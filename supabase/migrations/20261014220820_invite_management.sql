-- Managing invites (#9): any member can revoke an invite link or cancel a
-- pending invitation; both show up in the group's history with who did it,
-- and the lists update live.

------------------------------------------------------------------------------
-- Revoking a link is one-way
------------------------------------------------------------------------------

-- Members could already set revoked_at (column grant), but also set it back
-- to null and revive a link. Now the first revoke sticks and the server
-- picks the time.
create function public.guard_invite_link_revoke() returns trigger
language plpgsql set search_path = '' as $$
begin
  if old.revoked_at is not null and new.revoked_at is distinct from old.revoked_at then
    raise exception 'this invite link is already revoked';
  end if;
  if old.revoked_at is null and new.revoked_at is not null then
    new.revoked_at := now();
  end if;
  return new;
end $$;

revoke execute on function public.guard_invite_link_revoke() from public, anon, authenticated;

create trigger group_invite_links_guard_revoke before update on public.group_invite_links
  for each row execute function public.guard_invite_link_revoke();

------------------------------------------------------------------------------
-- Cancelling an invitation
------------------------------------------------------------------------------

alter table public.group_invitations drop constraint group_invitations_status_check,
  add constraint group_invitations_status_check
  check (status in ('pending', 'accepted', 'declined', 'cancelled'));

-- Any member of the group may cancel a pending invitation. The invitee's
-- notification then reads "Cancelled" (list_notifications shows the status).
create function public.cancel_invitation(p_invitation uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  update public.group_invitations
     set status = 'cancelled', responded_at = now()
   where id = p_invitation and status = 'pending' and public.is_group_member(group_id);
  if not found then
    raise exception 'invitation not found';
  end if;
end $$;

revoke execute on function public.cancel_invitation(uuid) from public, anon;
grant execute on function public.cancel_invitation(uuid) to authenticated;

------------------------------------------------------------------------------
-- History: who created or revoked links, who invited or cancelled
------------------------------------------------------------------------------

create trigger log_group_invite_links after insert or update on public.group_invite_links
  for each row execute function public.log_change('invite_link', 'id');
create trigger log_group_invitations after insert or update on public.group_invitations
  for each row execute function public.log_change('invitation', 'id');

-- Same as before (20261014203717), plus: invitation lines name the invitee,
-- link codes never leave the database, and bookkeeping on links and
-- invitations is left out (a join through a link only bumps its use count;
-- an accepted invitation is already told by "joined the group").
create or replace function public.list_group_history(
  p_group uuid, p_before bigint default null, p_limit int default 50
)
returns table (
  id              bigint,
  created_at      timestamptz,
  entity_type     text,
  entity_id       uuid,
  action          text,
  before          jsonb,
  after           jsonb,
  actor_id        uuid,
  actor_username  text,
  subject_name    text,  -- the activity, plan, type or merged label it's about
  person_username text,  -- the member, participant or invitee it's about
  from_type_name  text,
  to_type_name    text,
  event_title     text,  -- a plan's own name, kept when an activity replaces the event
  entry_id        uuid,  -- the plan, while it still exists
  entry_all_day   boolean,
  entry_date      date,
  entry_start_at  timestamptz,
  entry_end_at    timestamptz
)
language sql stable security definer set search_path = '' as $$
  select cl.id, cl.created_at, cl.entity_type, cl.entity_id, cl.action,
         case cl.entity_type
           when 'activity' then cl.before - 'personal_type_id'
           when 'invite_link' then cl.before - 'token'
           else cl.before end,
         case cl.entity_type
           when 'activity' then cl.after - 'personal_type_id'
           when 'invite_link' then cl.after - 'token'
           else cl.after end,
         cl.actor_id, actor.username,
         case
           when cl.entity_type in ('activity', 'activity_photo', 'group_activity') then act.name
           when cl.entity_type in ('schedule_entry', 'schedule_participant')
             then coalesce(entry_act.name, se.title, snap_act.name, cl.before ->> 'title', cl.after ->> 'title')
           when cl.entity_type = 'activity_type' then coalesce(cl.after ->> 'name', cl.before ->> 'name')
           -- An updated rule's snapshot holds only the new target; its label is on the rule.
           when cl.entity_type = 'type_merge'
             then coalesce(cl.after ->> 'source_name', cl.before ->> 'source_name', tm.source_name)
         end,
         person.username,
         from_t.name, to_t.name,
         se.title, se.id, se.all_day, se.date, se.start_at, se.end_at
  from public.change_log cl
  left join public.profiles actor on actor.id = cl.actor_id
  -- Activity names only while the caller can still see the activity.
  left join public.activities act
         on cl.entity_type in ('activity', 'activity_photo', 'group_activity')
        and act.id = cl.entity_id
        and public.can_access_activity(act.id)
  left join public.schedule_entries se
         on cl.entity_type in ('schedule_entry', 'schedule_participant')
        and se.id = cl.entity_id and se.group_id = p_group
  left join public.activities entry_act on entry_act.id = se.activity_id
  -- A removed plan's activity, from the log's snapshot of the plan.
  left join public.activities snap_act
         on se.id is null
        and cl.entity_type = 'schedule_entry'
        and snap_act.id = public.try_uuid(coalesce(cl.before, cl.after) ->> 'activity_id')
        and public.can_access_activity(snap_act.id)
  left join public.type_merges tm
         on cl.entity_type = 'type_merge' and tm.id = cl.entity_id and tm.group_id = p_group
  -- An invitation's status change only logs the status; the invitee is on the row.
  left join public.group_invitations gi
         on cl.entity_type = 'invitation' and gi.id = cl.entity_id and gi.group_id = p_group
  left join public.profiles person
         on person.id = case cl.entity_type
                          when 'group_member' then cl.entity_id
                          when 'schedule_participant' then public.try_uuid(coalesce(cl.after, cl.before) ->> 'user_id')
                          when 'invitation' then coalesce(public.try_uuid(cl.after ->> 'invitee_id'), gi.invitee_id)
                        end
  left join public.activity_types from_t
         on cl.entity_type = 'group_activity'
        and from_t.id = public.try_uuid(cl.before ->> 'type_id') and from_t.group_id = p_group
  left join public.activity_types to_t
         on cl.entity_type in ('group_activity', 'type_merge')
        and to_t.id = public.try_uuid(coalesce(cl.after ->> 'type_id', cl.after ->> 'target_type_id',
                                               cl.before ->> 'target_type_id'))
        and to_t.group_id = p_group
  where public.is_group_member(p_group)
    and (p_before is null or cl.id < p_before)
    and (cl.group_id = p_group
         -- Shared at the time: the latest share into this group before the
         -- edit has no removal between it and the edit. Log ids give the order
         -- (timestamps tie within a transaction).
         or (cl.entity_type in ('activity', 'activity_photo')
             and exists (
               select 1 from public.change_log s
               where s.entity_type = 'group_activity' and s.entity_id = cl.entity_id
                 and s.group_id = p_group and s.action = 'created' and s.id < cl.id
                 and not exists (
                   select 1 from public.change_log u
                   where u.entity_type = 'group_activity' and u.entity_id = cl.entity_id
                     and u.group_id = p_group and u.action = 'deleted'
                     and u.id > s.id and u.id < cl.id))))
    -- Bookkeeping, not something a person did: an edit that only changed the
    -- owner's private label, a label being cleared from a share (its type
    -- stays), a participant marked as clashing (the planner's clash_override
    -- row already says so), a link's use count going up, and an accepted
    -- invitation (the "joined" line says so).
    and not (cl.entity_type = 'activity' and cl.action = 'updated'
             and coalesce(cl.after - 'personal_type_id', '{}'::jsonb) = '{}'::jsonb)
    and not (cl.entity_type = 'group_activity' and cl.action = 'updated')
    and not (cl.entity_type = 'schedule_participant' and cl.action = 'updated'
             and cl.after ->> 'status' = 'clash')
    and not (cl.entity_type = 'invite_link' and cl.action = 'updated' and not (cl.after ? 'revoked_at'))
    and not (cl.entity_type = 'invitation' and cl.action = 'updated' and cl.after ->> 'status' = 'accepted')
  order by cl.id desc
  limit greatest(1, least(coalesce(p_limit, 50), 200));
$$;

------------------------------------------------------------------------------
-- Live updates: the group sees links and invitations change
------------------------------------------------------------------------------

-- Same as before (20261014210549), plus: invite links go to their group, and
-- invitations to the group as well as the invitee.
create or replace function public.broadcast_change() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  r       jsonb := to_jsonb(coalesce(new, old));
  v_group uuid;
  topics  text[];
  t       text;
  sent    text := coalesce(current_setting('easyplan.broadcasts_sent', true), '');
  k       text;
begin
  case tg_table_name
    when 'groups' then
      topics := array['group:' || (r ->> 'id')];
    when 'group_members' then
      topics := array['group:' || (r ->> 'group_id'), 'user:' || (r ->> 'user_id')];
    when 'group_activities', 'activity_types', 'type_merges', 'group_invite_links' then
      topics := array['group:' || (r ->> 'group_id')];
    when 'schedule_entries' then
      -- Participants too: someone who left the group can still be on its plans.
      topics := array['group:' || (r ->> 'group_id')]
             || array(select 'user:' || sp.user_id from public.schedule_participants sp
                      where sp.entry_id = (r ->> 'id')::uuid);
    when 'schedule_participants' then
      topics := array['user:' || (r ->> 'user_id')];
      -- Null when the plan itself is being deleted; its own trigger covers the group.
      v_group := public.entry_group((r ->> 'entry_id')::uuid);
      if v_group is not null then
        topics := topics || ('group:' || v_group);
      end if;
    when 'activities', 'activity_photos' then
      select array['user:' || a.owner_id]
             || array(select 'group:' || ga.group_id from public.group_activities ga where ga.activity_id = a.id)
        into topics
        from public.activities a
       where a.id = coalesce(r ->> 'activity_id', r ->> 'id')::uuid;
    when 'notifications' then
      topics := array['user:' || (r ->> 'user_id')];
    when 'group_invitations' then
      -- The invitee's pending list, and the group's list of sent invitations.
      topics := array['user:' || (r ->> 'invitee_id'), 'group:' || (r ->> 'group_id')];
  end case;

  -- One message per topic and table per transaction is enough: listeners only
  -- see messages after commit, and they re-fetch everything for that table.
  foreach t in array coalesce(topics, '{}') loop
    k := '|' || t || '/' || tg_table_name || '|';
    continue when position(k in sent) > 0;
    sent := sent || k;
    perform realtime.send(jsonb_build_object('table', tg_table_name), 'changed', t, true);
  end loop;
  perform set_config('easyplan.broadcasts_sent', sent, true);
  return null;
end $$;

create trigger broadcast_group_invite_links after insert or update or delete on public.group_invite_links
  for each row execute function public.broadcast_change();

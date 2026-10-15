-- #17: group history shows one line for an action across a series (e.g. a
-- 12-week plan created, or moved from a date on), with how many dates it covered.
-- Same as 20261014220820 otherwise, plus the repeat_count column.
drop function public.list_group_history(uuid, bigint, int);
create function public.list_group_history(
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
  entry_end_at    timestamptz,
  repeat_count    int    -- rows one action made across a series, shown as this one
)
language sql stable security definer set search_path = '' as $$
  with base (id, created_at, entity_type, entity_id, action, before, after, actor_id, actor_username, subject_name, person_username, from_type_name, to_type_name, event_title, entry_id, entry_all_day, entry_date, entry_start_at, entry_end_at, series_key) as (
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
           se.title, se.id, se.all_day, se.date, se.start_at, se.end_at,
           -- The plan's series: from the row's snapshot, the plan itself, or (once
           -- the plan is deleted) the snapshot logged when it was created.
           coalesce(cl.after ->> 'series_id', cl.before ->> 'series_id', se.series_id::text,
                    case when cl.entity_type in ('schedule_entry', 'schedule_participant') then
                      (select d.after ->> 'series_id' from public.change_log d
                        where d.entity_type = 'schedule_entry' and d.entity_id = cl.entity_id
                          and d.action = 'created' limit 1) end)
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
  )
  -- One action across a series (create, move, add people, ...) writes a row per
  -- occurrence in the same transaction; show the first and count the rest.
  select b.id, b.created_at, b.entity_type, b.entity_id, b.action, b.before, b.after, b.actor_id,
         b.actor_username, b.subject_name, b.person_username, b.from_type_name, b.to_type_name,
         b.event_title, b.entry_id, b.entry_all_day, b.entry_date, b.entry_start_at, b.entry_end_at,
         case when b.series_key is null then 1 else
           (select count(*)::int from base o where o.series_key = b.series_key and o.entity_type = b.entity_type and o.action = b.action
                and o.actor_id is not distinct from b.actor_id and o.created_at = b.created_at
                and o.person_username is not distinct from b.person_username) end
  from base b
  where b.series_key is null
     or not exists (select 1 from base o where o.series_key = b.series_key and o.entity_type = b.entity_type and o.action = b.action
                and o.actor_id is not distinct from b.actor_id and o.created_at = b.created_at
                and o.person_username is not distinct from b.person_username
                      and o.id < b.id)
  order by b.id desc
  limit greatest(1, least(coalesce(p_limit, 50), 200));
$$;
revoke execute on function public.list_group_history(uuid, bigint, int) from public, anon;
grant execute on function public.list_group_history(uuid, bigint, int) to authenticated;

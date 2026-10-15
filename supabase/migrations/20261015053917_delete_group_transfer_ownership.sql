-- #10: owners can delete a group and hand ownership to another member.

-- Deleting goes through delete_group so the people affected are always told;
-- clients can no longer delete group rows directly. (hand_over_ownership
-- still removes a group left with no members; it runs as the table owner.)
drop policy groups_delete on public.groups;

-- Turning a group's plans back into events when its activity list goes makes
-- no sense when the whole group is being deleted: the plans are going too,
-- and updating them failed (their group row is already gone). That broke
-- delete_group and the automatic delete of a group its last member leaves.
create or replace function public.revert_entries_to_events() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if not exists (select 1 from public.groups where id = old.group_id) then
    return old;
  end if;
  update public.schedule_entries se
     set title = coalesce(se.title, a.name), activity_id = null
    from public.activities a
   where a.id = old.activity_id
     and se.group_id = old.group_id
     and se.activity_id = old.activity_id;
  return old;
end $$;

-- What deleting would remove, for the confirmation dialog. Owner only.
create function public.group_deletion_summary(p_group uuid)
returns table (members int, upcoming_plans int, ideas int)
language plpgsql stable security definer set search_path = '' as $$
declare
  v_today date := (now() at time zone coalesce(
    (select timezone from public.profiles where id = auth.uid()), 'UTC'))::date;
begin
  if not public.is_group_owner(p_group) then
    raise exception 'only the owner can delete this group' using errcode = '42501';
  end if;
  return query
  select (select count(*)::int from public.group_members m where m.group_id = p_group),
         (select count(*)::int from public.schedule_entries se
           where se.group_id = p_group and (se.end_at > now() or se.date >= v_today)),
         (select count(*)::int from public.schedule_entries se
           where se.group_id = p_group and se.date is null and se.start_at is null);
end $$;

-- Deletes the group with its plans, types and invites (activities belong to
-- their owners and stay). Everyone who loses something is notified first:
-- members, and anyone in one of its plans. The name must be typed to confirm.
create function public.delete_group(p_group uuid, p_confirm_name text) returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_name text;
begin
  select name into v_name from public.groups where id = p_group;
  if v_name is null or not public.is_group_owner(p_group) then
    raise exception 'only the owner can delete this group' using errcode = '42501';
  end if;
  if lower(btrim(coalesce(p_confirm_name, ''))) <> lower(btrim(v_name)) then
    raise exception 'type the group''s name to confirm';
  end if;

  insert into public.notifications (user_id, kind, payload)
  select x.user_id, 'group_deleted', jsonb_build_object('group_name', v_name, 'by', auth.uid())
  from (select m.user_id from public.group_members m where m.group_id = p_group
        union
        select sp.user_id from public.schedule_participants sp
          join public.schedule_entries se on se.id = sp.entry_id
         where se.group_id = p_group) x
  where x.user_id <> auth.uid();

  delete from public.groups where id = p_group;
end $$;

-- Makes another member the owner straight away; the caller becomes a member.
-- Logged in group history and the new owner is notified.
create function public.transfer_ownership(p_group uuid, p_new_owner uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not public.is_group_owner(p_group) then
    raise exception 'only the owner can hand over the group' using errcode = '42501';
  end if;
  if p_new_owner = auth.uid() then
    raise exception 'you already own this group';
  end if;
  if not exists (select 1 from public.group_members where group_id = p_group and user_id = p_new_owner) then
    raise exception 'they''re not a member of this group';
  end if;

  update public.group_members set role = 'member' where group_id = p_group and user_id = auth.uid();
  update public.group_members set role = 'owner' where group_id = p_group and user_id = p_new_owner;

  -- Role changes aren't logged by the group_members trigger (insert/delete only).
  insert into public.change_log (actor_id, group_id, entity_type, entity_id, action, before, after)
  values (auth.uid(), p_group, 'group_member', p_new_owner, 'updated',
          jsonb_build_object('role', 'member'), jsonb_build_object('role', 'owner'));

  insert into public.notifications (user_id, kind, payload)
  values (p_new_owner, 'ownership_transferred', jsonb_build_object('group_id', p_group, 'by', auth.uid()));
end $$;

revoke execute on function public.group_deletion_summary(uuid), public.delete_group(uuid, text),
  public.transfer_ownership(uuid, uuid) from public, anon;
grant execute on function public.group_deletion_summary(uuid), public.delete_group(uuid, text),
  public.transfer_ownership(uuid, uuid) to authenticated;

-- list_notifications: a deleted group's name comes from the notification
-- itself (the group row is gone). Otherwise unchanged.
create or replace function public.list_notifications(p_limit int default 50)
returns table (
  id                uuid,
  kind              text,
  created_at        timestamptz,
  read_at           timestamptz,
  actor_id          uuid,
  actor_name        text,
  group_id          uuid,
  group_name        text,
  invitation_status text,
  entry_id          uuid,
  entry_title       text,
  entry_all_day     boolean,
  entry_date        date,
  entry_start_at    timestamptz,
  entry_end_at      timestamptz,
  clash_count       int
)
language sql stable security definer set search_path = '' as $$
  select n.id, n.kind, n.created_at, n.read_at,
         a.id, coalesce(a.display_name, a.username),
         g.id, coalesce(g.name, case when n.kind = 'group_deleted' then n.payload ->> 'group_name' end),
         i.status,
         se.id, coalesce(act.name, se.title), se.all_day, se.date, se.start_at, se.end_at,
         pg_catalog.jsonb_array_length(coalesce(n.payload -> 'clashes', '[]'::jsonb))
  from public.notifications n
  left join public.profiles a
         on a.id = public.try_uuid(coalesce(n.payload ->> 'invited_by', n.payload ->> 'by'))
  left join public.group_invitations i
         on n.kind = 'group_invitation' and i.id = public.try_uuid(n.payload ->> 'invitation_id')
  left join public.groups g
         on g.id = public.try_uuid(n.payload ->> 'group_id')
        and (public.is_group_member(g.id) or i.invitee_id = auth.uid())
  left join public.schedule_entries se
         on se.id = public.try_uuid(n.payload ->> 'entry_id')
        and (public.is_entry_participant(se.id) or public.is_group_member(se.group_id))
  left join public.activities act on act.id = se.activity_id
  where n.user_id = auth.uid()
  order by n.created_at desc, n.id
  limit greatest(1, least(coalesce(p_limit, 50), 200));
$$;

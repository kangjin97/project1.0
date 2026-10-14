-- list_notifications: the caller's notifications with what the screen needs
-- to describe them. Payloads only hold ids, and a client couldn't resolve all
-- of them through RLS (e.g. the plan of a group the caller has since left).
-- Plan and group details are shown only while the caller can still see them;
-- otherwise those columns are null and the app says "a plan" / "a group".
create function public.list_notifications(p_limit int default 50)
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
         g.id, g.name,
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

revoke execute on function public.list_notifications(int) from public, anon;
grant execute on function public.list_notifications(int) to authenticated;

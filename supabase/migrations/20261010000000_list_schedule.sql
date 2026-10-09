-- Read model for the schedule screens.
--
-- Entries mix all-day dates and timed ranges, and the screens need group,
-- activity and participant names alongside them, so one function returns
-- everything for a date window.

-- Entries in [p_from, p_to] (inclusive local dates in p_tz).
--   p_group null  → the caller's own schedule (entries they take part in)
--   p_group given → that group's whole schedule (caller must be a member);
--                   p_include_unscheduled also returns events with no date yet
create function public.list_schedule(
  p_from date,
  p_to date,
  p_tz text default 'UTC',
  p_group uuid default null,
  p_include_unscheduled boolean default false
) returns table (
  id uuid,
  group_id uuid,
  group_name text,
  activity_id uuid,
  activity_name text,
  title text,
  all_day boolean,
  date date,
  start_at timestamptz,
  end_at timestamptz,
  created_by uuid,
  my_status text,
  participants jsonb
)
language sql stable security definer set search_path = '' as $$
  select e.id, e.group_id, g.name, e.activity_id, a.name, e.title,
         e.all_day, e.date, e.start_at, e.end_at, e.created_by,
         me.status,
         coalesce((
           select jsonb_agg(jsonb_build_object(
                    'user_id', p.user_id, 'username', pr.username,
                    'display_name', pr.display_name, 'status', p.status)
                  order by pr.username)
           from public.schedule_participants p
           join public.profiles pr on pr.id = p.user_id
           where p.entry_id = e.id), '[]')
  from public.schedule_entries e
  join public.groups g on g.id = e.group_id
  left join public.activities a on a.id = e.activity_id
  left join public.schedule_participants me on me.entry_id = e.id and me.user_id = auth.uid()
  where auth.uid() is not null
    and case when p_group is null then me.user_id is not null
             else e.group_id = p_group and public.is_group_member(p_group) end
    and (
      (e.all_day and e.date between p_from and p_to)
      or (e.start_at is not null
          and tstzrange(e.start_at, e.end_at, '[)')
              && tstzrange(p_from::timestamp at time zone p_tz, (p_to + 1)::timestamp at time zone p_tz, '[)'))
      or (p_include_unscheduled and e.date is null and e.start_at is null)
    )
  order by coalesce(e.start_at, e.date::timestamp at time zone p_tz) nulls first, e.created_at;
$$;

revoke execute on function public.list_schedule(date, date, text, uuid, boolean) from public, anon;
grant execute on function public.list_schedule(date, date, text, uuid, boolean) to authenticated;

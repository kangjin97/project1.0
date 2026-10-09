-- Profile page: bio, avatars, shared groups, own stats.

alter table public.profiles add column bio text check (bio is null or length(bio) <= 160);
grant update (bio) on public.profiles to authenticated;

------------------------------------------------------------------------------
-- Avatars: private bucket at avatars/<user_id>/<file>. Any signed-in user can
-- view (profiles are visible to all signed-in users); only the owner writes.
------------------------------------------------------------------------------

insert into storage.buckets (id, name, public)
values ('avatars', 'avatars', false)
on conflict (id) do nothing;

create policy avatars_read on storage.objects for select to authenticated
  using (bucket_id = 'avatars');
create policy avatars_write on storage.objects for insert to authenticated
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);
create policy avatars_update on storage.objects for update to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);
create policy avatars_remove on storage.objects for delete to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

------------------------------------------------------------------------------
-- Groups the caller shares with another user (all their groups for themselves).
------------------------------------------------------------------------------

create function public.shared_groups(p_user uuid)
returns table (group_id uuid, group_name text, member_count bigint)
language sql stable security definer set search_path = '' as $$
  select g.id, g.name, (select count(*) from public.group_members m where m.group_id = g.id)
  from public.groups g
  join public.group_members me on me.group_id = g.id and me.user_id = auth.uid()
  join public.group_members them on them.group_id = g.id and them.user_id = p_user
  order by g.name;
$$;

------------------------------------------------------------------------------
-- The caller's own counts for their profile page.
------------------------------------------------------------------------------

create function public.my_profile_stats()
returns table (groups bigint, activities bigint, upcoming_plans bigint)
language sql stable security definer set search_path = '' as $$
  select
    (select count(*) from public.group_members where user_id = auth.uid()),
    (select count(*) from public.activities where owner_id = auth.uid() and deleted_at is null),
    (select count(*)
       from public.schedule_participants p
       join public.schedule_entries e on e.id = p.entry_id
       join public.profiles pr on pr.id = auth.uid()
      where p.user_id = auth.uid()
        and (e.end_at >= now() or (e.all_day and e.date >= (now() at time zone pr.timezone)::date)));
$$;

------------------------------------------------------------------------------
-- list_schedule: include participants' avatars.
------------------------------------------------------------------------------

create or replace function public.list_schedule(
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
                    'display_name', pr.display_name, 'avatar_path', pr.avatar_path,
                    'status', p.status)
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

revoke execute on function public.shared_groups(uuid), public.my_profile_stats() from public, anon;
grant execute on function public.shared_groups(uuid), public.my_profile_stats() to authenticated;

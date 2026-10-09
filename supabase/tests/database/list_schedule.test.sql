-- The schedule read model: personal vs group views, date windows, privacy.
begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data) values
  ('11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'ann@example.test', '{"username":"ann"}'),
  ('22222222-2222-2222-2222-222222222222', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'ben@example.test', '{"username":"ben"}'),
  ('33333333-3333-3333-3333-333333333333', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'cat@example.test', '{"username":"cat"}');

create function pg_temp.act_as(p uuid) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated')::text, true);
$$;
grant execute on function pg_temp.act_as(uuid) to authenticated;

-- Ann's group with Ben; Cat is not a member.
select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
insert into groups (id, name, created_by)
values ('aaaaaaaa-0000-0000-0000-000000000001', 'Crew', '11111111-1111-1111-1111-111111111111');
insert into group_members (group_id, user_id)
values ('aaaaaaaa-0000-0000-0000-000000000001', '22222222-2222-2222-2222-222222222222');

set local role authenticated;
select pg_temp.act_as('11111111-1111-1111-1111-111111111111');

insert into activities (id, name) values ('b0000000-0000-0000-0000-000000000001', 'Hike');
insert into group_activities (group_id, activity_id, type_id)
select 'aaaaaaaa-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000001', id
from activity_types where group_id = 'aaaaaaaa-0000-0000-0000-000000000001' and name = 'Outdoors';

-- Timed hike for Ann + Ben (Singapore 9–11am on 10 Oct = 01:00–03:00 UTC).
select create_schedule_entry('aaaaaaaa-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000001', null,
  false, null, '2026-10-10 01:00+00', '2026-10-10 03:00+00',
  array['11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222']::uuid[]);
-- All-day event for Ann only on 12 Oct.
select create_schedule_entry('aaaaaaaa-0000-0000-0000-000000000001', null, 'Beach day',
  true, '2026-10-12', null, null, null);
-- Unscheduled idea.
select create_schedule_entry('aaaaaaaa-0000-0000-0000-000000000001', null, 'Karaoke sometime',
  false, null, null, null, null);

select is((select count(*)::int from list_schedule('2026-10-01', '2026-10-31', 'Asia/Singapore')),
          2, 'my schedule: timed + all-day, not the unscheduled idea');
select is((select activity_name from list_schedule('2026-10-10', '2026-10-10', 'Asia/Singapore') where activity_id is not null),
          'Hike', 'activity name is included');
select is((select jsonb_array_length(participants) from list_schedule('2026-10-10', '2026-10-10', 'Asia/Singapore')),
          2, 'participants are included');
select is((select count(*)::int from list_schedule('2026-10-11', '2026-10-11', 'Asia/Singapore')),
          0, 'window excludes other days');
select is((select count(*)::int from list_schedule('2026-10-09', '2026-10-09', 'America/Los_Angeles')),
          1, 'timed entries are matched in the caller''s time zone (10 Oct 01:00 UTC is 9 Oct in LA)');
select is((select count(*)::int from list_schedule('2026-10-01', '2026-10-31', 'UTC',
           'aaaaaaaa-0000-0000-0000-000000000001', true)),
          3, 'group schedule with unscheduled ideas');

-- Ben: only the hike is his; he still sees the whole group schedule.
select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
select is((select count(*)::int from list_schedule('2026-10-01', '2026-10-31', 'UTC')), 1, 'ben''s own schedule');
select is((select count(*)::int from list_schedule('2026-10-01', '2026-10-31', 'UTC', 'aaaaaaaa-0000-0000-0000-000000000001')),
          2, 'ben sees all scheduled group entries');
select ok((select my_status is null from list_schedule('2026-10-01', '2026-10-31', 'UTC', 'aaaaaaaa-0000-0000-0000-000000000001')
           where title = 'Beach day'), 'my_status is null for entries ben is not in');

-- Cat: not a member.
select pg_temp.act_as('33333333-3333-3333-3333-333333333333');
select is((select count(*)::int from list_schedule('2026-10-01', '2026-10-31', 'UTC', 'aaaaaaaa-0000-0000-0000-000000000001', true)),
          0, 'non-members see nothing of the group schedule');

select * from finish();
rollback;

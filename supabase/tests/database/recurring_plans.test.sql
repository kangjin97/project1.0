-- Recurring plans (#17).
begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data) values
  ('11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'ann@example.test', '{"username":"ann","timezone":"Europe/London"}'),
  ('22222222-2222-2222-2222-222222222222', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'ben@example.test', '{"username":"ben"}'),
  ('33333333-3333-3333-3333-333333333333', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'cat@example.test', '{"username":"cat"}'),
  ('44444444-4444-4444-4444-444444444444', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'eve@example.test', '{"username":"eve"}');

create function pg_temp.act_as(p uuid) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated')::text, true);
$$;
grant execute on function pg_temp.act_as(uuid) to authenticated;
create temp table ids (k text primary key, v uuid);
grant all on ids to authenticated;

-- The series' occurrences, in order, as the database stores them.
create function pg_temp.occ(p_series uuid) returns table (n bigint, id uuid, date date, start_at timestamptz, end_at timestamptz, title text)
language sql security definer as $$
  select row_number() over (order by coalesce(start_at, date::timestamptz)), id, date, start_at, end_at, title
  from public.schedule_entries where series_id = p_series order by 1;
$$;
grant execute on function pg_temp.occ(uuid) to authenticated;

reset role;
insert into groups (id, name, created_by) values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'Crew', '11111111-1111-1111-1111-111111111111');
insert into group_members (group_id, user_id) values
  ('aaaaaaaa-0000-0000-0000-000000000001', '22222222-2222-2222-2222-222222222222'),
  ('aaaaaaaa-0000-0000-0000-000000000001', '33333333-3333-3333-3333-333333333333');

set local role anon;
select throws_ok($$ select public.create_schedule_series('aaaaaaaa-0000-0000-0000-000000000001', null, 'x', true,
  '2026-11-01', null, null, null, 'weekly', '2026-12-01') $$, '42501', null, 'signed-out callers can''t create series');

set local role authenticated;
select pg_temp.act_as('44444444-4444-4444-4444-444444444444');
select throws_ok($$ select public.create_schedule_series('aaaaaaaa-0000-0000-0000-000000000001', null, 'x', true,
  '2026-11-01', null, null, null, 'weekly', '2026-12-01') $$, 'P0001', 'not a member of this group', 'non-members can''t');

-- Ben already has something on the second Friday evening.
select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
insert into ids select 'busy', (create_schedule_entry('aaaaaaaa-0000-0000-0000-000000000001', null, 'Busy thing',
  false, null, '2026-10-23 18:30+00', '2026-10-23 19:30+00', array['22222222-2222-2222-2222-222222222222']::uuid[]) ->> 'entry_id')::uuid;

-- Ann (Europe/London) plans Game night, Fridays 7–9pm London, until 6 Nov:
-- 16, 23, 30 Oct and 6 Nov. Clocks go back on 25 Oct, so UTC moves an hour.
select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select throws_ok($$ select public.create_schedule_series('aaaaaaaa-0000-0000-0000-000000000001', null, 'Game night', false,
  null, '2026-10-16 18:00+00', '2026-10-16 20:00+00', null, 'weekly', '2027-11-01') $$,
  'P0001', 'repeats can end at most a year after the first date', 'at most a year');
select throws_ok($$ select public.create_schedule_series('aaaaaaaa-0000-0000-0000-000000000001', null, 'Game night', false,
  null, '2026-10-16 18:00+00', '2026-10-16 20:00+00', null, 'weekly', '2026-10-20') $$,
  'P0001', 'a repeating plan needs at least two dates before it ends', 'at least two dates');
select throws_ok($$ select public.create_schedule_series('aaaaaaaa-0000-0000-0000-000000000001', null, 'Idea', false,
  null, null, null, null, 'weekly', '2026-12-01') $$,
  'P0001', 'a repeating plan needs a date', 'ideas with no date can''t repeat');
select throws_ok($$ select public.create_schedule_series('aaaaaaaa-0000-0000-0000-000000000001', null, 'x', true,
  '2026-11-01', null, null, null, 'daily', '2026-12-01') $$,
  'P0001', 'choose how often it repeats', 'only weekly, every 2 weeks or monthly');

select is((public.create_schedule_series('aaaaaaaa-0000-0000-0000-000000000001', null, 'Game night', false,
  null, '2026-10-16 18:00+00', '2026-10-16 20:00+00',
  array['11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222']::uuid[],
  'weekly', '2026-11-06')) ->> 'status', 'clash', 'a clash on any date stops the save');
select is((select count(*)::int from schedule_series), 0, 'nothing saved on clash');

insert into ids select 'series', (public.create_schedule_series('aaaaaaaa-0000-0000-0000-000000000001', null, 'Game night', false,
  null, '2026-10-16 18:00+00', '2026-10-16 20:00+00',
  array['11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222']::uuid[],
  'weekly', '2026-11-06', true) ->> 'series_id')::uuid;

select results_eq(
  $$ select start_at, end_at from pg_temp.occ((select v from ids where k = 'series')) $$,
  $$ values ('2026-10-16 18:00+00'::timestamptz, '2026-10-16 20:00+00'::timestamptz),
            ('2026-10-23 18:00+00', '2026-10-23 20:00+00'),
            ('2026-10-30 19:00+00', '2026-10-30 21:00+00'),
            ('2026-11-06 19:00+00', '2026-11-06 21:00+00') $$,
  'weekly at the same London time across the clock change');
select results_eq(
  $$ select sp.user_id, sp.status from schedule_participants sp
     join pg_temp.occ((select v from ids where k = 'series')) o on o.id = sp.entry_id where o.n = 2 order by 1 $$,
  $$ values ('11111111-1111-1111-1111-111111111111'::uuid, 'added'), ('22222222-2222-2222-2222-222222222222'::uuid, 'clash') $$,
  'only the clashing date marks Ben as clashing');

select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
select results_eq(
  $$ select kind, entry_title, series_freq, series_until, clash_count, entry_start_at from public.list_notifications()
     where kind in ('added_to_series', 'added_to_entry', 'schedule_clash') $$,
  $$ values ('added_to_series', 'Game night', 'weekly', '2026-11-06'::date, 1, '2026-10-16 18:00+00'::timestamptz) $$,
  'one notification for the whole series, pointing at its first date, with the clash');
select results_eq(
  $$ select series_freq, series_until from public.list_schedule('2026-10-16', '2026-10-16', 'Europe/London') $$,
  $$ values ('weekly', '2026-11-06'::date) $$, 'plans carry their series details');

-- Group history: one line per action across the series, with how many dates.
select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select results_eq(
  $$ select entity_type, action, person_username, repeat_count from public.list_group_history('aaaaaaaa-0000-0000-0000-000000000001')
     where entity_type in ('schedule_entry', 'schedule_participant') and coalesce(subject_name, '') = 'Game night'
     order by id $$,
  $$ values ('schedule_entry', 'created', null::text, 4), ('schedule_participant', 'created', 'ann', 4),
            ('schedule_participant', 'created', 'ben', 4), ('schedule_entry', 'clash_override', null, 1) $$,
  'creating a 4-date series is one "planned" line and one line per person');

-- Monthly on the 31st falls back to the last day of shorter months.
select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
insert into ids select 'monthly', (public.create_schedule_series('aaaaaaaa-0000-0000-0000-000000000001', null, 'Book club', true,
  '2027-01-31', null, null, null, 'monthly', '2027-04-30') ->> 'series_id')::uuid;
select results_eq($$ select date from pg_temp.occ((select v from ids where k = 'monthly')) $$,
  $$ values ('2027-01-31'::date), ('2027-02-28'), ('2027-03-31'), ('2027-04-30') $$, 'monthly on the same date, clamped');

-- This and following: move from the 2nd date an hour later (8–10pm London).
select is((public.reschedule_following((select id from pg_temp.occ((select v from ids where k = 'series')) where n = 2),
  false, null, '2026-10-23 19:00+00', '2026-10-23 21:00+00', true)) ->> 'count', '3', 'three occurrences moved');
select results_eq(
  $$ select start_at from pg_temp.occ((select v from ids where k = 'series')) $$,
  $$ values ('2026-10-16 18:00+00'::timestamptz), ('2026-10-23 19:00+00'), ('2026-10-30 20:00+00'), ('2026-11-06 20:00+00') $$,
  'the first date stays; later ones shift by the same wall-clock hour');
select is((select repeat_count from public.list_group_history('aaaaaaaa-0000-0000-0000-000000000001')
            where entity_type = 'schedule_entry' and action = 'updated' order by id desc limit 1), 3,
          'moving from the 2nd date is one history line covering 3 dates');

-- Add Cat from the 3rd date: one notification.
select is((public.add_participants_following((select id from pg_temp.occ((select v from ids where k = 'series')) where n = 3),
  array['33333333-3333-3333-3333-333333333333']::uuid[])) ->> 'count', '2', 'Cat added to two dates');
select is((select count(*)::int from schedule_participants sp join pg_temp.occ((select v from ids where k = 'series')) o
            on o.id = sp.entry_id where sp.user_id = '33333333-3333-3333-3333-333333333333'), 2, 'only the 3rd and 4th');
reset role;
select is((select count(*)::int from notifications where user_id = '33333333-3333-3333-3333-333333333333'), 1,
          'Cat gets a single notification');
set local role authenticated;

-- Rename from the 4th; leave from the 3rd (Ben); delete from the 4th.
select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select is(public.rename_following((select id from pg_temp.occ((select v from ids where k = 'series')) where n = 4), 'Games!'), 1,
          'rename applies from that date');
select results_eq($$ select title from pg_temp.occ((select v from ids where k = 'series')) $$,
  $$ values ('Game night'), ('Game night'), ('Game night'), ('Games!') $$, 'earlier dates keep their name');

select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
select is(public.leave_following((select id from pg_temp.occ((select v from ids where k = 'series')) where n = 3)), 2,
          'Ben leaves the 3rd and 4th');
select is((select count(*)::int from schedule_participants sp join pg_temp.occ((select v from ids where k = 'series')) o
            on o.id = sp.entry_id where sp.user_id = auth.uid()), 2, 'and stays on the first two');

select pg_temp.act_as('44444444-4444-4444-4444-444444444444');
select throws_ok($$ select public.delete_following((select id from pg_temp.occ((select v from ids where k = 'series')) where n = 4)) $$,
                 'P0001', 'not a member of this group', 'non-members can''t delete');
select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select is(public.delete_following((select id from pg_temp.occ((select v from ids where k = 'series')) where n = 4)), 1,
          'delete from the last date');
select is((select count(*)::int from pg_temp.occ((select v from ids where k = 'series'))), 3, 'three dates left');
-- History of deleted dates still groups (the plans are gone, their log isn't).
select is((select count(*)::int from public.list_group_history('aaaaaaaa-0000-0000-0000-000000000001')
            where entity_type = 'schedule_participant' and action = 'created' and person_username = 'ben'
              and entity_id <> (select v from ids where k = 'busy')), 1,
          'Ben being added to the series is still one line after a date is deleted');

-- Extend: later end date adds dates copying the last one; at most a year from today.
select throws_ok($$ select public.extend_series((select id from pg_temp.occ((select v from ids where k = 'series')) where n = 1),
  (current_date + 400)) $$, 'P0001', 'repeats can end at most a year from today', 'extend is capped');
select is((public.extend_series((select id from pg_temp.occ((select v from ids where k = 'series')) where n = 1),
  '2026-11-20', true)) ->> 'count', '3', 'extending to 20 Nov adds 6, 13 and 20 Nov');
select results_eq($$ select start_at, title from pg_temp.occ((select v from ids where k = 'series')) where n > 3 $$,
  $$ values ('2026-11-06 20:00+00'::timestamptz, 'Game night'), ('2026-11-13 20:00+00', 'Game night'),
            ('2026-11-20 20:00+00', 'Game night') $$,
  'new dates follow the last one''s time and name');
select is((select until from schedule_series where id = (select v from ids where k = 'series')), '2026-11-20'::date,
          'the series end moves');

-- Plain (non-series) plans: "following" means just that one.
select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
select is(public.rename_following((select v from ids where k = 'busy'), 'Renamed'), 1, 'a single plan is its own scope');

select * from finish();
rollback;

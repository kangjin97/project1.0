-- Group history: list_group_history (#8).
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
create temp table ids (k text primary key, v uuid);
grant all on ids to authenticated;

set local role anon;
select throws_ok($$ select * from public.list_group_history('aaaaaaaa-0000-0000-0000-000000000001') $$,
                 '42501', null, 'signed-out callers can''t read group history');

set local role authenticated;

-- Ann creates "Crew" and an activity, and fixes its price before sharing it.
select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
insert into groups (id, name, created_by) values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'Crew', '11111111-1111-1111-1111-111111111111');
with x as (insert into activities (name, price_min, price_max) values ('Beach day', 0, 10) returning id)
insert into ids select 'beach', id from x;
update activities set price_max = 20 where id = (select v from ids where k = 'beach');

insert into group_activities (group_id, activity_id, type_id)
select 'aaaaaaaa-0000-0000-0000-000000000001', v,
       (select id from activity_types where group_id = 'aaaaaaaa-0000-0000-0000-000000000001' and name = 'Food')
from ids where k = 'beach';

-- Ann invites Ben, who joins, raises the price and moves it to Outdoors.
with x as (
  insert into group_invitations (group_id, invitee_id, invited_by)
  values ('aaaaaaaa-0000-0000-0000-000000000001', '22222222-2222-2222-2222-222222222222', auth.uid())
  returning id)
insert into ids select 'inv', id from x;

select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
select respond_to_invitation((select v from ids where k = 'inv'), true);
update activities set price_max = 30 where id = (select v from ids where k = 'beach');
update group_activities
   set type_id = (select id from activity_types where group_id = 'aaaaaaaa-0000-0000-0000-000000000001' and name = 'Outdoors')
 where activity_id = (select v from ids where k = 'beach');

-- Ann labels it "yummy" and changes the price in the same edit; the label
-- re-files it into a new "yummy" type.
select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
with x as (insert into personal_types (name) values ('yummy') returning id) insert into ids select 'yummy', id from x;
update activities set personal_type_id = (select v from ids where k = 'yummy'), price_max = 40
 where id = (select v from ids where k = 'beach');

-- Ann plans a picnic with Ben, who then leaves it.
insert into ids select 'picnic', (create_schedule_entry('aaaaaaaa-0000-0000-0000-000000000001', null, 'Picnic',
  true, '2026-11-01', null, null,
  array['11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222']::uuid[]) ->> 'entry_id')::uuid;
select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
delete from schedule_participants where entry_id = (select v from ids where k = 'picnic') and user_id = auth.uid();

-- Ben merges "yummy" into Food.
select merge_types('aaaaaaaa-0000-0000-0000-000000000001',
  array[(select id from activity_types where group_id = 'aaaaaaaa-0000-0000-0000-000000000001' and name = 'yummy')],
  (select id from activity_types where group_id = 'aaaaaaaa-0000-0000-0000-000000000001' and name = 'Food'));

-- What Ben, a member, sees.
select is((select count(*)::int from public.list_group_history('aaaaaaaa-0000-0000-0000-000000000001')
            where entity_type = 'activity_type' and action = 'created'), 5,
          'members see the whole history, including from before they joined (4 starter types + yummy)');
select results_eq(
  $$ select actor_username, person_username from public.list_group_history('aaaaaaaa-0000-0000-0000-000000000001')
      where entity_type = 'group_member' and action = 'created' order by id $$,
  $$ values ('ann'::text, 'ann'::text), ('ben', 'ben') $$,
  'joins name who joined');
select results_eq(
  $$ select actor_username, subject_name, to_type_name from public.list_group_history('aaaaaaaa-0000-0000-0000-000000000001')
      where entity_type = 'group_activity' and action = 'created' $$,
  $$ values ('ann'::text, 'Beach day'::text, 'Food'::text) $$,
  'a share names the activity and the type it was filed under');
select results_eq(
  $$ select actor_username, from_type_name, to_type_name from public.list_group_history('aaaaaaaa-0000-0000-0000-000000000001')
      where entity_type = 'group_activity' and action = 'type_changed' order by id $$,
  $$ values ('ben'::text, 'Food'::text, 'Outdoors'::text), ('ann', 'Outdoors', null), ('ben', null, 'Food') $$,
  'type changes name the old and new types (null once a type is merged away)');

-- Activity edits: only those made while shared, and never the owner's label.
select results_eq(
  $$ select actor_username, subject_name, after from public.list_group_history('aaaaaaaa-0000-0000-0000-000000000001')
      where entity_type = 'activity' order by id $$,
  $$ values ('ben'::text, 'Beach day'::text, '{"price_max": 30}'::jsonb), ('ann', 'Beach day', '{"price_max": 40}') $$,
  'edits made while shared are listed; the edit from before sharing is not');
select is((select count(*)::int from public.list_group_history('aaaaaaaa-0000-0000-0000-000000000001')
            where before ? 'personal_type_id' or after ? 'personal_type_id'), 0,
          'the owner''s private label never appears');

select results_eq(
  $$ select entity_type, action, actor_username, subject_name, person_username
       from public.list_group_history('aaaaaaaa-0000-0000-0000-000000000001')
      where entity_type in ('schedule_entry', 'schedule_participant') order by id $$,
  $$ values ('schedule_entry'::text, 'created'::text, 'ann'::text, 'Picnic'::text, null::text),
            ('schedule_participant', 'created', 'ann', 'Picnic', 'ann'),
            ('schedule_participant', 'created', 'ann', 'Picnic', 'ben'),
            ('schedule_participant', 'deleted', 'ben', 'Picnic', 'ben') $$,
  'plans and their participants are named');
select is((select event_title from public.list_group_history('aaaaaaaa-0000-0000-0000-000000000001')
            where entity_type = 'schedule_entry' and action = 'created'), 'Picnic',
          'plans carry their own name, kept for when an activity replaces the event');
select results_eq(
  $$ select distinct entry_id, entry_all_day, entry_date, entry_start_at from public.list_group_history('aaaaaaaa-0000-0000-0000-000000000001')
      where entity_type in ('schedule_entry', 'schedule_participant') $$,
  $$ select v, true, '2026-11-01'::date, null::timestamptz from ids where k = 'picnic' $$,
  'plan lines carry the plan and its timing, so the app can open it');
select results_eq(
  $$ select actor_username, subject_name, to_type_name from public.list_group_history('aaaaaaaa-0000-0000-0000-000000000001')
      where entity_type = 'type_merge' $$,
  $$ values ('ben'::text, 'yummy'::text, 'Food'::text) $$,
  'a merge names the label and its target');

-- Order and paging.
select is((select bool_and(id < prev) from (
            select id, lag(id) over (order by id desc) as prev
            from public.list_group_history('aaaaaaaa-0000-0000-0000-000000000001')) t where prev is not null),
          true, 'newest first');
create temp table page1 as select * from public.list_group_history('aaaaaaaa-0000-0000-0000-000000000001', null, 3);
select is((select count(*)::int from page1), 3, 'the limit is applied');
select results_eq(
  $$ select id from public.list_group_history('aaaaaaaa-0000-0000-0000-000000000001',
                                              (select min(id) from page1), 3) $$,
  $$ select id from public.list_group_history('aaaaaaaa-0000-0000-0000-000000000001') offset 3 limit 3 $$,
  'the next page carries on after the previous one');
select is((select count(*)::int from public.list_group_history('aaaaaaaa-0000-0000-0000-000000000001', null, 0)), 1,
          'the limit is at least 1');

-- Outsiders see nothing.
select pg_temp.act_as('33333333-3333-3333-3333-333333333333');
select is((select count(*)::int from public.list_group_history('aaaaaaaa-0000-0000-0000-000000000001')), 0,
          'non-members see no history');

-- Ben leaves: he stops seeing it, and Ann sees that he left.
select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
delete from group_members where group_id = 'aaaaaaaa-0000-0000-0000-000000000001' and user_id = auth.uid();
select is((select count(*)::int from public.list_group_history('aaaaaaaa-0000-0000-0000-000000000001')), 0,
          'former members see no history');
select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select results_eq(
  $$ select actor_username, person_username from public.list_group_history('aaaaaaaa-0000-0000-0000-000000000001')
      where entity_type = 'group_member' and action = 'deleted' $$,
  $$ values ('ben'::text, 'ben'::text) $$,
  'leaving is listed with who left');

-- A second activity goes in, out and back in: only edits made while it was in
-- the group are listed.
with x as (insert into activities (name, price_min, price_max) values ('Kayak', 0, 1) returning id)
insert into ids select 'kayak', id from x;
insert into group_activities (group_id, activity_id, type_id)
select 'aaaaaaaa-0000-0000-0000-000000000001', v,
       (select id from activity_types where group_id = 'aaaaaaaa-0000-0000-0000-000000000001' and name = 'Outdoors')
from ids where k = 'kayak';
update activities set price_max = 2 where id = (select v from ids where k = 'kayak');
delete from group_activities where activity_id = (select v from ids where k = 'kayak');
update activities set price_max = 3 where id = (select v from ids where k = 'kayak');
insert into group_activities (group_id, activity_id, type_id)
select 'aaaaaaaa-0000-0000-0000-000000000001', v,
       (select id from activity_types where group_id = 'aaaaaaaa-0000-0000-0000-000000000001' and name = 'Outdoors')
from ids where k = 'kayak';
update activities set price_max = 4 where id = (select v from ids where k = 'kayak');
select results_eq(
  $$ select after from public.list_group_history('aaaaaaaa-0000-0000-0000-000000000001')
      where entity_type = 'activity' and entity_id = (select v from ids where k = 'kayak') order by id $$,
  $$ values ('{"price_max": 2}'::jsonb), ('{"price_max": 4}') $$,
  'edits made while it was out of the group are not listed');

-- Ann deletes Beach day: its removal is listed, the edits made while it was
-- shared stay listed, and its name is no longer shown.
select delete_activity((select v from ids where k = 'beach'));
select is((select count(*)::int from public.list_group_history('aaaaaaaa-0000-0000-0000-000000000001')
            where entity_type = 'group_activity' and action = 'deleted'
              and entity_id = (select v from ids where k = 'beach')), 1, 'removing it from the group is listed');
select is((select count(*)::int from public.list_group_history('aaaaaaaa-0000-0000-0000-000000000001')
            where entity_type = 'activity' and entity_id = (select v from ids where k = 'beach')), 2,
          'edits made while it was shared stay listed after it leaves the group');
select is((select count(*)::int from public.list_group_history('aaaaaaaa-0000-0000-0000-000000000001')
            where entity_id = (select v from ids where k = 'beach') and subject_name is not null), 0,
          'a deleted activity''s name is no longer shown');

select * from finish();
rollback;

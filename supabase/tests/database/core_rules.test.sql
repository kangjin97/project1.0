-- Exercises the product rules in SPEC.md as real users through RLS.
-- Run with: supabase test db
begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

-- Three users: alice, bob, carol
insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data) values
  ('11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'alice@example.test', '{"username":"Alice"}'),
  ('22222222-2222-2222-2222-222222222222', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'bob@example.test',   '{"username":"bob"}'),
  ('33333333-3333-3333-3333-333333333333', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'carol@example.test', '{"username":"carol"}');

-- Scratch space for ids returned by RPCs
create temp table ids (k text primary key, v uuid);
grant all on ids to authenticated;

create function pg_temp.act_as(p uuid) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated')::text, true);
$$;
grant execute on function pg_temp.act_as(uuid) to authenticated;

select is((select username from profiles where id = '11111111-1111-1111-1111-111111111111'),
          'alice', 'profile is created on sign-up with a lower-cased username');

------------------------------------------------------------------------------
-- Groups & invites
------------------------------------------------------------------------------
set local role authenticated;
select pg_temp.act_as('11111111-1111-1111-1111-111111111111');

insert into groups (id, name) values ('aaaaaaaa-0000-0000-0000-000000000001', 'Weekend crew');
select is((select role from group_members where group_id = 'aaaaaaaa-0000-0000-0000-000000000001'
           and user_id = auth.uid()), 'owner', 'creator becomes group owner');
select is((select count(*)::int from activity_types where group_id = 'aaaaaaaa-0000-0000-0000-000000000001'),
          4, 'new group gets starter activity types');

select is((select username from find_user_by_email('BOB@example.test')), 'bob', 'find a user by email');
insert into group_invitations (group_id, invitee_id)
values ('aaaaaaaa-0000-0000-0000-000000000001', '22222222-2222-2222-2222-222222222222');
insert into group_invite_links (group_id) values ('aaaaaaaa-0000-0000-0000-000000000001');
insert into ids select 'link', id from group_invite_links;

select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
select is((select count(*)::int from groups), 1, 'invitee can see the group they were invited to');
select is((select count(*)::int from group_members), 0, 'invitee cannot see members before joining');
select is((select count(*)::int from notifications where kind = 'group_invitation'), 1, 'invitee is notified');
select lives_ok($$ select respond_to_invitation((select id from group_invitations), true) $$, 'bob accepts');
select is((select count(*)::int from group_members), 2, 'bob is now a member');

select set_config('test.token', (select token from group_invite_links), true);

select pg_temp.act_as('33333333-3333-3333-3333-333333333333');
select is((select count(*)::int from group_invite_links), 0, 'non-members cannot read invite links');
select is((select group_name from preview_invite_link(current_setting('test.token'))), 'Weekend crew', 'link preview shows the group name');
select is(join_group_via_link(current_setting('test.token')), 'aaaaaaaa-0000-0000-0000-000000000001'::uuid, 'carol joins via link');
select throws_ok($$ select join_group_via_link('nope') $$, 'invite link is invalid or expired');

------------------------------------------------------------------------------
-- Activities: private until shared, then editable by everyone
------------------------------------------------------------------------------
select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
insert into activities (id, name, location, price_min, price_max)
values ('bbbbbbbb-0000-0000-0000-000000000001', 'Steak at Burnt Ends', '7 Dempsey Rd', 80, 150);

select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
select is((select count(*)::int from activities), 0, 'activity is private before sharing');

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
insert into group_activities (group_id, activity_id, type_id)
select 'aaaaaaaa-0000-0000-0000-000000000001', 'bbbbbbbb-0000-0000-0000-000000000001', id
from activity_types where group_id = 'aaaaaaaa-0000-0000-0000-000000000001' and name = 'Food';

select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
select is((select count(*)::int from activities), 1, 'group members see shared activity');
update activities set price_max = 120 where id = 'bbbbbbbb-0000-0000-0000-000000000001';
select throws_ok($$ update activities set owner_id = auth.uid() $$, '42501', null, 'members cannot take ownership');
select throws_ok($$ select delete_activity('bbbbbbbb-0000-0000-0000-000000000001') $$,
                 'only the owner can delete this activity');
update group_activities set type_id = (select id from activity_types where name = 'Outdoors')
where activity_id = 'bbbbbbbb-0000-0000-0000-000000000001';

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select is((select price_max from activities), 120.00, 'owner sees the member''s edit');
select is((select updated_by from activities), '22222222-2222-2222-2222-222222222222'::uuid, 'last editor is recorded');
select is((select after ->> 'price_max' from change_log where entity_type = 'activity' and action = 'updated'),
          '120.00', 'activity edit is logged');
select is((select actor_id from change_log where action = 'type_changed'),
          '22222222-2222-2222-2222-222222222222'::uuid, 'type change is logged with who did it');

------------------------------------------------------------------------------
-- Schedules & clash detection
------------------------------------------------------------------------------
-- Bob puts an all-day event on Sat 10 Oct.
select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
insert into ids select 'bob_event', (create_schedule_entry(
  'aaaaaaaa-0000-0000-0000-000000000001', null, 'eat some steak', true, '2026-10-10', null, null,
  array['22222222-2222-2222-2222-222222222222']::uuid[]) ->> 'entry_id')::uuid;
select is((select status from schedule_participants where entry_id = (select v from ids where k = 'bob_event')),
          'added', 'event added to bob''s schedule');

-- An unscheduled event never clashes.
select is(create_schedule_entry('aaaaaaaa-0000-0000-0000-000000000001', null, 'karaoke sometime',
          false, null, null, null, null) ->> 'status', 'created', 'unscheduled event is allowed');

-- Alice plans steak 7-9pm that day for herself and bob.
select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select is(create_schedule_entry('aaaaaaaa-0000-0000-0000-000000000001', 'bbbbbbbb-0000-0000-0000-000000000001',
          null, false, null, '2026-10-10 19:00+00', '2026-10-10 21:00+00',
          array['11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222']::uuid[]) ->> 'status',
          'clash', 'all-day entry clashes with a timed entry on the same day');
select is((select count(*)::int from schedule_entries where activity_id is not null), 0, 'nothing saved on clash');

insert into ids select 'steak', (create_schedule_entry('aaaaaaaa-0000-0000-0000-000000000001',
  'bbbbbbbb-0000-0000-0000-000000000001', null, false, null, '2026-10-10 19:00+00', '2026-10-10 21:00+00',
  array['11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222']::uuid[], true) ->> 'entry_id')::uuid;
select is((select status from schedule_participants where entry_id = (select v from ids where k = 'steak')
           and user_id = '22222222-2222-2222-2222-222222222222'), 'clash', 'bob is added but marked as clashing');
select is((select status from schedule_participants where entry_id = (select v from ids where k = 'steak')
           and user_id = auth.uid()), 'added', 'alice has no clash');
select ok(exists (select 1 from change_log where action = 'clash_override' and actor_id = auth.uid()),
          'proceeding despite clashes is logged');

select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
select is((select count(*)::int from notifications where kind = 'schedule_clash'), 1, 'bob is told about the clash');
update schedule_participants set status = 'added' where entry_id = (select v from ids where k = 'steak');
select is((select status from schedule_participants where entry_id = (select v from ids where k = 'steak')
           and user_id = auth.uid()), 'added', 'bob can acknowledge a clash');
select throws_ok($$ update schedule_entries set start_at = now() $$, '42501', null,
                 'times can only change through reschedule_entry');

-- Reschedule to the next day clears the clash.
select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select is(reschedule_entry((select v from ids where k = 'steak'), false, null,
          '2026-10-11 19:00+00', '2026-10-11 21:00+00') ->> 'status', 'updated', 'reschedule without clash');

------------------------------------------------------------------------------
-- Events: any member swaps in an activity; history is kept
------------------------------------------------------------------------------
select pg_temp.act_as('33333333-3333-3333-3333-333333333333');
update schedule_entries set activity_id = 'bbbbbbbb-0000-0000-0000-000000000001'
where id = (select v from ids where k = 'bob_event');
select is((select actor_id from change_log where action = 'event_replaced'),
          '33333333-3333-3333-3333-333333333333'::uuid, 'replacing an event is logged with who did it');
select is((select count(*)::int from schedule_entries where id = (select v from ids where k = 'bob_event')),
          1, 'carol can see the group schedule');
select is((select count(*)::int from schedule_participants where entry_id = (select v from ids where k = 'bob_event')),
          1, 'participants are kept when an event is replaced');

------------------------------------------------------------------------------
-- Owner deletes the activity: entries revert to events
------------------------------------------------------------------------------
select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select lives_ok($$ select delete_activity('bbbbbbbb-0000-0000-0000-000000000001') $$, 'owner can delete');
select is((select count(*)::int from activities), 0, 'deleted activity is hidden');
select is((select count(*)::int from schedule_entries where activity_id is not null), 0, 'no entries point at it');
select is((select title from schedule_entries where id = (select v from ids where k = 'steak')),
          'Steak at Burnt Ends', 'entry reverts to an event named after the activity');
select ok(exists (select 1 from change_log where entity_type = 'activity' and action = 'deleted'),
          'delete is logged');

-- Members leave the group schedule: any member can remove an entry.
select pg_temp.act_as('33333333-3333-3333-3333-333333333333');
delete from schedule_entries where id = (select v from ids where k = 'steak');
select is((select count(*)::int from schedule_entries where id = (select v from ids where k = 'steak')),
          0, 'a member can remove an entry from the group schedule');

select * from finish();
rollback;

-- Deleting a group and handing over ownership (#10).
begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data) values
  ('11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'ann@example.test', '{"username":"ann"}'),
  ('22222222-2222-2222-2222-222222222222', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'ben@example.test', '{"username":"ben"}'),
  ('33333333-3333-3333-3333-333333333333', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'cat@example.test', '{"username":"cat"}'),
  ('44444444-4444-4444-4444-444444444444', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'dan@example.test', '{"username":"dan"}'),
  ('55555555-5555-5555-5555-555555555555', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'eve@example.test', '{"username":"eve"}');

create function pg_temp.act_as(p uuid) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated')::text, true);
$$;
grant execute on function pg_temp.act_as(uuid) to authenticated;

set local role anon;
select throws_ok($$ select public.delete_group('aaaaaaaa-0000-0000-0000-000000000001', 'Crew') $$, '42501', null,
                 'signed-out callers can''t delete groups');
select throws_ok($$ select public.transfer_ownership('aaaaaaaa-0000-0000-0000-000000000001', '22222222-2222-2222-2222-222222222222') $$,
                 '42501', null, 'signed-out callers can''t hand over groups');

-- Ann owns "Crew" with Ben, Cat and Dan; Eve isn't in it.
reset role;
insert into groups (id, name, created_by) values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'Crew', '11111111-1111-1111-1111-111111111111');
insert into group_members (group_id, user_id) values
  ('aaaaaaaa-0000-0000-0000-000000000001', '22222222-2222-2222-2222-222222222222'),
  ('aaaaaaaa-0000-0000-0000-000000000001', '33333333-3333-3333-3333-333333333333'),
  ('aaaaaaaa-0000-0000-0000-000000000001', '44444444-4444-4444-4444-444444444444');
set local role authenticated;

-- Ann shares an activity and plans: one upcoming (with Ben and Dan), one past, one idea.
select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
insert into activities (id, name) values ('b0000000-0000-0000-0000-00000000000a', 'Ann''s hike');
insert into group_activities (group_id, activity_id, type_id)
select 'aaaaaaaa-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-00000000000a', id
from activity_types where group_id = 'aaaaaaaa-0000-0000-0000-000000000001' and name = 'Outdoors';
select create_schedule_entry('aaaaaaaa-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-00000000000a', null,
  true, '2099-01-01', null, null,
  array['11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222',
        '44444444-4444-4444-4444-444444444444']::uuid[]);
select create_schedule_entry('aaaaaaaa-0000-0000-0000-000000000001', null, 'Old picnic',
  true, '2000-01-01', null, null, array['11111111-1111-1111-1111-111111111111']::uuid[]);
select create_schedule_entry('aaaaaaaa-0000-0000-0000-000000000001', null, 'Karaoke sometime',
  false, null, null, null, null);

-- Dan leaves the group but stays in the upcoming plan.
select pg_temp.act_as('44444444-4444-4444-4444-444444444444');
delete from group_members where user_id = auth.uid();

-- Summary: owner only.
select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
select throws_ok($$ select * from public.group_deletion_summary('aaaaaaaa-0000-0000-0000-000000000001') $$,
                 '42501', null, 'only the owner sees the deletion summary');
select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select results_eq($$ select members, upcoming_plans, ideas from public.group_deletion_summary('aaaaaaaa-0000-0000-0000-000000000001') $$,
                  $$ values (3, 1, 1) $$, 'summary counts members, upcoming plans and ideas');

-- Handing over: owner only, to a current member other than themselves.
select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
select throws_ok($$ select public.transfer_ownership('aaaaaaaa-0000-0000-0000-000000000001', '33333333-3333-3333-3333-333333333333') $$,
                 '42501', null, 'a member can''t hand over the group');
select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select throws_ok($$ select public.transfer_ownership('aaaaaaaa-0000-0000-0000-000000000001', '55555555-5555-5555-5555-555555555555') $$,
                 'P0001', 'they''re not a member of this group', 'can''t hand over to a non-member');
select throws_ok($$ select public.transfer_ownership('aaaaaaaa-0000-0000-0000-000000000001', auth.uid()) $$,
                 'P0001', 'you already own this group', 'can''t hand over to yourself');
select lives_ok($$ select public.transfer_ownership('aaaaaaaa-0000-0000-0000-000000000001', '22222222-2222-2222-2222-222222222222') $$,
                'the owner hands the group to Ben');
select results_eq($$ select user_id, role from group_members where group_id = 'aaaaaaaa-0000-0000-0000-000000000001' order by user_id $$,
                  $$ values ('11111111-1111-1111-1111-111111111111'::uuid, 'member'), ('22222222-2222-2222-2222-222222222222'::uuid, 'owner'),
                            ('33333333-3333-3333-3333-333333333333'::uuid, 'member') $$,
                  'Ben is now the only owner; Ann is a member');
select ok(exists (select 1 from public.list_group_history('aaaaaaaa-0000-0000-0000-000000000001')
                   where entity_type = 'group_member' and action = 'updated' and person_username = 'ben'),
          'the hand-over shows in group history');

select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
select results_eq($$ select kind, actor_name, group_name from public.list_notifications() where kind = 'ownership_transferred' $$,
                  $$ values ('ownership_transferred', 'ann', 'Crew') $$, 'the new owner is told who handed it over');

-- Deleting: owner only, through delete_group, with the name typed.
select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select throws_ok($$ select public.delete_group('aaaaaaaa-0000-0000-0000-000000000001', 'Crew') $$,
                 '42501', null, 'the former owner can''t delete the group');
select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
delete from groups where id = 'aaaaaaaa-0000-0000-0000-000000000001';
select ok(exists (select 1 from groups where id = 'aaaaaaaa-0000-0000-0000-000000000001'),
          'even the owner can''t delete the row directly (no notifications would go out)');
select throws_ok($$ select public.delete_group('aaaaaaaa-0000-0000-0000-000000000001', 'Crow') $$,
                 'P0001', 'type the group''s name to confirm', 'the typed name must match');
select lives_ok($$ select public.delete_group('aaaaaaaa-0000-0000-0000-000000000001', '  crew ') $$,
                'the owner deletes it (name matched ignoring case and spaces)');

reset role;
select is((select count(*)::int from groups where id = 'aaaaaaaa-0000-0000-0000-000000000001'), 0, 'the group is gone');
select is((select count(*)::int from schedule_entries where group_id = 'aaaaaaaa-0000-0000-0000-000000000001'), 0,
          'its plans are gone');
select is((select count(*)::int from activities where id = 'b0000000-0000-0000-0000-00000000000a'), 1,
          'the shared activity stays with its owner');
select results_eq($$ select user_id from notifications where kind = 'group_deleted'
                      and payload ->> 'group_name' = 'Crew' and user_id in (select id from auth.users where email like '%@example.test')
                    order by user_id $$,
                  $$ values ('11111111-1111-1111-1111-111111111111'::uuid), ('33333333-3333-3333-3333-333333333333'::uuid),
                            ('44444444-4444-4444-4444-444444444444'::uuid) $$,
                  'members and plan participants are notified, not the person deleting');
set local role authenticated;

select pg_temp.act_as('44444444-4444-4444-4444-444444444444');
select results_eq($$ select kind, actor_name, group_name from public.list_notifications() where kind = 'group_deleted' $$,
                  $$ values ('group_deleted', 'ben', 'Crew') $$, 'the notification keeps the deleted group''s name');

-- The last member leaving still deletes a group whose activities have plans
-- (this failed before: reverting plans to events hit the missing group).
select pg_temp.act_as('55555555-5555-5555-5555-555555555555');
insert into groups (id, name, created_by) values ('aaaaaaaa-0000-0000-0000-000000000002', 'Solo', auth.uid());
insert into activities (id, name) values ('b0000000-0000-0000-0000-00000000000e', 'Eve''s swim');
insert into group_activities (group_id, activity_id, type_id)
select 'aaaaaaaa-0000-0000-0000-000000000002', 'b0000000-0000-0000-0000-00000000000e', id
from activity_types where group_id = 'aaaaaaaa-0000-0000-0000-000000000002' and name = 'Outdoors';
select create_schedule_entry('aaaaaaaa-0000-0000-0000-000000000002', 'b0000000-0000-0000-0000-00000000000e', null,
  true, '2099-02-01', null, null, array['55555555-5555-5555-5555-555555555555']::uuid[]);
select lives_ok($$ delete from group_members where user_id = auth.uid() $$, 'the last member can leave a group with planned activities');
reset role;
select is((select count(*)::int from groups where id = 'aaaaaaaa-0000-0000-0000-000000000002'), 0, 'and the empty group is deleted');
set local role authenticated;

select * from finish();
rollback;

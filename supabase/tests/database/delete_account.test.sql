-- Account deletion and group ownership hand-over.
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

-- Ann owns "Crew" (Ben joined before Cat) and "Solo" (just her).
select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
insert into groups (id, name, created_by) values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'Crew', '11111111-1111-1111-1111-111111111111'),
  ('aaaaaaaa-0000-0000-0000-000000000002', 'Solo', '11111111-1111-1111-1111-111111111111'),
  ('aaaaaaaa-0000-0000-0000-000000000003', 'Pair', '11111111-1111-1111-1111-111111111111');
insert into group_members (group_id, user_id, joined_at) values
  ('aaaaaaaa-0000-0000-0000-000000000001', '22222222-2222-2222-2222-222222222222', now() - interval '2 days'),
  ('aaaaaaaa-0000-0000-0000-000000000001', '33333333-3333-3333-3333-333333333333', now() - interval '1 day'),
  ('aaaaaaaa-0000-0000-0000-000000000003', '33333333-3333-3333-3333-333333333333', now());

set local role authenticated;

-- Leaving as owner hands the group over.
select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
delete from group_members where group_id = 'aaaaaaaa-0000-0000-0000-000000000003' and user_id = auth.uid();
select pg_temp.act_as('33333333-3333-3333-3333-333333333333');
select is((select role from group_members where group_id = 'aaaaaaaa-0000-0000-0000-000000000003' and user_id = auth.uid()),
          'owner', 'an owner leaving hands the group to the remaining member');

-- Ann's content: an activity shared into Crew and scheduled; Ben shares one too.
select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
insert into activities (id, name) values ('b0000000-0000-0000-0000-00000000000a', 'Ann''s hike');
insert into group_activities (group_id, activity_id, type_id)
select 'aaaaaaaa-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-00000000000a', id
from activity_types where group_id = 'aaaaaaaa-0000-0000-0000-000000000001' and name = 'Outdoors';
select create_schedule_entry('aaaaaaaa-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-00000000000a', null,
  true, '2026-11-01', null, null,
  array['11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222']::uuid[]);
update profiles set avatar_path = '11111111-1111-1111-1111-111111111111/me.jpg' where id = auth.uid();
select is((select count(*)::int from my_storage_files()), 1, 'my_storage_files lists the avatar');

select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
insert into activities (id, name) values ('b0000000-0000-0000-0000-00000000000b', 'Ben''s dinner');
insert into group_activities (group_id, activity_id, type_id)
select 'aaaaaaaa-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-00000000000b', id
from activity_types where group_id = 'aaaaaaaa-0000-0000-0000-000000000001' and name = 'Food';

-- Ann deletes her account.
select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select lives_ok($$ select delete_my_account() $$, 'ann deletes her account');

reset role;
select is((select count(*)::int from auth.users where id = '11111111-1111-1111-1111-111111111111'), 0, 'auth user gone');
select is((select count(*)::int from profiles where id = '11111111-1111-1111-1111-111111111111'), 0, 'profile gone');
select is((select user_id from group_members where group_id = 'aaaaaaaa-0000-0000-0000-000000000001' and role = 'owner'),
          '22222222-2222-2222-2222-222222222222'::uuid, 'Crew passes to the longest-standing member (Ben)');
select is((select count(*)::int from groups where id = 'aaaaaaaa-0000-0000-0000-000000000002'), 0,
          'Solo had nobody else, so it is deleted');
select is((select created_by from groups where id = 'aaaaaaaa-0000-0000-0000-000000000001'), null,
          'creator column is cleared, group kept');
select is((select count(*)::int from activities where owner_id = '11111111-1111-1111-1111-111111111111'), 0,
          'her activities are deleted');
select is((select title from schedule_entries where group_id = 'aaaaaaaa-0000-0000-0000-000000000001'), 'Ann''s hike',
          'the plan that used her activity stays as an event');
select is((select count(*)::int from schedule_participants
           where user_id = '22222222-2222-2222-2222-222222222222'), 1, 'Ben is still on that plan');
select is((select count(*)::int from group_activities where activity_id = 'b0000000-0000-0000-0000-00000000000b'), 1,
          'other people''s activities are untouched');
select ok(exists (select 1 from change_log where actor_id = '11111111-1111-1111-1111-111111111111'),
          'history is kept (shown as a deleted user)');

set local role authenticated;
select pg_temp.act_as('33333333-3333-3333-3333-333333333333');
select throws_ok($$ select delete_my_account() from (select set_config('request.jwt.claims', '{}', true)) x $$,
                 'not authenticated');

select * from finish();
rollback;

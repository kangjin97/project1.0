-- Save a copy of someone's activity to my activities (#112).
begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data) values
  ('11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'tom@example.test', '{"username":"tom_copy"}'),
  ('22222222-2222-2222-2222-222222222222', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'amy@example.test', '{"username":"amy_copy"}'),
  ('33333333-3333-3333-3333-333333333333', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'out@example.test', '{"username":"out_copy"}');

create function pg_temp.act_as(p uuid) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated')::text, true);
$$;
grant execute on function pg_temp.act_as(uuid) to authenticated;

-- Tom owns two groups; Amy is in both, the outsider in neither.
select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
insert into groups (id, name, created_by) values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'Sporty', '11111111-1111-1111-1111-111111111111'),
  ('aaaaaaaa-0000-0000-0000-000000000002', 'Weekend', '11111111-1111-1111-1111-111111111111');
insert into group_members (group_id, user_id) values
  ('aaaaaaaa-0000-0000-0000-000000000001', '22222222-2222-2222-2222-222222222222'),
  ('aaaaaaaa-0000-0000-0000-000000000002', '22222222-2222-2222-2222-222222222222');

set local role authenticated;
select pg_temp.act_as('11111111-1111-1111-1111-111111111111');

insert into activities (id, name, description, location, place_id, price_min, price_max, currency, url) values
  ('bbbbbbbb-0000-0000-0000-000000000001', 'Bishan Pickleball', 'Book 2 weeks ahead', 'Bishan Sports Hall, Singapore',
   'ChIJ_copy_test_place_01', 10, 15, 'SGD', 'https://www.activesg.gov.sg'),
  ('bbbbbbbb-0000-0000-0000-000000000002', 'Tom''s secret spot', null, null, null, null, null, 'SGD', null);

-- Shared first into Sporty as Outdoors, later into Weekend as Entertainment.
insert into group_activities (group_id, activity_id, type_id, added_at)
select 'aaaaaaaa-0000-0000-0000-000000000001', 'bbbbbbbb-0000-0000-0000-000000000001', id, now() - interval '1 day'
  from activity_types where group_id = 'aaaaaaaa-0000-0000-0000-000000000001' and name = 'Outdoors';
insert into group_activities (group_id, activity_id, type_id)
select 'aaaaaaaa-0000-0000-0000-000000000002', 'bbbbbbbb-0000-0000-0000-000000000001', id
  from activity_types where group_id = 'aaaaaaaa-0000-0000-0000-000000000002' and name = 'Entertainment';

-- Nobody sets copied_from by hand.
select throws_ok($$ insert into activities (name, copied_from) values ('Fake', 'bbbbbbbb-0000-0000-0000-000000000002') $$,
                 '42501', 'copies are made with copy_activity', 'copied_from can''t be set on insert');
select throws_ok($$ update activities set copied_from = 'bbbbbbbb-0000-0000-0000-000000000002' where id = 'bbbbbbbb-0000-0000-0000-000000000001' $$,
                 '42501', null, 'or on update');

-- The owner can't copy their own.
select throws_ok($$ select copy_activity('bbbbbbbb-0000-0000-0000-000000000001') $$,
                 'P0001', 'this activity is already yours', 'the owner can''t save a copy of their own activity');

-- Outsiders can't copy what they can't see, shared or not.
select pg_temp.act_as('33333333-3333-3333-3333-333333333333');
select throws_ok($$ select copy_activity('bbbbbbbb-0000-0000-0000-000000000001') $$,
                 'P0002', 'activity not found', 'someone outside its groups can''t copy it');

-- A member can't copy an activity that isn't shared with them.
select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
select throws_ok($$ select copy_activity('bbbbbbbb-0000-0000-0000-000000000002') $$,
                 'P0002', 'activity not found', 'a private activity can''t be copied');

-- Amy already has a label named like the type in Sporty, in other letter case.
insert into personal_types (id, name) values ('dddddddd-0000-0000-0000-000000000001', 'outdoors');

create temp table copies (id uuid);
grant all on copies to authenticated;
insert into copies select copy_activity('bbbbbbbb-0000-0000-0000-000000000001');

select is((select count(*)::int from activities a join copies c on c.id = a.id), 1, 'a member can save a copy');
select results_eq(
  $$ select owner_id, name, description, location, place_id, price_min, price_max, currency::text, url, copied_from
       from activities where id = (select id from copies) $$,
  $$ values ('22222222-2222-2222-2222-222222222222'::uuid, 'Bishan Pickleball', 'Book 2 weeks ahead',
             'Bishan Sports Hall, Singapore', 'ChIJ_copy_test_place_01', 10.00::numeric(12,2), 15.00::numeric(12,2),
             'SGD', 'https://www.activesg.gov.sg', 'bbbbbbbb-0000-0000-0000-000000000001'::uuid) $$,
  'the copy is theirs, with every field and a link to the original');
select is((select personal_type_id from activities where id = (select id from copies)),
          'dddddddd-0000-0000-0000-000000000001'::uuid,
          'its label is the type from the group where it was shared first, reusing the label of that name in any case');
select is((select count(*)::int from group_activities where activity_id = (select id from copies)), 0,
          'the copy is private');
select is((select count(*)::int from personal_types where owner_id = '22222222-2222-2222-2222-222222222222'), 1,
          'no extra label was created');

-- Editing the copy leaves the original alone.
update activities set price_max = 99 where id = (select id from copies);
select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select is((select price_max from activities where id = 'bbbbbbbb-0000-0000-0000-000000000001'), 15.00::numeric(12,2),
          'the copy is independent of the original');
select is((select count(*)::int from activities where id = (select id from copies)), 0,
          'the original''s owner can''t see the copy');

-- One live copy per person.
select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
select throws_ok($$ select copy_activity('bbbbbbbb-0000-0000-0000-000000000001') $$,
                 'P0001', 'you already saved a copy of this activity', 'saving twice is refused');

-- Deleting the copy frees it; saving from Weekend uses that group's type and creates the label.
select delete_activity((select id from copies));
truncate copies;
insert into copies select copy_activity('bbbbbbbb-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000002');
select is((select t.name from activities a join personal_types t on t.id = a.personal_type_id where a.id = (select id from copies)),
          'Entertainment', 'saving from a given group uses its type, creating the label when missing');

-- A group the caller isn't in doesn't leak its type: no label then.
select delete_activity((select id from copies));
truncate copies;
insert into copies select copy_activity('bbbbbbbb-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-0000000000ff');
select is((select personal_type_id from activities where id = (select id from copies)), null,
          'a group where the activity isn''t shared with the caller gives no label');

-- A deleted original can't be copied.
select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select delete_activity('bbbbbbbb-0000-0000-0000-000000000001');
select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
select is((select copied_from from activities where id = (select id from copies)),
          'bbbbbbbb-0000-0000-0000-000000000001'::uuid, 'the copy keeps its link after the original is deleted');
select delete_activity((select id from copies));
select throws_ok($$ select copy_activity('bbbbbbbb-0000-0000-0000-000000000001') $$,
                 'P0002', 'activity not found', 'a deleted activity can''t be copied');

-- Signed-out callers can't use it.
reset role;
set local role anon;
select throws_ok($$ select public.copy_activity('bbbbbbbb-0000-0000-0000-000000000001') $$,
                 '42501', null, 'anon can''t call copy_activity');

select * from finish();
rollback;

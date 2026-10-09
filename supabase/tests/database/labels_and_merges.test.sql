-- Personal labels carry into groups; groups can merge types.
begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data) values
  ('11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'me@example.test',    '{"username":"myself"}'),
  ('22222222-2222-2222-2222-222222222222', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'jimmy@example.test', '{"username":"jimmy"}');

create function pg_temp.act_as(p uuid) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated')::text, true);
$$;
grant execute on function pg_temp.act_as(uuid) to authenticated;

-- The type an activity is filed under in the test group.
create function pg_temp.type_of(p_activity uuid) returns text language sql security definer as $$
  select t.name from public.group_activities ga join public.activity_types t on t.id = ga.type_id
  where ga.group_id = 'aaaaaaaa-0000-0000-0000-000000000001' and ga.activity_id = p_activity;
$$;
grant execute on function pg_temp.type_of(uuid) to authenticated;

-- Group "Foodies" with me (owner) and Jimmy.
select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
insert into groups (id, name, created_by)
values ('aaaaaaaa-0000-0000-0000-000000000001', 'Foodies', '11111111-1111-1111-1111-111111111111');
insert into group_members (group_id, user_id)
values ('aaaaaaaa-0000-0000-0000-000000000001', '22222222-2222-2222-2222-222222222222');

set local role authenticated;

------------------------------------------------------------------------------
-- Labels carry over when sharing
------------------------------------------------------------------------------
select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
insert into personal_types (id, name) values ('d0000000-0000-0000-0000-00000000000a', 'yummy');
insert into activities (id, name, personal_type_id)
values ('b0000000-0000-0000-0000-00000000000a', 'Activity A', 'd0000000-0000-0000-0000-00000000000a');

select is((select type_name from preview_group_type('aaaaaaaa-0000-0000-0000-000000000001', 'Yummy')),
          'Yummy', 'preview: unknown label would become a new type');
select is((select is_new from preview_group_type('aaaaaaaa-0000-0000-0000-000000000001', 'Yummy')),
          true, 'preview reports the type as new');

insert into group_activities (group_id, activity_id)
values ('aaaaaaaa-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-00000000000a');
select is(pg_temp.type_of('b0000000-0000-0000-0000-00000000000a'), 'yummy',
          'sharing without picking a type files it under the owner''s label');

select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
select is((select count(*)::int from personal_types), 0, 'labels are private to their owner');
select throws_ok($$ update activities set personal_type_id = null where id = 'b0000000-0000-0000-0000-00000000000a' $$,
                 '42501', null, 'members cannot change someone else''s label');

insert into personal_types (id, name) values ('d0000000-0000-0000-0000-00000000000b', 'goodfood');
insert into activities (id, name, personal_type_id)
values ('b0000000-0000-0000-0000-00000000000b', 'Activity B', 'd0000000-0000-0000-0000-00000000000b');
insert into group_activities (group_id, activity_id)
values ('aaaaaaaa-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-00000000000b');
select is(pg_temp.type_of('b0000000-0000-0000-0000-00000000000b'), 'goodfood', 'Jimmy''s label becomes its own type');

select throws_ok($$ insert into activities (name, personal_type_id)
                    values ('Sneaky', 'd0000000-0000-0000-0000-00000000000a') $$,
                 '23503', null, 'cannot use someone else''s label');

------------------------------------------------------------------------------
-- Merging
------------------------------------------------------------------------------
select lives_ok($$ select merge_types('aaaaaaaa-0000-0000-0000-000000000001',
                    array(select id from activity_types where name in ('yummy', 'goodfood')),
                    null, 'Food') $$, 'merge yummy + goodfood into a new type Food');
select is(pg_temp.type_of('b0000000-0000-0000-0000-00000000000a'), 'Food', 'existing activity A moved to Food');
select is(pg_temp.type_of('b0000000-0000-0000-0000-00000000000b'), 'Food', 'existing activity B moved to Food');
select is((select count(*)::int from activity_types where name in ('yummy', 'goodfood')), 0, 'merged types are gone');
select is((select count(*)::int from type_merges), 2, 'two merge rules exist');

-- A later activity labelled "GoodFood" lands in Food.
insert into personal_types (id, name) values ('d0000000-0000-0000-0000-00000000000c', 'Snacks');
insert into activities (id, name, personal_type_id)
values ('b0000000-0000-0000-0000-00000000000c', 'Activity C', 'd0000000-0000-0000-0000-00000000000b');
select is((select merged from preview_group_type('aaaaaaaa-0000-0000-0000-000000000001', 'GoodFood')),
          true, 'preview shows the merge');
insert into group_activities (group_id, activity_id)
values ('aaaaaaaa-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-00000000000c');
select is(pg_temp.type_of('b0000000-0000-0000-0000-00000000000c'), 'Food', 'new activity with a merged label goes to Food');

------------------------------------------------------------------------------
-- Changing a label re-files the activity
------------------------------------------------------------------------------
update activities set personal_type_id = 'd0000000-0000-0000-0000-00000000000c'
where id = 'b0000000-0000-0000-0000-00000000000c';
select is(pg_temp.type_of('b0000000-0000-0000-0000-00000000000c'), 'Snacks', 'new label moves it to its own type');

update personal_types set name = 'yummy' where id = 'd0000000-0000-0000-0000-00000000000c';
select is(pg_temp.type_of('b0000000-0000-0000-0000-00000000000c'), 'Food', 'renaming the label to a merged name moves it into Food');

-- A member's manual change is overridden by the owner's next label change.
update group_activities set type_id = (select id from activity_types where name = 'Other')
where activity_id = 'b0000000-0000-0000-0000-00000000000b';
select is(pg_temp.type_of('b0000000-0000-0000-0000-00000000000b'), 'Other', 'members can still change the type by hand');
update activities set personal_type_id = 'd0000000-0000-0000-0000-00000000000c'
where id = 'b0000000-0000-0000-0000-00000000000b';
select is(pg_temp.type_of('b0000000-0000-0000-0000-00000000000b'), 'Food', 'the owner''s label change re-files it');

------------------------------------------------------------------------------
-- Undoing a merge
------------------------------------------------------------------------------
select lives_ok($$ select remove_type_merge((select id from type_merges where source_name = 'yummy')) $$,
                'remove the yummy rule');
select is(pg_temp.type_of('b0000000-0000-0000-0000-00000000000b'), 'yummy',
          'activities labelled yummy go back to a yummy type');
select is((select count(*)::int from type_merges), 1, 'the goodfood rule remains');
select ok(exists (select 1 from change_log where entity_type = 'type_merge' and action = 'deleted'),
          'merge changes are logged');

select * from finish();
rollback;

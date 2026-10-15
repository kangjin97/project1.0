-- Re-pointing a merge rule is logged and shows in group history (#52).
begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data) values
  ('11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'ann@example.test', '{"username":"ann"}');

create function pg_temp.act_as(p uuid) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated')::text, true);
$$;
grant execute on function pg_temp.act_as(uuid) to authenticated;
create temp table ids (k text primary key, v uuid);
grant all on ids to authenticated;

set local role authenticated;
select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
insert into groups (id, name, created_by)
values ('aaaaaaaa-0000-0000-0000-000000000001', 'Foodies', auth.uid());
with t as (
  insert into activity_types (group_id, name) values
    ('aaaaaaaa-0000-0000-0000-000000000001', 'yummy'),
    ('aaaaaaaa-0000-0000-0000-000000000001', 'Eats')
  returning id, name)
insert into ids select name, id from t;
insert into ids select 'Food', id from activity_types
where group_id = 'aaaaaaaa-0000-0000-0000-000000000001' and name = 'Food';

-- yummy → Food creates a rule; then Food → Eats re-points the yummy rule.
select merge_types('aaaaaaaa-0000-0000-0000-000000000001', array[(select v from ids where k = 'yummy')],
                   (select v from ids where k = 'Food'));
select merge_types('aaaaaaaa-0000-0000-0000-000000000001', array[(select v from ids where k = 'Food')],
                   (select v from ids where k = 'Eats'));

reset role;
select results_eq(
  $$ select before ->> 'target_type_id', after ->> 'target_type_id' from change_log
     where entity_type = 'type_merge' and action = 'updated'
       and entity_id = (select id from type_merges where group_id = 'aaaaaaaa-0000-0000-0000-000000000001'
                                                       and source_name = 'yummy') $$,
  $$ select (select v from ids where k = 'Food')::text, (select v from ids where k = 'Eats')::text $$,
  'the re-pointed rule is logged with its old and new target');
set local role authenticated;

select results_eq(
  $$ select subject_name, to_type_name from public.list_group_history('aaaaaaaa-0000-0000-0000-000000000001')
     where entity_type = 'type_merge' and action = 'updated' $$,
  $$ values ('yummy', 'Eats') $$,
  'group history says yummy was merged into Eats');

-- Merging into the type a rule already points at changes nothing and logs nothing.
reset role;
create temp table before_count as
  select count(*) n from change_log where entity_type = 'type_merge' and action = 'updated'
   and group_id = 'aaaaaaaa-0000-0000-0000-000000000001';
grant select on before_count to authenticated;
set local role authenticated;
insert into activity_types (group_id, name) values ('aaaaaaaa-0000-0000-0000-000000000001', 'yummy');
select merge_types('aaaaaaaa-0000-0000-0000-000000000001',
                   array[(select id from activity_types where group_id = 'aaaaaaaa-0000-0000-0000-000000000001' and name = 'yummy')],
                   (select v from ids where k = 'Eats'));
reset role;
select is((select count(*) from change_log where entity_type = 'type_merge' and action = 'updated'
            and group_id = 'aaaaaaaa-0000-0000-0000-000000000001'),
          (select n from before_count), 'an update that keeps the same target isn''t logged');

select * from finish();
rollback;

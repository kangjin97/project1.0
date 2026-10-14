-- Notifications: list_notifications and marking them read (#6).
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
select throws_ok('select * from public.list_notifications()', '42501', null, 'signed-out callers can''t list notifications');

set local role authenticated;

-- Ann creates "Crew" and invites Ben.
select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
insert into groups (id, name, created_by) values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'Crew', '11111111-1111-1111-1111-111111111111');
with x as (
  insert into group_invitations (group_id, invitee_id, invited_by)
  values ('aaaaaaaa-0000-0000-0000-000000000001', '22222222-2222-2222-2222-222222222222', auth.uid())
  returning id)
insert into ids select 'inv', id from x;

select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
select results_eq(
  $$ select kind, actor_name, group_name, invitation_status, entry_id is null from public.list_notifications() $$,
  $$ values ('group_invitation', 'ann', 'Crew', 'pending', true) $$,
  'the invitee sees who invited them to which group');

select pg_temp.act_as('33333333-3333-3333-3333-333333333333');
select is((select count(*)::int from public.list_notifications()), 0, 'others'' notifications are not listed');

-- Ben joins; Ann adds him to a picnic, then to a hike on the same day anyway.
select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
select respond_to_invitation((select v from ids where k = 'inv'), true);

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
insert into ids select 'picnic', (create_schedule_entry('aaaaaaaa-0000-0000-0000-000000000001', null, 'Picnic',
  true, '2026-11-01', null, null,
  array['11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222']::uuid[]) ->> 'entry_id')::uuid;
insert into ids select 'hike', (create_schedule_entry('aaaaaaaa-0000-0000-0000-000000000001', null, 'Hike',
  true, '2026-11-01', null, null,
  array['11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222']::uuid[], true) ->> 'entry_id')::uuid;
select is((select count(*)::int from public.list_notifications()), 0, 'the planner isn''t notified about their own plans');

-- Same-transaction rows share now(); spread them out to check the order.
reset role;
update notifications set created_at = created_at - interval '2 hours' where kind = 'group_invitation';
update notifications set created_at = created_at - interval '1 hour' where kind = 'added_to_entry';
set local role authenticated;

select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
select results_eq(
  $$ select kind, entry_title, group_name, actor_name from public.list_notifications() $$,
  $$ values ('schedule_clash', 'Hike', 'Crew', 'ann'), ('added_to_entry', 'Picnic', 'Crew', 'ann'),
            ('group_invitation', null::text, 'Crew', 'ann') $$,
  'newest first, with plan titles and group names');
select results_eq(
  $$ select entry_id, entry_all_day, entry_date, clash_count from public.list_notifications() where kind = 'schedule_clash' $$,
  $$ select v, true, '2026-11-01'::date, 1 from ids where k = 'hike' $$,
  'a clash notification carries the plan''s timing and how many plans it clashes with');
select is((select invitation_status from public.list_notifications() where kind = 'group_invitation'), 'accepted',
          'the invitation shows its current status');
select is((select count(*)::int from public.list_notifications(1)), 1, 'the limit is applied');

-- Marking read: own rows only.
select is((select count(*)::int from public.list_notifications() where read_at is null), 3, 'all unread at first');
update notifications set read_at = now() where read_at is null;
select is((select count(*)::int from public.list_notifications() where read_at is null), 0, 'Ben can mark his notifications read');
reset role;
update notifications set read_at = null where user_id = '22222222-2222-2222-2222-222222222222';
set local role authenticated;
select pg_temp.act_as('33333333-3333-3333-3333-333333333333');
update notifications set read_at = now();
reset role;
select is((select count(*)::int from notifications where user_id = '22222222-2222-2222-2222-222222222222' and read_at is null), 3,
          'nobody else can mark them read');
set local role authenticated;

-- After leaving the plan and the group, Ben no longer sees their current details.
select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
delete from schedule_participants where user_id = auth.uid();
delete from group_members where user_id = auth.uid();
select results_eq(
  $$ select kind, entry_id is null, entry_title is null, group_name is null from public.list_notifications() order by kind $$,
  $$ values ('added_to_entry', true, true, true), ('group_invitation', true, true, false), ('schedule_clash', true, true, true) $$,
  'plan and group details disappear once Ben can''t see them; the invitation keeps its group name');

select * from finish();
rollback;

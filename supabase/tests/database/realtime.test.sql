-- Realtime broadcasts and who may listen (#7).
begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data) values
  ('11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'ann@example.test', '{"username":"ann"}'),
  ('22222222-2222-2222-2222-222222222222', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'ben@example.test', '{"username":"ben"}');

create function pg_temp.act_as(p uuid) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated')::text, true);
$$;
grant execute on function pg_temp.act_as(uuid) to authenticated;

-- Messages sent so far to a topic about a table (read as postgres, past RLS).
create function pg_temp.sent(p_topic text, p_table text) returns int language sql as $$
  select count(*)::int from realtime.messages
  where topic = p_topic and event = 'changed' and payload ->> 'table' = p_table
    and inserted_at > now() - interval '1 hour';
$$;
-- The whole test is one transaction, but the trigger sends once per topic and
-- table per transaction; forget what was sent to act like a new transaction.
create function pg_temp.next_transaction() returns void language sql as $$
  select set_config('easyplan.broadcasts_sent', '', true);
$$;
grant execute on function pg_temp.next_transaction() to authenticated;

set local role authenticated;
select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
insert into groups (id, name, created_by) values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'Crew', '11111111-1111-1111-1111-111111111111');

reset role;
select is(pg_temp.sent('group:aaaaaaaa-0000-0000-0000-000000000001', 'group_members'), 1,
          'creating a group tells the group');
select is(pg_temp.sent('user:11111111-1111-1111-1111-111111111111', 'group_members'), 1,
          'and the creator, whose group list changed');
select is(pg_temp.sent('group:aaaaaaaa-0000-0000-0000-000000000001', 'activity_types'), 1,
          'four starter types in one transaction send one message');
select is((select array_agg(distinct k order by k) from realtime.messages m, jsonb_object_keys(m.payload) k
            where m.topic = 'group:aaaaaaaa-0000-0000-0000-000000000001'),
          array['id', 'table'], 'messages carry only the table name (and a message id), no row data');

-- Ann shares an activity, then edits it: the group and Ann hear about both.
set local role authenticated;
select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select pg_temp.next_transaction();
insert into activities (id, name) values ('bbbbbbbb-0000-0000-0000-000000000001', 'Beach day');
insert into group_activities (group_id, activity_id, type_id)
select 'aaaaaaaa-0000-0000-0000-000000000001', 'bbbbbbbb-0000-0000-0000-000000000001', id
from activity_types where group_id = 'aaaaaaaa-0000-0000-0000-000000000001' and name = 'Food';
select pg_temp.next_transaction();
update activities set price_max = 20 where id = 'bbbbbbbb-0000-0000-0000-000000000001';
reset role;
select is(pg_temp.sent('group:aaaaaaaa-0000-0000-0000-000000000001', 'group_activities'), 1, 'sharing tells the group');
select is(pg_temp.sent('group:aaaaaaaa-0000-0000-0000-000000000001', 'activities'), 1,
          'editing a shared activity tells every group it''s in');
select is(pg_temp.sent('user:11111111-1111-1111-1111-111111111111', 'activities'), 2,
          'and its owner (creating it, then editing it)');

-- Ben joins and is put on a plan: he hears about the plan and the notification.
set local role authenticated;
select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select pg_temp.next_transaction();
insert into group_invitations (id, group_id, invitee_id, invited_by) values
  ('cccccccc-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001',
   '22222222-2222-2222-2222-222222222222', '11111111-1111-1111-1111-111111111111');
reset role;
select is(pg_temp.sent('user:22222222-2222-2222-2222-222222222222', 'notifications'), 1,
          'an invitation reaches the invitee through their notifications');

-- Before joining, Ben can't listen to the group.
set local role authenticated;
select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
select set_config('realtime.topic', 'group:aaaaaaaa-0000-0000-0000-000000000001', true);
select is((select count(*)::int from realtime.messages), 0, 'non-members can''t listen to a group');

select pg_temp.next_transaction();
select respond_to_invitation('cccccccc-0000-0000-0000-000000000001', true);
select set_config('realtime.topic', 'group:aaaaaaaa-0000-0000-0000-000000000001', true);
select ok((select count(*) from realtime.messages) > 0, 'members can listen to their group');
reset role;
select is(pg_temp.sent('user:22222222-2222-2222-2222-222222222222', 'group_invitations'), 2,
          'the invitee hears about the invitation and about answering it (e.g. on another device)');
set local role authenticated;

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select pg_temp.next_transaction();
select create_schedule_entry('aaaaaaaa-0000-0000-0000-000000000001', null, 'Picnic', true, '2026-11-01', null, null,
  array['11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222']::uuid[]);
reset role;
select is(pg_temp.sent('user:22222222-2222-2222-2222-222222222222', 'schedule_participants'), 1,
          'being added to a plan reaches the person');
select is(pg_temp.sent('group:aaaaaaaa-0000-0000-0000-000000000001', 'schedule_entries'), 1,
          'a new plan tells the group');
select is(pg_temp.sent('group:aaaaaaaa-0000-0000-0000-000000000001', 'schedule_participants'), 1,
          'two participants in one transaction send one message to the group');

-- User topics: only your own.
set local role authenticated;
select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
select set_config('realtime.topic', 'user:22222222-2222-2222-2222-222222222222', true);
select ok((select count(*) from realtime.messages) > 0, 'you can listen to your own topic');
select set_config('realtime.topic', 'user:11111111-1111-1111-1111-111111111111', true);
select is((select count(*)::int from realtime.messages), 0, 'you can''t listen to someone else''s');
select set_config('realtime.topic', 'something-else', true);
select is((select count(*)::int from realtime.messages), 0, 'other topics are closed');

-- Nobody may send, and signed-out users can't listen.
select throws_ok(
  $$ insert into realtime.messages (topic, extension, event, payload, private)
     values ('group:aaaaaaaa-0000-0000-0000-000000000001', 'broadcast', 'changed', '{}', true) $$,
  '42501', null, 'clients can''t send messages, even to their own group');
set local role anon;
select set_config('realtime.topic', 'group:aaaaaaaa-0000-0000-0000-000000000001', true);
select is((select count(*)::int from realtime.messages), 0, 'signed-out users can''t listen');

-- After leaving, Ben can't listen any more; the group and Ben both hear he left.
set local role authenticated;
select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
select pg_temp.next_transaction();
delete from group_members where group_id = 'aaaaaaaa-0000-0000-0000-000000000001' and user_id = auth.uid();
select set_config('realtime.topic', 'group:aaaaaaaa-0000-0000-0000-000000000001', true);
select is((select count(*)::int from realtime.messages), 0, 'former members can''t listen');
reset role;
select is(pg_temp.sent('user:22222222-2222-2222-2222-222222222222', 'group_members'), 2,
          'joining and leaving both reach the person');

-- Ben is still on the picnic after leaving the group: changes to it still reach him.
set local role authenticated;
select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select pg_temp.next_transaction();
update schedule_entries set title = 'Beach picnic' where title = 'Picnic';
reset role;
select is(pg_temp.sent('user:22222222-2222-2222-2222-222222222222', 'schedule_entries'), 1,
          'plan changes reach participants who left the group');

select * from finish();
rollback;

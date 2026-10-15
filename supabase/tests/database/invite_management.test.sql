-- Managing invites: revoking links, cancelling invitations, history (#9).
begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data) values
  ('11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'ann@example.test', '{"username":"ann"}'),
  ('22222222-2222-2222-2222-222222222222', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'ben@example.test', '{"username":"ben"}'),
  ('33333333-3333-3333-3333-333333333333', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'cat@example.test', '{"username":"cat"}'),
  ('44444444-4444-4444-4444-444444444444', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'dan@example.test', '{"username":"dan"}');

create function pg_temp.act_as(p uuid) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated')::text, true);
$$;
grant execute on function pg_temp.act_as(uuid) to authenticated;

set local role anon;
select throws_ok($$ select public.cancel_invitation('cccccccc-0000-0000-0000-000000000001') $$,
                 '42501', null, 'signed-out callers can''t cancel invitations');

set local role authenticated;

-- Ann's group "Crew", with Ben as a member (joined by invitation).
select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
insert into groups (id, name, created_by) values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'Crew', '11111111-1111-1111-1111-111111111111');
insert into group_invitations (id, group_id, invitee_id) values
  ('cccccccc-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001', '22222222-2222-2222-2222-222222222222');
select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
select respond_to_invitation('cccccccc-0000-0000-0000-000000000001', true);

-- Ann makes a link; Ben (any member) revokes it.
select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
insert into group_invite_links (id, group_id, expires_at, token) values
  ('dddddddd-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001', now() + interval '7 days', 'tok-crew-1');

select pg_temp.act_as('33333333-3333-3333-3333-333333333333');
update group_invite_links set revoked_at = now() where id = 'dddddddd-0000-0000-0000-000000000001';
reset role;
select is((select revoked_at from group_invite_links where id = 'dddddddd-0000-0000-0000-000000000001'), null,
          'non-members can''t revoke a link');
set local role authenticated;

select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
update group_invite_links set revoked_at = '2000-01-01' where id = 'dddddddd-0000-0000-0000-000000000001';
select ok((select revoked_at > now() - interval '1 minute' from group_invite_links
            where id = 'dddddddd-0000-0000-0000-000000000001'),
          'any member can revoke a link, and the server sets the time');
select throws_ok($$ update group_invite_links set revoked_at = null where id = 'dddddddd-0000-0000-0000-000000000001' $$,
                 'P0001', 'this invite link is already revoked', 'a revoked link can''t be revived');

select pg_temp.act_as('33333333-3333-3333-3333-333333333333');
select throws_ok($$ select join_group_via_link('tok-crew-1') $$,
                 'P0001', 'invite link is invalid or expired', 'nobody can join through a revoked link');

-- Using a link (not revoking it) still works: Ann makes another, Cat joins.
select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
insert into group_invite_links (group_id, expires_at, token) values
  ('aaaaaaaa-0000-0000-0000-000000000001', now() + interval '7 days', 'tok-crew-2');
select pg_temp.act_as('33333333-3333-3333-3333-333333333333');
select is(join_group_via_link('tok-crew-2'), 'aaaaaaaa-0000-0000-0000-000000000001'::uuid,
          'joining through a link still counts its use');

-- Ann invites Dan; Ben (any member) cancels it.
select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
insert into group_invitations (id, group_id, invitee_id) values
  ('cccccccc-0000-0000-0000-000000000002', 'aaaaaaaa-0000-0000-0000-000000000001', '44444444-4444-4444-4444-444444444444');

select pg_temp.act_as('44444444-4444-4444-4444-444444444444');
select throws_ok($$ select cancel_invitation('cccccccc-0000-0000-0000-000000000002') $$,
                 'P0001', 'invitation not found', 'the invitee can''t cancel (they decline instead)');

select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
select lives_ok($$ select cancel_invitation('cccccccc-0000-0000-0000-000000000002') $$,
                'any member can cancel a pending invitation');
select throws_ok($$ select cancel_invitation('cccccccc-0000-0000-0000-000000000002') $$,
                 'P0001', 'invitation not found', 'only pending invitations can be cancelled');
select throws_ok($$ select cancel_invitation('cccccccc-0000-0000-0000-000000000001') $$,
                 'P0001', 'invitation not found', 'an accepted invitation can''t be cancelled');

select pg_temp.act_as('44444444-4444-4444-4444-444444444444');
select throws_ok($$ select respond_to_invitation('cccccccc-0000-0000-0000-000000000002', true) $$,
                 'P0001', 'invitation not found', 'a cancelled invitation can''t be accepted');
select is((select count(*)::int from group_invitations where invitee_id = auth.uid() and status = 'pending'), 0,
          'it''s gone from the invitee''s pending list');
select is((select invitation_status from public.list_notifications() where kind = 'group_invitation'), 'cancelled',
          'the invitee''s notification shows it was cancelled');

-- History: who made and revoked links, who invited and cancelled; no codes.
select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select results_eq(
  $$ select entity_type, action, actor_username, person_username,
            coalesce(after ->> 'status', case when after ? 'revoked_at' and action = 'updated' then 'revoked' end)
       from public.list_group_history('aaaaaaaa-0000-0000-0000-000000000001')
      where entity_type in ('invite_link', 'invitation') order by id $$,
  $$ values ('invitation'::text, 'created'::text, 'ann'::text, 'ben'::text, 'pending'::text),
            ('invite_link', 'created', 'ann', null, null),
            ('invite_link', 'updated', 'ben', null, 'revoked'),
            ('invite_link', 'created', 'ann', null, null),
            ('invitation', 'created', 'ann', 'dan', 'pending'),
            ('invitation', 'updated', 'ben', 'dan', 'cancelled') $$,
  'history shows invitations and links with who did what (accepting and link use counts are left out)');
select is((select count(*)::int from public.list_group_history('aaaaaaaa-0000-0000-0000-000000000001')
            where before ? 'token' or after ? 'token'), 0, 'link codes never appear in history');

-- Live updates reach the group (read as postgres, past RLS).
reset role;
select ok(exists (select 1 from realtime.messages
                   where topic = 'group:aaaaaaaa-0000-0000-0000-000000000001'
                     and payload ->> 'table' = 'group_invite_links'),
          'link changes are broadcast to the group');
select ok(exists (select 1 from realtime.messages
                   where topic = 'group:aaaaaaaa-0000-0000-0000-000000000001'
                     and payload ->> 'table' = 'group_invitations'),
          'invitation changes are broadcast to the group too');

select * from finish();
rollback;

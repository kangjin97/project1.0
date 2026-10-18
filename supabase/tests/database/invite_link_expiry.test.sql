-- Invite links last at most 7 days, and the server picks the token and
-- bookkeeping columns (#82).
begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data) values
  ('11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'ann@example.test', '{"username":"ann"}');

create function pg_temp.act_as(p uuid) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated')::text, true);
$$;
grant execute on function pg_temp.act_as(uuid) to authenticated;

set local role authenticated;
select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
insert into groups (id, name, created_by) values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'Crew', '11111111-1111-1111-1111-111111111111');

-- What the app sends: 7 days from now.
insert into group_invite_links (id, group_id, expires_at) values
  ('dddddddd-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001', now() + interval '7 days');
select is((select expires_at from group_invite_links where id = 'dddddddd-0000-0000-0000-000000000001'),
          now() + interval '7 days', 'a 7-day link keeps its expiry');

-- No expiry: the server gives it 7 days.
insert into group_invite_links (id, group_id) values
  ('dddddddd-0000-0000-0000-000000000002', 'aaaaaaaa-0000-0000-0000-000000000001');
select is((select expires_at from group_invite_links where id = 'dddddddd-0000-0000-0000-000000000002'),
          now() + interval '7 days', 'a link without an expiry gets 7 days');

-- Too long, or "never": capped at 7 days.
insert into group_invite_links (id, group_id, expires_at) values
  ('dddddddd-0000-0000-0000-000000000003', 'aaaaaaaa-0000-0000-0000-000000000001', now() + interval '10 years');
select is((select expires_at from group_invite_links where id = 'dddddddd-0000-0000-0000-000000000003'),
          now() + interval '7 days', 'a longer expiry is capped at 7 days');

-- Shorter is fine.
insert into group_invite_links (id, group_id, expires_at) values
  ('dddddddd-0000-0000-0000-000000000004', 'aaaaaaaa-0000-0000-0000-000000000001', now() + interval '1 day');
select is((select expires_at from group_invite_links where id = 'dddddddd-0000-0000-0000-000000000004'),
          now() + interval '1 day', 'a shorter expiry is kept');

-- The client can't choose the token or fake the bookkeeping columns.
insert into group_invite_links (id, group_id, token, use_count, created_at, revoked_at) values
  ('dddddddd-0000-0000-0000-000000000005', 'aaaaaaaa-0000-0000-0000-000000000001', 'my-easy-token', -100,
   now() + interval '1 year', now() - interval '1 day');
select ok((select token ~ '^[0-9a-f]{64}$' from group_invite_links where id = 'dddddddd-0000-0000-0000-000000000005'),
          'the server picks a random 64-hex token');
select is((select (use_count, created_at, revoked_at)::text from group_invite_links
           where id = 'dddddddd-0000-0000-0000-000000000005'),
          (0, now(), null::timestamptz)::text, 'use count, created time and revoked time are the server''s');

-- Members still can't change the expiry afterwards (no column grant).
select throws_ok($$ update group_invite_links set expires_at = now() + interval '1 year'
                    where id = 'dddddddd-0000-0000-0000-000000000001' $$,
                 '42501', null, 'the expiry can''t be extended later');

select * from finish();
rollback;

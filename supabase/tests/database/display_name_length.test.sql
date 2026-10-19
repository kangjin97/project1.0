-- Display names are at most 50 characters (#83).
begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

-- Sign-up: a long name is cut to 50, a blank one becomes null, a normal one is kept.
insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data) values
  ('11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'ann@example.test',
   json_build_object('username', 'ann', 'display_name', repeat('a', 80))),
  ('22222222-2222-2222-2222-222222222222', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'ben@example.test',
   '{"username":"ben","display_name":"   "}'),
  ('33333333-3333-3333-3333-333333333333', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'cat@example.test',
   '{"username":"cat","display_name":"  Cat Tan  "}');

select is((select display_name from profiles where id = '11111111-1111-1111-1111-111111111111'), repeat('a', 50),
          'a long sign-up name is cut to 50 characters, not refused');
select is((select display_name from profiles where id = '22222222-2222-2222-2222-222222222222'), null,
          'a blank sign-up name is stored as null');
select is((select display_name from profiles where id = '33333333-3333-3333-3333-333333333333'), 'Cat Tan',
          'a normal sign-up name is kept, trimmed');

create function pg_temp.act_as(p uuid) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated')::text, true);
$$;
grant execute on function pg_temp.act_as(uuid) to authenticated;

-- Editing: 50 is fine, 51 is refused. Counts characters, not bytes.
set local role authenticated;
select pg_temp.act_as('33333333-3333-3333-3333-333333333333');
select lives_ok($$ update profiles set display_name = repeat('é', 50) where id = auth.uid() $$,
                'a 50-character name (multi-byte) can be saved');
select throws_ok($$ update profiles set display_name = repeat('b', 51) where id = auth.uid() $$,
                 '23514', null, 'a 51-character name is refused');

select * from finish();
rollback;

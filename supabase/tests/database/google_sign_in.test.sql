-- Sign in with Google: profile from Google's metadata, and the username step (#87).
begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

-- Ann signs up with our form; Gus with Google (full_name, no username or zone).
insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data) values
  ('11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'ann@example.test',
   '{"username":"ann","display_name":"Ann","timezone":"Asia/Singapore"}'),
  ('22222222-2222-2222-2222-222222222222', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'gus@example.test',
   '{"full_name":"Gus Goh","name":"Gus Goh","avatar_url":"https://lh3.googleusercontent.com/a/x=s96-c","email_verified":true}');

select is((select needs_username from profiles where id = '11111111-1111-1111-1111-111111111111'), false,
          'a form sign-up has chosen its username');
select is((select (username, display_name, timezone, needs_username)::text from profiles
           where id = '22222222-2222-2222-2222-222222222222'),
          ('user_222222222222', 'Gus Goh', 'UTC', true)::text,
          'a Google sign-up gets a placeholder username, Google''s name, UTC, and must pick a username');

create function pg_temp.act_as(p uuid) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated')::text, true);
$$;
grant execute on function pg_temp.act_as(uuid) to authenticated;

set local role authenticated;
select pg_temp.act_as('22222222-2222-2222-2222-222222222222');

select throws_ok($$ update profiles set needs_username = false where id = auth.uid() $$,
                 '42501', null, 'the flag can''t be cleared directly');
update profiles set display_name = 'Gus' where id = auth.uid();
select is((select needs_username from profiles where id = auth.uid()), true,
          'changing other fields doesn''t count as choosing a username');

update profiles set username = 'gus_goh' where id = auth.uid();
select is((select (username, needs_username)::text from profiles where id = auth.uid()),
          ('gus_goh', false)::text, 'picking a username clears the flag');

select * from finish();
rollback;

-- Time zones: set at sign-up from the device, validated, changeable, listed.
begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data) values
  ('11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   'sg@example.test', '{"username":"sg_user","timezone":"Asia/Singapore"}'),
  ('22222222-2222-2222-2222-222222222222', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   'bad@example.test', '{"username":"bad_tz","timezone":"Mars/Olympus_Mons"}'),
  ('33333333-3333-3333-3333-333333333333', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   'none@example.test', '{"username":"no_tz"}');

select is((select timezone from profiles where username = 'sg_user'), 'Asia/Singapore', 'sign-up uses the device zone');
select is((select timezone from profiles where username = 'bad_tz'), 'UTC', 'an unknown zone at sign-up falls back to UTC');
select is((select timezone from profiles where username = 'no_tz'), 'UTC', 'no zone at sign-up → UTC');

create function pg_temp.act_as(p uuid) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated')::text, true);
$$;
grant execute on function pg_temp.act_as(uuid) to authenticated;
set local role authenticated;
select pg_temp.act_as('11111111-1111-1111-1111-111111111111');

select lives_ok($$ update profiles set timezone = 'Europe/London' where id = auth.uid() $$, 'change to a valid zone');
select is((select timezone from profiles where id = auth.uid()), 'Europe/London', 'zone changed');
select throws_ok($$ update profiles set timezone = 'Nowhere/Land' where id = auth.uid() $$, '22023', null,
                 'unknown zones are rejected');

select ok((select count(*) from list_timezones()) > 300, 'the picker gets the full list');
select is((select row(region, city, offset_minutes)::text from list_timezones() where name = 'Asia/Kolkata'),
          '(Asia,Kolkata,330)', 'region, readable city and offset (UTC+05:30)');
select is((select city from list_timezones() where name = 'America/Argentina/Buenos_Aires'),
          'Argentina – Buenos Aires', 'nested names read nicely');
select ok((select bool_and(a.offset_minutes <= b.offset_minutes)
           from (select offset_minutes, row_number() over () rn from list_timezones()) a
           join (select offset_minutes, row_number() over () rn from list_timezones()) b on b.rn = a.rn + 1),
          'sorted by offset');

select * from finish();
rollback;

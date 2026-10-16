-- Google Maps locations: place IDs on activities and the daily API quota (#73).
begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data) values
  ('11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'ann@example.test', '{"username":"ann","timezone":"Asia/Singapore"}'),
  ('22222222-2222-2222-2222-222222222222', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'ben@example.test', '{"username":"ben"}');

create function pg_temp.act_as(p uuid) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated')::text, true);
$$;
grant execute on function pg_temp.act_as(uuid) to authenticated;

set local role authenticated;
select pg_temp.act_as('11111111-1111-1111-1111-111111111111');

-- Picking a place stores its ID next to the location text.
insert into activities (id, name, location, place_id) values
  ('bbbbbbbb-0000-0000-0000-000000000001', 'Beach day', 'Changi Beach Park, Nicoll Dr, Singapore', 'ChIJ_test_place_id_123');
select is((select place_id from activities where id = 'bbbbbbbb-0000-0000-0000-000000000001'), 'ChIJ_test_place_id_123',
          'an activity keeps the picked place''s ID');

select throws_ok($$ insert into activities (name, location, place_id) values ('Bad', 'Somewhere', 'https://evil.example/x') $$,
                 '23514', null, 'only well-formed place IDs are accepted');
select throws_ok($$ insert into activities (name, place_id) values ('No text', 'ChIJ_test_place_id_123') $$,
                 '23514', null, 'a place needs location text');

-- Editing the text without picking again drops the place.
update activities set location = 'Changi, somewhere' where id = 'bbbbbbbb-0000-0000-0000-000000000001';
select is((select place_id from activities where id = 'bbbbbbbb-0000-0000-0000-000000000001'), null,
          'changing the location text drops a place that wasn''t picked again');

-- Picking another place sets both together.
update activities set location = 'East Coast Park, Singapore', place_id = 'ChIJ_other_place_456'
 where id = 'bbbbbbbb-0000-0000-0000-000000000001';
select is((select place_id from activities where id = 'bbbbbbbb-0000-0000-0000-000000000001'), 'ChIJ_other_place_456',
          'picking a new place stores it');

-- Other edits leave the place alone.
update activities set price_max = 10 where id = 'bbbbbbbb-0000-0000-0000-000000000001';
select is((select place_id from activities where id = 'bbbbbbbb-0000-0000-0000-000000000001'), 'ChIJ_other_place_456',
          'editing other fields keeps the place');

-- Daily quota: 100 place searches per person per day.
select lives_ok($$ select consume_api_quota('places') from generate_series(1, 100) $$, 'the first 100 searches of the day are allowed');
select throws_ok($$ select consume_api_quota('places') $$, 'PT429', 'daily limit reached; try again tomorrow',
                 'the 101st is refused');
reset role;
select is((select count from api_usage where user_id = '11111111-1111-1111-1111-111111111111' and kind = 'places'), 100,
          'a refused call isn''t counted');
select is((select day from api_usage where user_id = '11111111-1111-1111-1111-111111111111'),
          (now() at time zone 'Asia/Singapore')::date, 'days follow the caller''s time zone');
set local role authenticated;

select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
select lives_ok($$ select consume_api_quota('places') $$, 'each person has their own quota');
select throws_ok($$ select consume_api_quota('something_else') $$, 'P0001', 'unknown quota', 'only known kinds can be counted');

-- AI fills from a link (#74): 30 a day, counted separately from place searches.
select lives_ok($$ select consume_api_quota('ai_fill') from generate_series(1, 30) $$, 'the first 30 AI fills of the day are allowed');
select throws_ok($$ select consume_api_quota('ai_fill') $$, 'PT429', 'daily limit reached; try again tomorrow',
                 'the 31st AI fill is refused');
select lives_ok($$ select consume_api_quota('places') $$, 'place searches have their own count');
select throws_ok($$ select * from api_usage $$, '42501', null, 'nobody reads the usage table directly');
select throws_ok($$ insert into api_usage (user_id, kind, day) values (auth.uid(), 'places', current_date) $$,
                 '42501', null, 'nobody writes it directly either');

set local role anon;
select throws_ok($$ select consume_api_quota('places') $$, '42501', null, 'signed-out callers have no quota');

select * from finish();
rollback;

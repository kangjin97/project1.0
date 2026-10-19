-- Coordinates cache for the distance filter (#94).
begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data) values
  ('11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'ann@example.test', '{"username":"ann"}');

-- What the Edge Function writes (as the service role; postgres here).
insert into place_coordinates (place_id, lat, lng, fetched_at) values
  ('ChIJtestFresh0001', 1.3048, 103.8318, now() - interval '29 days'),
  ('ChIJtestExpired001', 1.2834, 103.8607, now() - interval '31 days');

select throws_ok($$ insert into place_coordinates (place_id, lat, lng) values ('not a place id!', 1, 1) $$,
                 '23514', null, 'only place IDs can be cached');
select throws_ok($$ insert into place_coordinates (place_id, lat, lng) values ('ChIJtestBadLat01', 91, 1) $$,
                 '23514', null, 'latitude must be on Earth');

-- The daily job deletes what's past Google's 30 days and keeps the rest.
select is((select count(*)::int from cron.job where jobname = 'expire-place-coordinates'), 1, 'the expiry job is scheduled');
do $$ begin execute (select command from cron.job where jobname = 'expire-place-coordinates'); end $$;
select is((select array_agg(place_id order by place_id) from place_coordinates where place_id like 'ChIJtest%'),
          array['ChIJtestFresh0001'], 'the job removes coordinates older than 30 days');

create function pg_temp.act_as(p uuid) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated')::text, true);
$$;
grant execute on function pg_temp.act_as(uuid) to authenticated;

set local role authenticated;
select pg_temp.act_as('11111111-1111-1111-1111-111111111111');

select throws_ok($$ select * from place_coordinates $$, '42501', null, 'signed-in users can''t read the cache');
select throws_ok($$ insert into place_coordinates (place_id, lat, lng) values ('ChIJtestPlanted01', 1, 1) $$,
                 '42501', null, 'or plant coordinates');

-- 200 lookups a day, then refused.
select lives_ok($$ select consume_api_quota('place_coords') from generate_series(1, 200) $$, '200 lookups are allowed');
select throws_ok($$ select consume_api_quota('place_coords') $$, 'PT429', null, 'the 201st is refused');

select * from finish();
rollback;

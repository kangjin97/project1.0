-- Distance filter (#94): where each Google place is, so the app can show
-- activities near a point. Google lets apps keep place IDs indefinitely but
-- coordinates for at most 30 consecutive days, so they live in a cache keyed
-- by place ID (shared by every activity with that place) and expire.

create table public.place_coordinates (
  place_id   text primary key
             constraint place_coordinates_place_id_format
               check (place_id ~ '^[A-Za-z0-9_-]+$' and length(place_id) between 10 and 300),
  lat        double precision not null check (lat between -90 and 90),
  lng        double precision not null check (lng between -180 and 180),
  fetched_at timestamptz not null default now()
);

-- Only the place-coordinates Edge Function reads and writes it (with the
-- service role, after looking the place up at Google), so clients can't plant
-- or read stale coordinates.
alter table public.place_coordinates enable row level security;
revoke all on public.place_coordinates from anon, authenticated;

-- Delete coordinates once they're 30 days old, every day. The Edge Function
-- also ignores older rows, in case a run is missed.
create extension if not exists pg_cron;

select cron.schedule(
  'expire-place-coordinates',
  '17 19 * * *',
  $$delete from public.place_coordinates where fetched_at < now() - interval '30 days'$$
);

-- Looking a place up at Google costs money: 200 lookups per person per day.
-- A place already in the cache costs nothing and isn't counted.
create or replace function public.consume_api_quota(p_kind text) returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_limit int := case p_kind when 'places' then 100 when 'ai_fill' then 30 when 'place_coords' then 200 end;
  v_day   date;
  v_count int;
begin
  if auth.uid() is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;
  if v_limit is null then
    raise exception 'unknown quota';
  end if;

  select (now() at time zone p.timezone)::date into v_day
    from public.profiles p where p.id = auth.uid();

  insert into public.api_usage as u (user_id, kind, day, count)
  values (auth.uid(), p_kind, coalesce(v_day, current_date), 1)
  on conflict (user_id, kind, day) do update set count = u.count + 1
  returning u.count into v_count;

  if v_count > v_limit then
    -- PT429: PostgREST answers HTTP 429. The failed call's count is rolled back.
    raise exception 'daily limit reached; try again tomorrow' using errcode = 'PT429';
  end if;
end $$;

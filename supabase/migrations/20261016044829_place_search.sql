-- Google Maps locations (#73): an activity's location can point at an exact
-- Google place, picked from suggestions while typing; and a per-user daily
-- quota for paid outside APIs (the places Edge Function; #74 reuses it).

------------------------------------------------------------------------------
-- The picked place
------------------------------------------------------------------------------

-- Google lets apps keep place IDs indefinitely (Places API policies); the
-- location text stays the user's own field. The format check keeps anything
-- but an ID out (it ends up in a Google Maps link).
alter table public.activities
  add column place_id text
    constraint activities_place_id_format
      check (place_id ~ '^[A-Za-z0-9_-]+$' and length(place_id) between 10 and 300),
  add constraint activities_place_needs_location check (place_id is null or location is not null);

grant update (place_id) on public.activities to authenticated;

-- A place belongs to the text it was picked for: editing the location without
-- picking again drops it, whoever edits and however.
create function public.drop_stale_place() returns trigger
language plpgsql set search_path = '' as $$
begin
  if new.location is distinct from old.location and new.place_id is not distinct from old.place_id then
    new.place_id := null;
  end if;
  return new;
end $$;

revoke execute on function public.drop_stale_place() from public, anon, authenticated;

create trigger activities_drop_stale_place before update on public.activities
  for each row execute function public.drop_stale_place();

------------------------------------------------------------------------------
-- Daily quotas for paid outside APIs
------------------------------------------------------------------------------

-- One row per user, kind and day. Nobody reads or writes it directly: only
-- consume_api_quota does, as the caller.
create table public.api_usage (
  user_id uuid not null references public.profiles (id) on delete cascade,
  kind    text not null,
  day     date not null,
  count   int  not null default 0,
  primary key (user_id, kind, day)
);

alter table public.api_usage enable row level security;
revoke all on public.api_usage from anon, authenticated;

-- Counts one call of [p_kind] for the caller and refuses past the daily limit.
-- Days follow the caller's profile time zone. Called by Edge Functions with
-- the user's own token before they spend money on the outside API.
create function public.consume_api_quota(p_kind text) returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_limit int := case p_kind when 'places' then 100 end;
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

revoke execute on function public.consume_api_quota(text) from public, anon;
grant execute on function public.consume_api_quota(text) to authenticated;

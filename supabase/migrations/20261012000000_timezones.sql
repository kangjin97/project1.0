-- Changeable profile time zones.
--
-- The zone is set once at sign-up from the device (sign-up metadata
-- `timezone`); afterwards only the user changes it, from their profile.

create function public.is_valid_timezone(p_name text) returns boolean
language sql stable as $$
  select p_name = 'UTC' or exists (select 1 from pg_catalog.pg_timezone_names where name = p_name);
$$;

-- Reject unknown zone names on any write.
create function public.guard_timezone() returns trigger
language plpgsql as $$
begin
  if not public.is_valid_timezone(new.timezone) then
    raise exception 'unknown time zone: %', new.timezone using errcode = '22023';
  end if;
  return new;
end $$;

create trigger profiles_guard_timezone before insert or update of timezone on public.profiles
  for each row execute function public.guard_timezone();

-- Sign-up: take the device's zone from metadata when it's valid.
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_tz text := new.raw_user_meta_data ->> 'timezone';
begin
  insert into public.profiles (id, username, display_name, timezone)
  values (
    new.id,
    lower(coalesce(new.raw_user_meta_data ->> 'username',
                   'user_' || substr(replace(new.id::text, '-', ''), 1, 12))),
    new.raw_user_meta_data ->> 'display_name',
    case when v_tz is not null and public.is_valid_timezone(v_tz) then v_tz else 'UTC' end
  );
  return new;
end $$;

-- Zones for the picker, with their current offset from UTC (reflects daylight saving).
create function public.list_timezones()
returns table (name text, region text, city text, offset_minutes int)
language sql stable as $$
  select 'UTC', 'UTC', 'Coordinated Universal Time', 0
  union all
  select t.name,
         split_part(t.name, '/', 1),
         replace(replace(substr(t.name, strpos(t.name, '/') + 1), '_', ' '), '/', ' – '),
         (extract(epoch from t.utc_offset) / 60)::int
  from pg_catalog.pg_timezone_names t
  where t.name ~ '^(Africa|America|Antarctica|Asia|Atlantic|Australia|Europe|Indian|Pacific)/'
  order by 4, 3;
$$;

revoke execute on function public.list_timezones(), public.is_valid_timezone(text) from public, anon;
grant execute on function public.list_timezones(), public.is_valid_timezone(text) to authenticated;
revoke execute on function public.guard_timezone() from public, anon, authenticated;

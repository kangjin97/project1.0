-- Sign in with Google (#87). Google sends no username, so a first Google
-- sign-in gets a placeholder username and is asked to pick one before using
-- the app; choosing (or confirming) a username clears the flag.

alter table public.profiles add column needs_username boolean not null default false;

-- Sign-up: our own form sends username, display_name and timezone. Google
-- sends full_name / name instead, and no username or zone (the app sets the
-- device zone on the username step).
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_meta jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
  v_tz   text  := v_meta ->> 'timezone';
begin
  insert into public.profiles (id, username, display_name, timezone, needs_username)
  values (
    new.id,
    lower(coalesce(v_meta ->> 'username', 'user_' || substr(replace(new.id::text, '-', ''), 1, 12))),
    left(nullif(trim(coalesce(v_meta ->> 'display_name', v_meta ->> 'full_name', v_meta ->> 'name')), ''), 50),
    case when v_tz is not null and public.is_valid_timezone(v_tz) then v_tz else 'UTC' end,
    v_meta ->> 'username' is null
  );
  return new;
end $$;

-- Any write of the username (the username step, or Edit profile) means the
-- person has chosen one. Clients can't set needs_username themselves.
create function public.mark_username_chosen() returns trigger
language plpgsql set search_path = '' as $$
begin
  new.needs_username := false;
  return new;
end $$;

revoke execute on function public.mark_username_chosen() from public, anon, authenticated;

create trigger profiles_username_chosen before update of username on public.profiles
  for each row execute function public.mark_username_chosen();

-- Display names are at most 50 characters (#83). Edit profile already limited
-- it, but sign-up didn't and the database didn't check, so a direct API call
-- could store any length.

-- Shorten any existing long name first, so the check can be added.
update public.profiles set display_name = left(display_name, 50)
 where char_length(display_name) > 50;

alter table public.profiles add constraint profiles_display_name_length
  check (display_name is null or char_length(display_name) <= 50);

-- Sign-up: a long name from the sign-up metadata is cut to 50 rather than
-- failing the whole sign-up with a vague "Database error"; a blank one is
-- stored as null, like Edit profile does.
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
    left(nullif(trim(new.raw_user_meta_data ->> 'display_name'), ''), 50),
    case when v_tz is not null and public.is_valid_timezone(v_tz) then v_tz else 'UTC' end
  );
  return new;
end $$;

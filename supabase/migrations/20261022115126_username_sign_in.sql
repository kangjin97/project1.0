-- Sign in with a username (#107). Supabase Auth signs in by email, so the
-- username-sign-in Edge Function looks the email up here with the service
-- role and signs in on the person's behalf; the email never reaches the app.
-- Failed attempts per username are limited so passwords can't be guessed
-- through it (every attempt reaches Auth from the function's one address).

create table public.username_sign_in_failures (
  username     text not null,
  attempted_at timestamptz not null default now()
);

create index username_sign_in_failures_recent on public.username_sign_in_failures (username, attempted_at);

alter table public.username_sign_in_failures enable row level security;
revoke all on public.username_sign_in_failures from anon, authenticated;

-- The account's email for [p_username] (any letter case), or null when there's
-- no such user. Raises PT429 after 10 failed attempts in 15 minutes, counting
-- unknown usernames the same way so they can't be probed.
create function public.email_for_username(p_username text) returns text
language plpgsql security definer set search_path = '' as $$
declare
  v_name text := lower(trim(p_username));
begin
  if (select count(*) from public.username_sign_in_failures f
       where f.username = v_name and f.attempted_at > now() - interval '15 minutes') >= 10 then
    raise exception 'too many tries; wait 15 minutes or sign in with your email' using errcode = 'PT429';
  end if;
  return (select u.email from public.profiles p join auth.users u on u.id = p.id where p.username = v_name);
end $$;

-- After a wrong password or unknown username.
create function public.record_username_sign_in_failure(p_username text) returns void
language sql security definer set search_path = '' as $$
  insert into public.username_sign_in_failures (username) values (lower(trim(p_username)));
$$;

-- After a successful sign-in: the count starts again.
create function public.clear_username_sign_in_failures(p_username text) returns void
language sql security definer set search_path = '' as $$
  delete from public.username_sign_in_failures where username = lower(trim(p_username));
$$;

-- Only the Edge Function (service role) may use these.
revoke execute on function public.email_for_username(text) from public, anon, authenticated;
revoke execute on function public.record_username_sign_in_failure(text) from public, anon, authenticated;
revoke execute on function public.clear_username_sign_in_failures(text) from public, anon, authenticated;
grant execute on function public.email_for_username(text) to service_role;
grant execute on function public.record_username_sign_in_failure(text) to service_role;
grant execute on function public.clear_username_sign_in_failures(text) to service_role;

-- Old failures only matter for 15 minutes; clear them out daily.
select cron.schedule(
  'expire-username-sign-in-failures',
  '23 19 * * *',
  $$delete from public.username_sign_in_failures where attempted_at < now() - interval '1 day'$$
);

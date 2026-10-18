-- Invite links last at most 7 days (#82). Until now only the app set
-- expires_at; members can insert every column, so a direct API call could make
-- a link that never expires, pick its own (guessable) token, or start it with a
-- fake use count. The server now picks everything except the group, an earlier
-- expiry and max_uses.

create function public.guard_invite_link_insert() returns trigger
language plpgsql set search_path = '' as $$
declare
  v_cap timestamptz := now() + interval '7 days';
begin
  new.expires_at := least(coalesce(new.expires_at, v_cap), v_cap);
  new.token      := replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', '');
  new.created_at := now();
  new.use_count  := 0;
  new.revoked_at := null;
  return new;
end $$;

revoke execute on function public.guard_invite_link_insert() from public, anon, authenticated;

create trigger group_invite_links_guard_insert before insert on public.group_invite_links
  for each row execute function public.guard_invite_link_insert();

-- Existing links: none should run past 7 days, but cap any that do. Triggers
-- are off so this doesn't show up in group history or broadcast.
alter table public.group_invite_links disable trigger user;
update public.group_invite_links
   set expires_at = created_at + interval '7 days'
 where expires_at is null or expires_at > created_at + interval '7 days';
alter table public.group_invite_links enable trigger user;

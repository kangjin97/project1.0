-- cancel_email_change: drop the caller's pending email change.
-- Supabase Auth has no API for this, and asking to change back to the current
-- address is a no-op, so a change someone gave up on stayed pending forever.
-- Clearing the tokens also makes the links already sent stop working.
create or replace function public.cancel_email_change() returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_me uuid := auth.uid();
begin
  if v_me is null then
    raise exception 'not authenticated';
  end if;

  update auth.users
     set email_change = '',
         email_change_token_new = '',
         email_change_token_current = '',
         email_change_confirm_status = 0,
         email_change_sent_at = null
   where id = v_me;
end $$;

revoke execute on function public.cancel_email_change() from public, anon;
grant execute on function public.cancel_email_change() to authenticated;

-- delete_my_account: unshare the caller's activities before deleting them.
-- Deleting an activity cascades to group_activities only after the activity
-- row is gone, so the revert-to-event trigger couldn't read its name and the
-- schedule entries still referenced it.
create or replace function public.delete_my_account() returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_me uuid := auth.uid();
begin
  if v_me is null then
    raise exception 'not authenticated';
  end if;

  -- Plans that used their activities revert to events (group_activities trigger).
  delete from public.group_activities
   where activity_id in (select id from public.activities where owner_id = v_me);
  delete from public.activities where owner_id = v_me;

  -- Cascades: profile → memberships (ownership hand-over), participation,
  -- labels, invitations to them, notifications.
  delete from auth.users where id = v_me;
end $$;

-- Function privileges and search_path (CLAUDE.md rule 4; #19).
begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

-- Every function in public pins search_path, so a caller can't shadow the
-- names it uses.
select is(
  (select coalesce(string_agg(p.proname, ', ' order by p.proname), '')
     from pg_catalog.pg_proc p
    where p.pronamespace = 'public'::regnamespace
      and not exists (select 1 from unnest(coalesce(p.proconfig, '{}')) c where c like 'search_path=%')),
  '', 'every public function sets search_path');

-- Signed-out callers can only check whether a username is free.
select is(
  (select coalesce(string_agg(p.proname, ', ' order by p.proname), '')
     from pg_catalog.pg_proc p
    where p.pronamespace = 'public'::regnamespace
      and has_function_privilege('anon', p.oid, 'execute')),
  'username_available', 'anon can execute only username_available');

-- Trigger functions and internal helpers aren't callable by clients.
select is(has_function_privilege('authenticated', f::regprocedure, 'execute'), false, f || ' is not executable by authenticated')
from unnest(array[
  'public.handle_new_user()', 'public.handle_new_group()', 'public.log_change()', 'public.notify_invitee()',
  'public.revert_entries_to_events()', 'public.touch_updated()',
  'public.group_activity_defaults()', 'public.guard_personal_type()', 'public.refile_activity()',
  'public.refile_renamed_label()', 'public.guard_timezone()', 'public.hand_over_ownership()',
  'public.broadcast_change()', 'public.guard_invite_link_revoke()',
  'public.resolve_group_type(uuid, text)', 'public.apply_participants(uuid, uuid[], jsonb)',
  'public.entry_range(boolean, date, timestamptz, timestamptz, text)'
]) f;

-- Helpers that policies, invoker triggers or the app need stay callable.
select is(has_function_privilege('authenticated', f::regprocedure, 'execute'), true, f || ' stays executable by authenticated')
from unnest(array['public.try_uuid(text)', 'public.is_valid_timezone(text)', 'public.list_timezones()']) f;

-- Pinning search_path didn't change what the helpers return.
select is(public.try_uuid('not-a-uuid'), null, 'try_uuid still returns null for junk');
select ok(public.is_valid_timezone('Asia/Kuala_Lumpur'), 'is_valid_timezone still knows aliases');
select ok((select count(*) from public.list_timezones()) > 300, 'list_timezones still lists zones');

select * from finish();
rollback;

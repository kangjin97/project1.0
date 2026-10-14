-- Tidy function privileges and pin search_path (#19).
--
-- Trigger functions: Postgres never checks EXECUTE when firing a trigger, so
-- clients don't need it; revoke it like the other trigger functions.
-- entry_range is only called by find_clashes (security definer), so it's an
-- internal helper too. try_uuid (storage policies), is_valid_timezone (an
-- invoker trigger) and list_timezones (the picker) stay callable.
revoke execute on function
  public.handle_new_user(),
  public.handle_new_group(),
  public.log_change(),
  public.notify_invitee(),
  public.revert_entries_to_events(),
  public.touch_updated(),
  public.entry_range(boolean, date, timestamptz, timestamptz, text)
from authenticated;

-- These run with the caller's rights and already use fully qualified names;
-- an empty search_path makes that a guarantee (Supabase's linter flags them).
alter function public.try_uuid(text) set search_path = '';
alter function public.entry_range(boolean, date, timestamptz, timestamptz, text) set search_path = '';
alter function public.touch_updated() set search_path = '';
alter function public.guard_personal_type() set search_path = '';
alter function public.is_valid_timezone(text) set search_path = '';
alter function public.guard_timezone() set search_path = '';
alter function public.list_timezones() set search_path = '';

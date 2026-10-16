-- "Fill an activity from a link" (#74): its own daily quota, 30 AI fills per
-- person per day (owner's choice). Same as 20261016044829 otherwise.
create or replace function public.consume_api_quota(p_kind text) returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_limit int := case p_kind when 'places' then 100 when 'ai_fill' then 30 end;
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

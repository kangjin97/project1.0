-- #17: recurring plans. A series is a repeat rule; every occurrence is an
-- ordinary schedule entry with series_id set, so clash checks, participants,
-- notifications, history, live updates and drag keep working per occurrence.
-- Owner's choices: weekly / every 2 weeks / monthly; ends on a date at most a
-- year after the first; edits apply to "this one" or "this and following";
-- one notification per series.

------------------------------------------------------------------------------
-- Schema
------------------------------------------------------------------------------

create table public.schedule_series (
  id         uuid primary key default gen_random_uuid(),
  group_id   uuid not null references public.groups (id) on delete cascade,
  freq       text not null check (freq in ('weekly', 'biweekly', 'monthly')),
  until      date not null,
  -- Occurrences repeat at the same wall-clock time in this zone (the planner's),
  -- so 7pm stays 7pm across daylight saving changes.
  tz         text not null,
  created_by uuid default auth.uid() references public.profiles (id) on delete set null,
  created_at timestamptz not null default now(),
  unique (id, group_id)
);

alter table public.schedule_entries add column series_id uuid;
alter table public.schedule_entries
  add constraint schedule_entries_series_fk foreign key (series_id, group_id)
  references public.schedule_series (id, group_id) on delete set null (series_id);
create index schedule_entries_series_idx on public.schedule_entries (series_id);

alter table public.schedule_series enable row level security;
create policy schedule_series_select on public.schedule_series for select to authenticated
  using (public.is_group_member(group_id));
revoke all on public.schedule_series from anon, authenticated;
grant select on public.schedule_series to authenticated;

------------------------------------------------------------------------------
-- Helpers (internal)
------------------------------------------------------------------------------

-- The local start of each occurrence, from the first, up to and including p_until.
-- Monthly repeats on the same date; the 31st falls back to a shorter month's last day.
create function public.series_dates(p_first timestamp, p_freq text, p_until date)
returns table (n int, local_start timestamp)
language sql immutable set search_path = '' as $$
  select k, s
  from pg_catalog.generate_series(0, 60) k,
       lateral (select p_first + case p_freq
                  when 'weekly' then pg_catalog.make_interval(days => 7 * k)
                  when 'biweekly' then pg_catalog.make_interval(days => 14 * k)
                  else pg_catalog.make_interval(months => k) end) t (s)
  where s::date <= p_until
  order by k;
$$;

-- When an entry happens, for ordering occurrences of a series.
create function public.entry_key(e public.schedule_entries, p_tz text) returns timestamptz
language sql stable set search_path = '' as $$
  select coalesce(e.start_at, e.date::timestamp at time zone p_tz);
$$;

-- The entries an edit applies to: just this one, or this and the later
-- occurrences of its series (past ones are never touched).
create function public.series_targets(p_entry uuid, p_scope text) returns uuid[]
language sql stable security definer set search_path = '' as $$
  select case
    when p_scope = 'following' and e.series_id is not null then array(
      select o.id from public.schedule_entries o
      where o.series_id = e.series_id
        and public.entry_key(o, s.tz) >= public.entry_key(e, s.tz)
      order by public.entry_key(o, s.tz))
    else array[e.id] end
  from public.schedule_entries e
  left join public.schedule_series s on s.id = e.series_id
  where e.id = p_entry;
$$;

-- Same as before, plus p_notify: series operations notify once per person
-- instead of once per occurrence.
drop function public.apply_participants(uuid, uuid[], jsonb);
create function public.apply_participants(
  p_entry uuid, p_new_user_ids uuid[], p_clashes jsonb, p_notify boolean default true
) returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_entry    public.schedule_entries;
  v_clashing uuid[] := array(select distinct (c ->> 'user_id')::uuid from jsonb_array_elements(p_clashes) c);
begin
  select * into v_entry from public.schedule_entries where id = p_entry;

  insert into public.schedule_participants (entry_id, user_id, status)
  select p_entry, u, case when u = any (v_clashing) then 'clash' else 'added' end
  from unnest(p_new_user_ids) u
  on conflict (entry_id, user_id) do nothing;

  update public.schedule_participants sp
     set status = case when sp.user_id = any (v_clashing) then 'clash' else 'added' end
   where sp.entry_id = p_entry
     and sp.status is distinct from case when sp.user_id = any (v_clashing) then 'clash' else 'added' end;

  if p_notify then
    insert into public.notifications (user_id, kind, payload)
    select sp.user_id,
           case when sp.status = 'clash' then 'schedule_clash' else 'added_to_entry' end,
           jsonb_build_object(
             'entry_id', p_entry, 'group_id', v_entry.group_id, 'by', auth.uid(),
             'clashes', coalesce((select jsonb_agg(c) from jsonb_array_elements(p_clashes) c
                                  where (c ->> 'user_id')::uuid = sp.user_id), '[]'))
    from public.schedule_participants sp
    where sp.entry_id = p_entry
      and sp.user_id <> auth.uid()
      and (sp.user_id = any (p_new_user_ids) or sp.status = 'clash');
  end if;

  if cardinality(v_clashing) > 0 then
    insert into public.change_log (actor_id, group_id, entity_type, entity_id, action, after)
    values (auth.uid(), v_entry.group_id, 'schedule_entry', p_entry, 'clash_override',
            jsonb_build_object('clashes', p_clashes));
  end if;
end $$;

-- One notification per person for a series operation: the first affected
-- occurrence (for the title and tap-through) and every clash of theirs.
create function public.notify_series(
  p_kind text, p_series uuid, p_group uuid, p_first_entry uuid, p_people uuid[], p_clashes jsonb
) returns void
language sql security definer set search_path = '' as $$
  insert into public.notifications (user_id, kind, payload)
  select u, p_kind,
         jsonb_build_object(
           'series_id', p_series, 'entry_id', p_first_entry, 'group_id', p_group, 'by', auth.uid(),
           'clashes', coalesce((select jsonb_agg(c) from jsonb_array_elements(p_clashes) c
                                where (c ->> 'user_id')::uuid = u), '[]'))
  from unnest(p_people) u
  where u <> auth.uid();
$$;

------------------------------------------------------------------------------
-- Creating and extending a series
------------------------------------------------------------------------------

-- Like create_schedule_entry, for a repeating plan. Every occurrence is checked
-- for clashes; nothing is saved unless there are none or p_force is set.
create function public.create_schedule_series(
  p_group_id uuid,
  p_activity_id uuid,
  p_title text,
  p_all_day boolean,
  p_date date,
  p_start_at timestamptz,
  p_end_at timestamptz,
  p_participant_ids uuid[],
  p_freq text,
  p_until date,
  p_force boolean default false
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_people  uuid[];
  v_tz      text := coalesce((select timezone from public.profiles where id = auth.uid()), 'UTC');
  v_first   timestamp;
  v_dur     interval;
  v_occ     jsonb := '[]';
  v_clashes jsonb := '[]';
  v_series  uuid;
  v_entry   uuid;
  v_ids     uuid[] := '{}';
  o         record;
  c         jsonb;
begin
  if not public.is_group_member(p_group_id) then
    raise exception 'not a member of this group';
  end if;
  if p_freq is null or p_freq not in ('weekly', 'biweekly', 'monthly') then
    raise exception 'choose how often it repeats';
  end if;
  if coalesce(p_all_day, false) then
    if p_date is null then raise exception 'a repeating plan needs a date'; end if;
    v_first := p_date::timestamp;
  else
    if p_start_at is null or p_end_at is null then raise exception 'a repeating plan needs a date'; end if;
    v_first := p_start_at at time zone v_tz;
    v_dur := p_end_at - p_start_at;
  end if;
  if p_until is null or p_until > (v_first + interval '1 year')::date then
    raise exception 'repeats can end at most a year after the first date';
  end if;

  v_people := array(select distinct u from unnest(coalesce(p_participant_ids, array[auth.uid()])) u where u is not null);
  if exists (select 1 from unnest(v_people) u
             where not exists (select 1 from public.group_members gm
                               where gm.group_id = p_group_id and gm.user_id = u)) then
    raise exception 'all participants must be members of the group';
  end if;

  for o in select * from public.series_dates(v_first, p_freq, p_until) loop
    v_occ := v_occ || jsonb_build_object(
      'date', case when coalesce(p_all_day, false) then o.local_start::date end,
      'start_at', case when not coalesce(p_all_day, false) then o.local_start at time zone v_tz end,
      'end_at', case when not coalesce(p_all_day, false) then (o.local_start at time zone v_tz) + v_dur end);
  end loop;
  if jsonb_array_length(v_occ) < 2 then
    raise exception 'a repeating plan needs at least two dates before it ends';
  end if;

  for c in select * from jsonb_array_elements(v_occ) loop
    select v_clashes || coalesce(jsonb_agg(to_jsonb(x)), '[]') into v_clashes
    from public.find_clashes(v_people, coalesce(p_all_day, false), (c ->> 'date')::date,
                             (c ->> 'start_at')::timestamptz, (c ->> 'end_at')::timestamptz) x;
  end loop;
  if jsonb_array_length(v_clashes) > 0 and not p_force then
    return jsonb_build_object('status', 'clash', 'clashes', v_clashes);
  end if;

  insert into public.schedule_series (group_id, freq, until, tz)
  values (p_group_id, p_freq, p_until, v_tz) returning id into v_series;

  for c in select * from jsonb_array_elements(v_occ) loop
    insert into public.schedule_entries (group_id, activity_id, title, all_day, date, start_at, end_at, series_id)
    values (p_group_id, p_activity_id, nullif(trim(p_title), ''), coalesce(p_all_day, false),
            (c ->> 'date')::date, (c ->> 'start_at')::timestamptz, (c ->> 'end_at')::timestamptz, v_series)
    returning id into v_entry;
    v_ids := v_ids || v_entry;
    perform public.apply_participants(v_entry, v_people,
      (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from public.find_clashes(v_people, coalesce(p_all_day, false),
         (c ->> 'date')::date, (c ->> 'start_at')::timestamptz, (c ->> 'end_at')::timestamptz, v_entry) x),
      false);
  end loop;

  perform public.notify_series('added_to_series', v_series, p_group_id, v_ids[1], v_people, v_clashes);
  return jsonb_build_object('status', 'created', 'entry_id', v_ids[1], 'series_id', v_series,
                            'count', cardinality(v_ids), 'clashes', v_clashes);
end $$;

-- Adds occurrences after the last one, up to p_until (at most a year from
-- today). New occurrences copy the last one: title, activity, length, people.
create function public.extend_series(p_entry uuid, p_until date, p_force boolean default false) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_series  public.schedule_series;
  v_last    public.schedule_entries;
  v_people  uuid[];
  v_first   timestamp;
  v_dur     interval;
  v_occ     jsonb := '[]';
  v_clashes jsonb := '[]';
  v_entry   uuid;
  v_ids     uuid[] := '{}';
  o         record;
  c         jsonb;
begin
  select s.* into v_series from public.schedule_series s
    join public.schedule_entries e on e.series_id = s.id where e.id = p_entry;
  if not found or not public.is_group_member(v_series.group_id) then
    raise exception 'not a member of this group';
  end if;
  if p_until is null or p_until <= v_series.until then
    raise exception 'choose a later end date';
  end if;
  if p_until > ((now() at time zone v_series.tz) + interval '1 year')::date then
    raise exception 'repeats can end at most a year from today';
  end if;

  select e.* into v_last from public.schedule_entries e
   where e.series_id = v_series.id order by public.entry_key(e, v_series.tz) desc limit 1;
  v_people := array(select user_id from public.schedule_participants where entry_id = v_last.id);
  v_first := coalesce(v_last.start_at at time zone v_series.tz, v_last.date::timestamp);
  v_dur := v_last.end_at - v_last.start_at;

  for o in select * from public.series_dates(v_first, v_series.freq, p_until) where n > 0 loop
    v_occ := v_occ || jsonb_build_object(
      'date', case when v_last.all_day then o.local_start::date end,
      'start_at', case when not v_last.all_day then o.local_start at time zone v_series.tz end,
      'end_at', case when not v_last.all_day then (o.local_start at time zone v_series.tz) + v_dur end);
  end loop;

  for c in select * from jsonb_array_elements(v_occ) loop
    select v_clashes || coalesce(jsonb_agg(to_jsonb(x)), '[]') into v_clashes
    from public.find_clashes(v_people, v_last.all_day, (c ->> 'date')::date,
                             (c ->> 'start_at')::timestamptz, (c ->> 'end_at')::timestamptz) x;
  end loop;
  if jsonb_array_length(v_clashes) > 0 and not p_force then
    return jsonb_build_object('status', 'clash', 'clashes', v_clashes);
  end if;

  update public.schedule_series set until = p_until where id = v_series.id;
  for c in select * from jsonb_array_elements(v_occ) loop
    insert into public.schedule_entries (group_id, activity_id, title, all_day, date, start_at, end_at, series_id)
    values (v_series.group_id, v_last.activity_id, v_last.title, v_last.all_day,
            (c ->> 'date')::date, (c ->> 'start_at')::timestamptz, (c ->> 'end_at')::timestamptz, v_series.id)
    returning id into v_entry;
    v_ids := v_ids || v_entry;
    perform public.apply_participants(v_entry, v_people,
      (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from public.find_clashes(v_people, v_last.all_day,
         (c ->> 'date')::date, (c ->> 'start_at')::timestamptz, (c ->> 'end_at')::timestamptz, v_entry) x),
      false);
  end loop;

  if cardinality(v_ids) > 0 then
    perform public.notify_series('added_to_series', v_series.id, v_series.group_id, v_ids[1], v_people, v_clashes);
  end if;
  return jsonb_build_object('status', 'updated', 'entry_id', v_ids[1], 'count', cardinality(v_ids),
                            'clashes', v_clashes);
end $$;

------------------------------------------------------------------------------
-- "This and following"
------------------------------------------------------------------------------

-- Moves this occurrence like reschedule_entry and shifts the later ones by the
-- same amount of wall-clock time (and gives them the new length). Clashes with
-- the series' own occurrences don't count.
create function public.reschedule_following(
  p_entry uuid, p_all_day boolean, p_date date, p_start_at timestamptz, p_end_at timestamptz,
  p_force boolean default false
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_this    public.schedule_entries;
  v_tz      text;
  v_targets uuid[];
  v_shift   interval;
  v_dur     interval;
  v_plan    jsonb := '[]';
  v_clashes jsonb := '[]';
  v_people  uuid[] := '{}';
  t         public.schedule_entries;
  c         jsonb;
  v_new     timestamp;
begin
  select * into v_this from public.schedule_entries where id = p_entry;
  if not found or not public.is_group_member(v_this.group_id) then
    raise exception 'not a member of this group';
  end if;
  v_tz := coalesce((select tz from public.schedule_series where id = v_this.series_id), 'UTC');
  v_targets := public.series_targets(p_entry, 'following');
  if coalesce(p_all_day, false) then
    if p_date is null then raise exception 'choose a date'; end if;
  elsif p_start_at is null or p_end_at is null then
    raise exception 'choose a date';
  end if;

  v_shift := coalesce(p_start_at at time zone v_tz, p_date::timestamp)
           - coalesce(v_this.start_at at time zone v_tz, v_this.date::timestamp);
  v_dur := p_end_at - p_start_at;

  for t in select * from public.schedule_entries where id = any (v_targets) loop
    v_new := coalesce(t.start_at at time zone v_tz, t.date::timestamp) + v_shift;
    v_plan := v_plan || jsonb_build_object(
      'id', t.id,
      'date', case when coalesce(p_all_day, false) then v_new::date end,
      'start_at', case when not coalesce(p_all_day, false) then v_new at time zone v_tz end,
      'end_at', case when not coalesce(p_all_day, false) then (v_new at time zone v_tz) + v_dur end);
  end loop;

  for c in select * from jsonb_array_elements(v_plan) loop
    select v_clashes || coalesce(jsonb_agg(to_jsonb(x)), '[]') into v_clashes
    from public.find_clashes(
           array(select user_id from public.schedule_participants where entry_id = (c ->> 'id')::uuid),
           coalesce(p_all_day, false), (c ->> 'date')::date,
           (c ->> 'start_at')::timestamptz, (c ->> 'end_at')::timestamptz, (c ->> 'id')::uuid) x
    where x.entry_id <> all (v_targets);
  end loop;
  if jsonb_array_length(v_clashes) > 0 and not p_force then
    return jsonb_build_object('status', 'clash', 'clashes', v_clashes);
  end if;

  for c in select * from jsonb_array_elements(v_plan) loop
    update public.schedule_entries
       set all_day = coalesce(p_all_day, false), date = (c ->> 'date')::date,
           start_at = (c ->> 'start_at')::timestamptz, end_at = (c ->> 'end_at')::timestamptz
     where id = (c ->> 'id')::uuid;
    perform public.apply_participants((c ->> 'id')::uuid, '{}',
      (select coalesce(jsonb_agg(x), '[]') from jsonb_array_elements(v_clashes) x
        where exists (select 1 from public.schedule_participants sp
                      where sp.entry_id = (c ->> 'id')::uuid and sp.user_id = (x ->> 'user_id')::uuid)
          and public.entry_range(coalesce(p_all_day, false), (c ->> 'date')::date,
                (c ->> 'start_at')::timestamptz, (c ->> 'end_at')::timestamptz, v_tz)
              && public.entry_range((x ->> 'all_day')::boolean, (x ->> 'entry_date')::date,
                (x ->> 'start_at')::timestamptz, (x ->> 'end_at')::timestamptz, v_tz)),
      false);
  end loop;

  -- One clash notification per person, pointing at their first clashing date.
  v_people := array(select distinct (x ->> 'user_id')::uuid from jsonb_array_elements(v_clashes) x);
  if cardinality(v_people) > 0 then
    perform public.notify_series('schedule_clash', v_this.series_id, v_this.group_id,
      (select sp.entry_id from public.schedule_participants sp
        join public.schedule_entries e on e.id = sp.entry_id
       where sp.entry_id = any (v_targets) and sp.status = 'clash'
       order by public.entry_key(e, v_tz) limit 1),
      v_people, v_clashes);
  end if;
  return jsonb_build_object('status', 'updated', 'entry_id', p_entry, 'count', cardinality(v_targets),
                            'clashes', v_clashes);
end $$;

-- Adds people to this and the later occurrences; one notification each.
create function public.add_participants_following(
  p_entry uuid, p_user_ids uuid[], p_force boolean default false
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_this    public.schedule_entries;
  v_targets uuid[];
  v_people  uuid[];
  v_clashes jsonb := '[]';
  t         public.schedule_entries;
  v_new     uuid[];
begin
  select * into v_this from public.schedule_entries where id = p_entry;
  if not found or not public.is_group_member(v_this.group_id) then
    raise exception 'not a member of this group';
  end if;
  v_targets := public.series_targets(p_entry, 'following');
  v_people := array(select distinct u from unnest(p_user_ids) u where u is not null);
  if exists (select 1 from unnest(v_people) u
             where not exists (select 1 from public.group_members gm
                               where gm.group_id = v_this.group_id and gm.user_id = u)) then
    raise exception 'all participants must be members of the group';
  end if;

  for t in select * from public.schedule_entries where id = any (v_targets) loop
    v_new := array(select u from unnest(v_people) u
                   where not exists (select 1 from public.schedule_participants
                                     where entry_id = t.id and user_id = u));
    select v_clashes || coalesce(jsonb_agg(to_jsonb(x)), '[]') into v_clashes
    from public.find_clashes(v_new, t.all_day, t.date, t.start_at, t.end_at, t.id) x
    where x.entry_id <> all (v_targets);
  end loop;
  if jsonb_array_length(v_clashes) > 0 and not p_force then
    return jsonb_build_object('status', 'clash', 'clashes', v_clashes);
  end if;

  for t in select * from public.schedule_entries where id = any (v_targets) loop
    v_new := array(select u from unnest(v_people) u
                   where not exists (select 1 from public.schedule_participants
                                     where entry_id = t.id and user_id = u));
    -- Keep existing participants' clash status intact, as add_entry_participants does.
    perform public.apply_participants(t.id, v_new,
      (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from public.find_clashes(
         array(select user_id from public.schedule_participants where entry_id = t.id) || v_new,
         t.all_day, t.date, t.start_at, t.end_at, t.id) x
       where x.entry_id <> all (v_targets)),
      false);
  end loop;

  perform public.notify_series('added_to_series', v_this.series_id, v_this.group_id, p_entry, v_people, v_clashes);
  return jsonb_build_object('status', 'updated', 'entry_id', p_entry, 'count', cardinality(v_targets),
                            'clashes', v_clashes);
end $$;

-- Renames (events), swaps the activity, removes, or takes the caller off this
-- and the later occurrences. Same rules as the single-entry versions.
create function public.rename_following(p_entry uuid, p_title text) returns int
language plpgsql security definer set search_path = '' as $$
declare v_targets uuid[];
begin
  if not public.is_group_member(public.entry_group(p_entry)) then
    raise exception 'not a member of this group';
  end if;
  v_targets := public.series_targets(p_entry, 'following');
  update public.schedule_entries set title = nullif(trim(p_title), '') where id = any (v_targets);
  return cardinality(v_targets);
end $$;

create function public.set_activity_following(p_entry uuid, p_activity_id uuid) returns int
language plpgsql security definer set search_path = '' as $$
declare v_targets uuid[];
begin
  if not public.is_group_member(public.entry_group(p_entry)) then
    raise exception 'not a member of this group';
  end if;
  v_targets := public.series_targets(p_entry, 'following');
  update public.schedule_entries set activity_id = p_activity_id where id = any (v_targets);
  return cardinality(v_targets);
end $$;

create function public.delete_following(p_entry uuid) returns int
language plpgsql security definer set search_path = '' as $$
declare v_targets uuid[];
begin
  if not public.is_group_member(public.entry_group(p_entry)) then
    raise exception 'not a member of this group';
  end if;
  v_targets := public.series_targets(p_entry, 'following');
  delete from public.schedule_entries where id = any (v_targets);
  return cardinality(v_targets);
end $$;

-- Participants can leave even after leaving the group, like leaving one plan.
create function public.leave_following(p_entry uuid) returns int
language plpgsql security definer set search_path = '' as $$
declare v_targets uuid[];
begin
  if not public.is_entry_participant(p_entry) then
    raise exception 'you''re not in this plan';
  end if;
  v_targets := public.series_targets(p_entry, 'following');
  delete from public.schedule_participants where entry_id = any (v_targets) and user_id = auth.uid();
  return cardinality(v_targets);
end $$;

------------------------------------------------------------------------------
-- Read models: series details on plans, notifications and history
------------------------------------------------------------------------------

drop function public.list_schedule(date, date, text, uuid, boolean);
create function public.list_schedule(
  p_from date,
  p_to date,
  p_tz text default 'UTC',
  p_group uuid default null,
  p_include_unscheduled boolean default false
) returns table (
  id uuid,
  group_id uuid,
  group_name text,
  activity_id uuid,
  activity_name text,
  title text,
  all_day boolean,
  date date,
  start_at timestamptz,
  end_at timestamptz,
  created_by uuid,
  my_status text,
  participants jsonb,
  series_id uuid,
  series_freq text,
  series_until date
)
language sql stable security definer set search_path = '' as $$
  select e.id, e.group_id, g.name, e.activity_id, a.name, e.title,
         e.all_day, e.date, e.start_at, e.end_at, e.created_by,
         me.status,
         coalesce((
           select jsonb_agg(jsonb_build_object(
                    'user_id', p.user_id, 'username', pr.username,
                    'display_name', pr.display_name, 'avatar_path', pr.avatar_path,
                    'status', p.status)
                  order by pr.username)
           from public.schedule_participants p
           join public.profiles pr on pr.id = p.user_id
           where p.entry_id = e.id), '[]'),
         s.id, s.freq, s.until
  from public.schedule_entries e
  join public.groups g on g.id = e.group_id
  left join public.activities a on a.id = e.activity_id
  left join public.schedule_series s on s.id = e.series_id
  left join public.schedule_participants me on me.entry_id = e.id and me.user_id = auth.uid()
  where auth.uid() is not null
    and case when p_group is null then me.user_id is not null
             else e.group_id = p_group and public.is_group_member(p_group) end
    and (
      (e.all_day and e.date between p_from and p_to)
      or (e.start_at is not null
          and tstzrange(e.start_at, e.end_at, '[)')
              && tstzrange(p_from::timestamp at time zone p_tz, (p_to + 1)::timestamp at time zone p_tz, '[)'))
      or (p_include_unscheduled and e.date is null and e.start_at is null)
    )
  order by coalesce(e.start_at, e.date::timestamp at time zone p_tz) nulls first, e.created_at;
$$;
revoke execute on function public.list_schedule(date, date, text, uuid, boolean) from public, anon;
grant execute on function public.list_schedule(date, date, text, uuid, boolean) to authenticated;

drop function public.list_notifications(int);
create function public.list_notifications(p_limit int default 50)
returns table (
  id                uuid,
  kind              text,
  created_at        timestamptz,
  read_at           timestamptz,
  actor_id          uuid,
  actor_name        text,
  group_id          uuid,
  group_name        text,
  invitation_status text,
  entry_id          uuid,
  entry_title       text,
  entry_all_day     boolean,
  entry_date        date,
  entry_start_at    timestamptz,
  entry_end_at      timestamptz,
  clash_count       int,
  series_freq       text,
  series_until      date
)
language sql stable security definer set search_path = '' as $$
  select n.id, n.kind, n.created_at, n.read_at,
         a.id, coalesce(a.display_name, a.username),
         g.id, coalesce(g.name, case when n.kind = 'group_deleted' then n.payload ->> 'group_name' end),
         i.status,
         se.id, coalesce(act.name, se.title), se.all_day, se.date, se.start_at, se.end_at,
         pg_catalog.jsonb_array_length(coalesce(n.payload -> 'clashes', '[]'::jsonb)),
         s.freq, s.until
  from public.notifications n
  left join public.profiles a
         on a.id = public.try_uuid(coalesce(n.payload ->> 'invited_by', n.payload ->> 'by'))
  left join public.group_invitations i
         on n.kind = 'group_invitation' and i.id = public.try_uuid(n.payload ->> 'invitation_id')
  left join public.groups g
         on g.id = public.try_uuid(n.payload ->> 'group_id')
        and (public.is_group_member(g.id) or i.invitee_id = auth.uid())
  left join public.schedule_entries se
         on se.id = public.try_uuid(n.payload ->> 'entry_id')
        and (public.is_entry_participant(se.id) or public.is_group_member(se.group_id))
  left join public.activities act on act.id = se.activity_id
  -- Series details only while its plan is visible.
  left join public.schedule_series s
         on se.id is not null and s.id = public.try_uuid(n.payload ->> 'series_id')
  where n.user_id = auth.uid()
  order by n.created_at desc, n.id
  limit greatest(1, least(coalesce(p_limit, 50), 200));
$$;
revoke execute on function public.list_notifications(int) from public, anon;
grant execute on function public.list_notifications(int) to authenticated;

revoke execute on function
  public.series_dates(timestamp, text, date),
  public.entry_key(public.schedule_entries, text),
  public.series_targets(uuid, text),
  public.apply_participants(uuid, uuid[], jsonb, boolean),
  public.notify_series(text, uuid, uuid, uuid, uuid[], jsonb)
from public, anon, authenticated;

revoke execute on function
  public.create_schedule_series(uuid, uuid, text, boolean, date, timestamptz, timestamptz, uuid[], text, date, boolean),
  public.extend_series(uuid, date, boolean),
  public.reschedule_following(uuid, boolean, date, timestamptz, timestamptz, boolean),
  public.add_participants_following(uuid, uuid[], boolean),
  public.rename_following(uuid, text),
  public.set_activity_following(uuid, uuid),
  public.delete_following(uuid),
  public.leave_following(uuid)
from public, anon;
grant execute on function
  public.create_schedule_series(uuid, uuid, text, boolean, date, timestamptz, timestamptz, uuid[], text, date, boolean),
  public.extend_series(uuid, date, boolean),
  public.reschedule_following(uuid, boolean, date, timestamptz, timestamptz, boolean),
  public.add_participants_following(uuid, uuid[], boolean),
  public.rename_following(uuid, text),
  public.set_activity_following(uuid, uuid),
  public.delete_following(uuid),
  public.leave_following(uuid)
to authenticated;

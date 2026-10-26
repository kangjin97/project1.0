-- Save a copy of someone's activity to my activities (#112).
--
-- A copy is an ordinary private activity owned by the person who saved it,
-- independent of the original. It remembers the original in copied_from, so
-- its page can say where it came from and the original's page can offer
-- "Open your copy" instead of saving a second one. Photo files are copied by
-- the app afterwards (Storage can't copy files from SQL); their rows go in
-- through the usual activity_photos policies.

alter table public.activities
  add column copied_from uuid references public.activities (id) on delete set null;

-- At most one live copy of an activity per person; deleting the copy frees it.
create unique index activities_one_copy_per_owner on public.activities (owner_id, copied_from)
  where copied_from is not null and deleted_at is null;

-- copied_from is set only by copy_activity, so nobody can claim an activity
-- was copied from one they never saw. It isn't in the column update grants,
-- so this guards inserts.
create function public.guard_copied_from() returns trigger
language plpgsql set search_path = '' as $$
begin
  if new.copied_from is not null
     and coalesce(current_setting('easyplan.copying', true), '') <> new.copied_from::text then
    raise exception 'copies are made with copy_activity' using errcode = '42501';
  end if;
  return new;
end $$;

revoke execute on function public.guard_copied_from() from public, anon, authenticated;

create trigger activities_guard_copied_from before insert on public.activities
  for each row execute function public.guard_copied_from();

-- Copies an activity the caller can see but doesn't own into their own
-- activities and returns the copy's id. The copy's label is the type the
-- activity is filed under in p_group (or, without it, in the caller's group
-- where it was shared earliest): an existing label with that name (any case)
-- or a new one.
create function public.copy_activity(p_activity uuid, p_group uuid default null) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  v_me uuid := auth.uid();
  v_src public.activities;
  v_type text;
  v_label uuid;
  v_id uuid;
begin
  if v_me is null then
    raise exception 'sign in first' using errcode = '42501';
  end if;

  select * into v_src from public.activities where id = p_activity;
  if v_src.id is null or not public.can_access_activity(p_activity) then
    raise exception 'activity not found' using errcode = 'P0002';
  end if;
  if v_src.owner_id = v_me then
    raise exception 'this activity is already yours';
  end if;
  if exists (select 1 from public.activities
              where owner_id = v_me and copied_from = p_activity and deleted_at is null) then
    raise exception 'you already saved a copy of this activity';
  end if;

  select t.name into v_type
    from public.group_activities ga
    join public.activity_types t on t.id = ga.type_id
   where ga.activity_id = p_activity
     and public.is_group_member(ga.group_id)
     and (p_group is null or ga.group_id = p_group)
   order by ga.added_at, ga.group_id
   limit 1;

  if v_type is not null then
    select id into v_label from public.personal_types
     where owner_id = v_me and lower(trim(name)) = lower(trim(v_type));
    if v_label is null then
      insert into public.personal_types (owner_id, name) values (v_me, trim(v_type)) returning id into v_label;
    end if;
  end if;

  perform set_config('easyplan.copying', p_activity::text, true);
  insert into public.activities
    (owner_id, name, description, location, place_id, price_min, price_max, currency, url,
     personal_type_id, copied_from, updated_by)
  values
    (v_me, v_src.name, v_src.description, v_src.location, v_src.place_id, v_src.price_min, v_src.price_max,
     v_src.currency, v_src.url, v_label, p_activity, v_me)
  returning id into v_id;
  perform set_config('easyplan.copying', '', true);

  return v_id;
end $$;

revoke execute on function public.copy_activity(uuid, uuid) from public, anon;
grant execute on function public.copy_activity(uuid, uuid) to authenticated;

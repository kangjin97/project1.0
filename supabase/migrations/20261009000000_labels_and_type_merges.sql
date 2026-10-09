-- Personal activity labels, and per-group type merging.
--
-- An owner labels their activity (e.g. "yummy"). When it's shared into a group,
-- the label decides its group type: a merge rule for that name wins, otherwise
-- the group type with the same name is used (created if missing). Changing or
-- renaming the label re-files the activity in every group it's in.

------------------------------------------------------------------------------
-- Tables
------------------------------------------------------------------------------

create table public.personal_types (
  id         uuid primary key default gen_random_uuid(),
  owner_id   uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  name       text not null check (length(trim(name)) between 1 and 40),
  created_at timestamptz not null default now(),
  unique (id, owner_id)
);
create unique index personal_types_name_per_owner on public.personal_types (owner_id, lower(trim(name)));

-- The composite FK keeps the label owned by the activity's owner.
alter table public.activities add column personal_type_id uuid;
alter table public.activities
  add constraint activities_personal_type_fk foreign key (personal_type_id, owner_id)
  references public.personal_types (id, owner_id) on delete set null (personal_type_id);
create index activities_personal_type_idx on public.activities (personal_type_id);

-- The label the activity carried into the group (null when a type was picked by hand).
alter table public.group_activities add column source_type_name text;

-- "Activities labelled <source_name> go into <target type>" within one group.
create table public.type_merges (
  id             uuid primary key default gen_random_uuid(),
  group_id       uuid not null references public.groups (id) on delete cascade,
  source_name    text not null check (length(trim(source_name)) between 1 and 40),
  target_type_id uuid not null,
  created_by     uuid not null default auth.uid() references public.profiles (id),
  created_at     timestamptz not null default now(),
  foreign key (target_type_id, group_id) references public.activity_types (id, group_id) on delete cascade
);
create unique index type_merges_source_per_group on public.type_merges (group_id, lower(trim(source_name)));

------------------------------------------------------------------------------
-- Type resolution
------------------------------------------------------------------------------

-- The group type an activity labelled p_name belongs in; creates it if needed.
create function public.resolve_group_type(p_group uuid, p_name text) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  v uuid;
  n text := trim(p_name);
begin
  select target_type_id into v from public.type_merges
   where group_id = p_group and lower(trim(source_name)) = lower(n);
  if found then
    return v;
  end if;

  select id into v from public.activity_types where group_id = p_group and lower(trim(name)) = lower(n);
  if found then
    return v;
  end if;

  insert into public.activity_types (group_id, name) values (p_group, n) returning id into v;
  return v;
end $$;

-- What resolve_group_type would pick, without creating anything (for the share sheet).
create function public.preview_group_type(p_group uuid, p_name text)
returns table (type_id uuid, type_name text, merged boolean, is_new boolean)
language plpgsql stable security definer set search_path = '' as $$
declare
  n text := trim(p_name);
begin
  if not public.is_group_member(p_group) then
    raise exception 'not a member of this group';
  end if;

  return query
    select t.id, t.name, true, false
    from public.type_merges m join public.activity_types t on t.id = m.target_type_id
    where m.group_id = p_group and lower(trim(m.source_name)) = lower(n);
  if found then
    return;
  end if;

  return query
    select t.id, t.name, false, false from public.activity_types t
    where t.group_id = p_group and lower(trim(t.name)) = lower(n);
  if found then
    return;
  end if;

  return query select null::uuid, n, false, true;
end $$;

------------------------------------------------------------------------------
-- Triggers
------------------------------------------------------------------------------

-- Sharing: record the owner's label and, when no type was picked, file by label.
create function public.group_activity_defaults() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_name text;
begin
  select pt.name into v_name
  from public.activities a join public.personal_types pt on pt.id = a.personal_type_id
  where a.id = new.activity_id;

  new.source_type_name := case when new.type_id is null then v_name end;
  if new.type_id is null then
    if v_name is null then
      raise exception 'choose a type for this group';
    end if;
    new.type_id := public.resolve_group_type(new.group_id, v_name);
  end if;
  return new;
end $$;

create trigger group_activities_defaults before insert on public.group_activities
  for each row execute function public.group_activity_defaults();

-- Only the owner sets an activity's label.
create function public.guard_personal_type() returns trigger
language plpgsql as $$
begin
  if new.personal_type_id is distinct from old.personal_type_id
     and auth.uid() is not null and auth.uid() <> old.owner_id then
    raise exception 'only the owner can change this activity''s label' using errcode = '42501';
  end if;
  return new;
end $$;

create trigger activities_guard_personal_type before update on public.activities
  for each row execute function public.guard_personal_type();

-- Re-file an activity in every group when its owner changes its label.
create function public.refile_activity() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_name text;
begin
  if new.personal_type_id is not distinct from old.personal_type_id then
    return new;
  end if;

  if new.personal_type_id is null then
    -- Label removed: keep the group types as they are.
    update public.group_activities set source_type_name = null where activity_id = new.id;
    return new;
  end if;

  select name into v_name from public.personal_types where id = new.personal_type_id;
  update public.group_activities ga
     set source_type_name = v_name, type_id = public.resolve_group_type(ga.group_id, v_name)
   where ga.activity_id = new.id;
  return new;
end $$;

create trigger activities_refile after update of personal_type_id on public.activities
  for each row execute function public.refile_activity();

-- Renaming a label re-files everything that carries it.
create function public.refile_renamed_label() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if lower(trim(new.name)) = lower(trim(old.name)) then
    return new;
  end if;
  update public.group_activities ga
     set source_type_name = new.name, type_id = public.resolve_group_type(ga.group_id, new.name)
    from public.activities a
   where a.id = ga.activity_id and a.personal_type_id = new.id;
  return new;
end $$;

create trigger personal_types_refile after update of name on public.personal_types
  for each row execute function public.refile_renamed_label();

create trigger log_type_merges after insert or delete on public.type_merges
  for each row execute function public.log_change('type_merge', 'id');

------------------------------------------------------------------------------
-- RPCs
------------------------------------------------------------------------------

-- Merges source types into a target (an existing type, or a new name).
-- Their activities move now, and future activities labelled with any source
-- name are filed under the target.
create function public.merge_types(
  p_group uuid, p_source_type_ids uuid[], p_target_type_id uuid default null, p_target_name text default null
) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  v_target public.activity_types;
  s        public.activity_types;
begin
  if not public.is_group_member(p_group) then
    raise exception 'not a member of this group';
  end if;

  if p_target_type_id is not null then
    select * into v_target from public.activity_types where id = p_target_type_id and group_id = p_group;
    if not found then
      raise exception 'target type not found';
    end if;
  elsif nullif(trim(p_target_name), '') is not null then
    select * into v_target from public.activity_types
     where group_id = p_group and lower(trim(name)) = lower(trim(p_target_name));
    if not found then
      insert into public.activity_types (group_id, name) values (p_group, trim(p_target_name))
      returning * into v_target;
    end if;
  else
    raise exception 'choose what to merge them into';
  end if;

  if not exists (select 1 from unnest(p_source_type_ids) u where u <> v_target.id) then
    raise exception 'choose at least one type to merge';
  end if;

  -- The target's own name must not be redirected elsewhere.
  delete from public.type_merges
   where group_id = p_group and lower(trim(source_name)) = lower(trim(v_target.name));

  for s in select * from public.activity_types
            where group_id = p_group and id = any (p_source_type_ids) and id <> v_target.id loop
    insert into public.type_merges (group_id, source_name, target_type_id)
    values (p_group, trim(s.name), v_target.id)
    on conflict (group_id, lower(trim(source_name))) do update set target_type_id = excluded.target_type_id;

    update public.type_merges set target_type_id = v_target.id
     where group_id = p_group and target_type_id = s.id;
    update public.group_activities set type_id = v_target.id
     where group_id = p_group and type_id = s.id;
    delete from public.activity_types where id = s.id;
  end loop;

  return v_target.id;
end $$;

-- Undoes one merge rule. Activities that came in with that label go back to a
-- type of that name.
create function public.remove_type_merge(p_merge uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare
  r public.type_merges;
begin
  select * into r from public.type_merges where id = p_merge;
  if not found or not public.is_group_member(r.group_id) then
    raise exception 'merge not found';
  end if;

  delete from public.type_merges where id = r.id;
  update public.group_activities ga
     set type_id = public.resolve_group_type(ga.group_id, ga.source_type_name)
   where ga.group_id = r.group_id
     and ga.type_id = r.target_type_id
     and lower(trim(ga.source_type_name)) = lower(trim(r.source_name));
end $$;

------------------------------------------------------------------------------
-- Access
------------------------------------------------------------------------------

alter table public.personal_types enable row level security;
alter table public.type_merges enable row level security;

create policy personal_types_all on public.personal_types for all to authenticated
  using (owner_id = auth.uid()) with check (owner_id = auth.uid());

create policy type_merges_select on public.type_merges for select to authenticated
  using (public.is_group_member(group_id));

revoke update on public.personal_types from anon, authenticated;
grant update (name) on public.personal_types to authenticated;
revoke insert, update, delete on public.type_merges from anon, authenticated;
grant update (personal_type_id) on public.activities to authenticated;

revoke execute on function
  public.resolve_group_type(uuid, text),
  public.group_activity_defaults(),
  public.guard_personal_type(),
  public.refile_activity(),
  public.refile_renamed_label()
  from public, anon, authenticated;
revoke execute on function
  public.preview_group_type(uuid, text),
  public.merge_types(uuid, uuid[], uuid, text),
  public.remove_type_merge(uuid)
  from public, anon;
grant execute on function
  public.preview_group_type(uuid, text),
  public.merge_types(uuid, uuid[], uuid, text),
  public.remove_type_merge(uuid)
  to authenticated;

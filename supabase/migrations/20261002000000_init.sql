-- Group Planner: initial schema
-- See SPEC.md for the product rules this implements.

------------------------------------------------------------------------------
-- Profiles
------------------------------------------------------------------------------

create table public.profiles (
  id           uuid primary key references auth.users (id) on delete cascade,
  username     text not null unique check (username ~ '^[a-z0-9_]{3,30}$'),
  display_name text,
  avatar_path  text,
  timezone     text not null default 'UTC',
  created_at   timestamptz not null default now()
);

-- Create a profile for every new auth user. The app passes `username` (and
-- optionally `display_name`) in the sign-up metadata.
create function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id, username, display_name)
  values (
    new.id,
    lower(coalesce(new.raw_user_meta_data ->> 'username',
                   'user_' || substr(replace(new.id::text, '-', ''), 1, 12))),
    new.raw_user_meta_data ->> 'display_name'
  );
  return new;
end $$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Callable before sign-up, so it must work for anon.
create function public.username_available(p_username text) returns boolean
language sql stable security definer set search_path = '' as $$
  select not exists (select 1 from public.profiles where username = lower(trim(p_username)));
$$;

-- Emails live only in auth.users. Exact-match lookup so members can be invited
-- by email without exposing everyone's address.
create function public.find_user_by_email(p_email text) returns setof public.profiles
language sql stable security definer set search_path = '' as $$
  select p.*
  from public.profiles p
  join auth.users u on u.id = p.id
  where auth.uid() is not null
    and lower(u.email) = lower(trim(p_email));
$$;

------------------------------------------------------------------------------
-- Groups & membership
------------------------------------------------------------------------------

create table public.groups (
  id         uuid primary key default gen_random_uuid(),
  name       text not null check (length(trim(name)) between 1 and 80),
  created_by uuid not null default auth.uid() references public.profiles (id),
  created_at timestamptz not null default now()
);

create table public.group_members (
  group_id  uuid not null references public.groups (id) on delete cascade,
  user_id   uuid not null references public.profiles (id) on delete cascade,
  role      text not null default 'member' check (role in ('owner', 'member')),
  joined_at timestamptz not null default now(),
  primary key (group_id, user_id)
);
create index group_members_user_idx on public.group_members (user_id);

create table public.group_invite_links (
  id         uuid primary key default gen_random_uuid(),
  group_id   uuid not null references public.groups (id) on delete cascade,
  token      text not null unique
             default replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', ''),
  created_by uuid not null default auth.uid() references public.profiles (id),
  expires_at timestamptz,
  max_uses   int check (max_uses > 0),
  use_count  int not null default 0,
  revoked_at timestamptz,
  created_at timestamptz not null default now()
);

create table public.group_invitations (
  id           uuid primary key default gen_random_uuid(),
  group_id     uuid not null references public.groups (id) on delete cascade,
  invitee_id   uuid not null references public.profiles (id) on delete cascade,
  invited_by   uuid not null default auth.uid() references public.profiles (id),
  status       text not null default 'pending' check (status in ('pending', 'accepted', 'declined')),
  created_at   timestamptz not null default now(),
  responded_at timestamptz
);
create unique index group_invitations_one_pending
  on public.group_invitations (group_id, invitee_id) where status = 'pending';

------------------------------------------------------------------------------
-- Activities
------------------------------------------------------------------------------

create table public.activities (
  id          uuid primary key default gen_random_uuid(),
  owner_id    uuid not null default auth.uid() references public.profiles (id),
  name        text not null check (length(trim(name)) between 1 and 120),
  description text,
  location    text,
  price_min   numeric(12, 2) check (price_min >= 0),
  price_max   numeric(12, 2) check (price_max >= 0),
  currency    char(3) not null default 'SGD',
  url         text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  updated_by  uuid default auth.uid() references public.profiles (id),
  deleted_at  timestamptz,
  check (price_min is null or price_max is null or price_max >= price_min)
);
create index activities_owner_idx on public.activities (owner_id) where deleted_at is null;

create table public.activity_photos (
  id           uuid primary key default gen_random_uuid(),
  activity_id  uuid not null references public.activities (id) on delete cascade,
  storage_path text not null unique,
  position     int not null default 0,
  uploaded_by  uuid not null default auth.uid() references public.profiles (id),
  created_at   timestamptz not null default now()
);
create index activity_photos_activity_idx on public.activity_photos (activity_id);

create table public.activity_types (
  id         uuid primary key default gen_random_uuid(),
  group_id   uuid not null references public.groups (id) on delete cascade,
  name       text not null check (length(trim(name)) between 1 and 40),
  created_at timestamptz not null default now(),
  unique (id, group_id)
);
create unique index activity_types_name_per_group on public.activity_types (group_id, lower(name));

-- An activity shared into a group. The type lives here so each group labels it
-- independently; the composite FK keeps the type inside the same group.
create table public.group_activities (
  group_id    uuid not null references public.groups (id) on delete cascade,
  activity_id uuid not null references public.activities (id) on delete cascade,
  type_id     uuid not null,
  added_by    uuid not null default auth.uid() references public.profiles (id),
  added_at    timestamptz not null default now(),
  primary key (group_id, activity_id),
  foreign key (type_id, group_id) references public.activity_types (id, group_id)
);
create index group_activities_activity_idx on public.group_activities (activity_id);

------------------------------------------------------------------------------
-- Schedules
------------------------------------------------------------------------------

-- An entry with activity_id null is an event (placeholder).
create table public.schedule_entries (
  id          uuid primary key default gen_random_uuid(),
  group_id    uuid not null references public.groups (id) on delete cascade,
  activity_id uuid,
  title       text check (title is null or length(trim(title)) between 1 and 120),
  all_day     boolean not null default false,
  date        date,
  start_at    timestamptz,
  end_at      timestamptz,
  created_by  uuid not null default auth.uid() references public.profiles (id),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  updated_by  uuid default auth.uid() references public.profiles (id),
  foreign key (group_id, activity_id) references public.group_activities (group_id, activity_id),
  check (activity_id is not null or title is not null),
  check (
    -- all-day on a date
    (all_day and date is not null and start_at is null and end_at is null)
    -- timed
    or (not all_day and date is null and start_at is not null and end_at is not null and end_at > start_at)
    -- unscheduled: events only
    or (not all_day and date is null and start_at is null and end_at is null and activity_id is null)
  )
);
create index schedule_entries_group_idx on public.schedule_entries (group_id);
create index schedule_entries_activity_idx on public.schedule_entries (activity_id);

create table public.schedule_participants (
  entry_id uuid not null references public.schedule_entries (id) on delete cascade,
  user_id  uuid not null references public.profiles (id) on delete cascade,
  status   text not null default 'added' check (status in ('added', 'clash')),
  added_by uuid not null default auth.uid() references public.profiles (id),
  added_at timestamptz not null default now(),
  primary key (entry_id, user_id)
);
create index schedule_participants_user_idx on public.schedule_participants (user_id);

------------------------------------------------------------------------------
-- Change log & notifications
------------------------------------------------------------------------------

-- No foreign keys: history must survive deletes.
create table public.change_log (
  id          bigint generated always as identity primary key,
  actor_id    uuid,
  group_id    uuid,
  entity_type text not null,
  entity_id   uuid not null,
  action      text not null,
  before      jsonb,
  after       jsonb,
  created_at  timestamptz not null default now()
);
create index change_log_group_idx on public.change_log (group_id, created_at desc);
create index change_log_entity_idx on public.change_log (entity_type, entity_id, created_at desc);

create table public.notifications (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references public.profiles (id) on delete cascade,
  kind       text not null,
  payload    jsonb not null default '{}',
  read_at    timestamptz,
  created_at timestamptz not null default now()
);
create index notifications_user_idx on public.notifications (user_id, created_at desc);

------------------------------------------------------------------------------
-- Access helpers (security definer so RLS policies don't recurse)
------------------------------------------------------------------------------

create function public.is_group_member(p_group uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.group_members
                 where group_id = p_group and user_id = auth.uid());
$$;

create function public.is_group_owner(p_group uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.group_members
                 where group_id = p_group and user_id = auth.uid() and role = 'owner');
$$;

create function public.shares_group_with(p_user uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.group_members a
                 join public.group_members b on b.group_id = a.group_id
                 where a.user_id = auth.uid() and b.user_id = p_user);
$$;

create function public.is_activity_shared_with_me(p_activity uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.group_activities ga
                 join public.group_members gm on gm.group_id = ga.group_id
                 where ga.activity_id = p_activity and gm.user_id = auth.uid());
$$;

create function public.can_access_activity(p_activity uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.activities a
                 where a.id = p_activity and a.deleted_at is null
                   and (a.owner_id = auth.uid() or public.is_activity_shared_with_me(a.id)));
$$;

create function public.entry_group(p_entry uuid) returns uuid
language sql stable security definer set search_path = '' as $$
  select group_id from public.schedule_entries where id = p_entry;
$$;

create function public.is_entry_participant(p_entry uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.schedule_participants
                 where entry_id = p_entry and user_id = auth.uid());
$$;

create function public.try_uuid(p text) returns uuid
language plpgsql immutable as $$
begin
  return p::uuid;
exception when others then
  return null;
end $$;

------------------------------------------------------------------------------
-- Triggers
------------------------------------------------------------------------------

create function public.touch_updated() returns trigger
language plpgsql as $$
begin
  new.updated_at := now();
  new.updated_by := auth.uid();
  return new;
end $$;

create trigger activities_touch before update on public.activities
  for each row execute function public.touch_updated();
create trigger schedule_entries_touch before update on public.schedule_entries
  for each row execute function public.touch_updated();

-- New group: creator becomes owner, and the group gets starter types.
create function public.handle_new_group() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.group_members (group_id, user_id, role) values (new.id, new.created_by, 'owner');
  insert into public.activity_types (group_id, name)
  select new.id, n from unnest(array['Food', 'Outdoors', 'Entertainment', 'Other']) n;
  return new;
end $$;

create trigger on_group_created after insert on public.groups
  for each row execute function public.handle_new_group();

-- When an activity leaves a group (unshared, or deleted by its owner), its
-- schedule entries in that group turn back into events so plans aren't lost.
create function public.revert_entries_to_events() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  update public.schedule_entries se
     set title = coalesce(se.title, a.name), activity_id = null
    from public.activities a
   where a.id = old.activity_id
     and se.group_id = old.group_id
     and se.activity_id = old.activity_id;
  return old;
end $$;

create trigger group_activities_revert before delete on public.group_activities
  for each row execute function public.revert_entries_to_events();

create function public.notify_invitee() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.notifications (user_id, kind, payload)
  values (new.invitee_id, 'group_invitation',
          jsonb_build_object('invitation_id', new.id, 'group_id', new.group_id, 'invited_by', new.invited_by));
  return new;
end $$;

create trigger on_invitation_created after insert on public.group_invitations
  for each row execute function public.notify_invitee();

-- Generic change log. tg_argv[0] = entity type, tg_argv[1] = column holding the entity id.
create function public.log_change() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_old    jsonb := case when tg_op in ('UPDATE', 'DELETE') then to_jsonb(old) end;
  v_new    jsonb := case when tg_op in ('INSERT', 'UPDATE') then to_jsonb(new) end;
  v_before jsonb;
  v_after  jsonb;
  v_action text;
  v_entity uuid;
  v_group  uuid;
  k        text;
begin
  if tg_op = 'UPDATE' then
    v_before := '{}';
    v_after := '{}';
    for k in select jsonb_object_keys(v_new) loop
      continue when k in ('updated_at', 'updated_by');
      if v_new -> k is distinct from v_old -> k then
        v_before := v_before || jsonb_build_object(k, v_old -> k);
        v_after := v_after || jsonb_build_object(k, v_new -> k);
      end if;
    end loop;
    if v_after = '{}' then
      return new;
    end if;

    v_action := 'updated';
    if tg_table_name = 'activities' and v_after ? 'deleted_at' and v_after ->> 'deleted_at' is not null then
      v_action := 'deleted';
    elsif tg_table_name = 'group_activities' and v_after ? 'type_id' then
      v_action := 'type_changed';
    elsif tg_table_name = 'schedule_entries' and v_after ? 'activity_id' then
      v_action := case
        when v_old ->> 'activity_id' is null then 'event_replaced'
        when v_new ->> 'activity_id' is null then 'reverted_to_event'
        else 'activity_swapped' end;
    end if;
  else
    v_action := case tg_op when 'INSERT' then 'created' else 'deleted' end;
    v_before := v_old;
    v_after := v_new;
  end if;

  v_entity := coalesce(v_new ->> tg_argv[1], v_old ->> tg_argv[1])::uuid;
  v_group := coalesce(v_new ->> 'group_id', v_old ->> 'group_id')::uuid;
  if v_group is null and tg_table_name = 'schedule_participants' then
    v_group := public.entry_group(v_entity);
  end if;

  insert into public.change_log (actor_id, group_id, entity_type, entity_id, action, before, after)
  values (auth.uid(), v_group, tg_argv[0], v_entity, v_action, v_before, v_after);

  return coalesce(new, old);
end $$;

create trigger log_activities after insert or update or delete on public.activities
  for each row execute function public.log_change('activity', 'id');
create trigger log_activity_photos after insert or delete on public.activity_photos
  for each row execute function public.log_change('activity_photo', 'activity_id');
create trigger log_activity_types after insert or update or delete on public.activity_types
  for each row execute function public.log_change('activity_type', 'id');
create trigger log_group_activities after insert or update or delete on public.group_activities
  for each row execute function public.log_change('group_activity', 'activity_id');
create trigger log_schedule_entries after insert or update or delete on public.schedule_entries
  for each row execute function public.log_change('schedule_entry', 'id');
create trigger log_schedule_participants after insert or update or delete on public.schedule_participants
  for each row execute function public.log_change('schedule_participant', 'entry_id');
create trigger log_group_members after insert or delete on public.group_members
  for each row execute function public.log_change('group_member', 'user_id');

------------------------------------------------------------------------------
-- Clash detection
------------------------------------------------------------------------------

-- The time range an entry occupies. All-day entries cover the whole local day
-- in the given time zone; unscheduled events occupy nothing (null).
create function public.entry_range(
  p_all_day boolean, p_date date, p_start timestamptz, p_end timestamptz, p_tz text
) returns tstzrange
language sql stable as $$
  select case
    when p_all_day then tstzrange(p_date::timestamp at time zone p_tz,
                                  (p_date + 1)::timestamp at time zone p_tz, '[)')
    when p_start is not null then tstzrange(p_start, p_end, '[)')
  end;
$$;

-- Existing entries that overlap the given time for each user. Titles of entries
-- in groups the caller isn't in are shown as "Busy".
create function public.find_clashes(
  p_user_ids uuid[], p_all_day boolean, p_date date,
  p_start_at timestamptz, p_end_at timestamptz, p_exclude_entry uuid default null
) returns table (
  user_id uuid, username text, entry_id uuid, title text,
  all_day boolean, entry_date date, start_at timestamptz, end_at timestamptz
)
language sql stable security definer set search_path = '' as $$
  select p.id, p.username, se.id,
         case when public.is_group_member(se.group_id) then coalesce(a.name, se.title) else 'Busy' end,
         se.all_day, se.date, se.start_at, se.end_at
  from unnest(p_user_ids) as u (id)
  join public.profiles p on p.id = u.id
  join public.schedule_participants sp on sp.user_id = p.id
  join public.schedule_entries se on se.id = sp.entry_id
  left join public.activities a on a.id = se.activity_id
  where auth.uid() is not null
    and (p.id = auth.uid() or public.shares_group_with(p.id))
    and (p_exclude_entry is null or se.id <> p_exclude_entry)
    and public.entry_range(se.all_day, se.date, se.start_at, se.end_at, p.timezone)
        && public.entry_range(p_all_day, p_date, p_start_at, p_end_at, p.timezone)
  order by p.username, coalesce(se.start_at, se.date::timestamptz);
$$;

-- Marks participants clash/added for an entry's current time, notifies members
-- who newly clash or were just added, and logs overridden clashes.
create function public.apply_participants(
  p_entry uuid, p_new_user_ids uuid[], p_clashes jsonb
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

  if cardinality(v_clashing) > 0 then
    insert into public.change_log (actor_id, group_id, entity_type, entity_id, action, after)
    values (auth.uid(), v_entry.group_id, 'schedule_entry', p_entry, 'clash_override',
            jsonb_build_object('clashes', p_clashes));
  end if;
end $$;

------------------------------------------------------------------------------
-- RPCs
------------------------------------------------------------------------------

create function public.join_group_via_link(p_token text) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  l public.group_invite_links;
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;

  select * into l from public.group_invite_links where token = p_token for update;
  if not found or l.revoked_at is not null
     or (l.expires_at is not null and l.expires_at < now())
     or (l.max_uses is not null and l.use_count >= l.max_uses) then
    raise exception 'invite link is invalid or expired';
  end if;

  if not exists (select 1 from public.group_members where group_id = l.group_id and user_id = auth.uid()) then
    insert into public.group_members (group_id, user_id) values (l.group_id, auth.uid());
    update public.group_invite_links set use_count = use_count + 1 where id = l.id;
  end if;
  return l.group_id;
end $$;

-- Lets the join screen show the group's name before joining.
create function public.preview_invite_link(p_token text)
returns table (group_id uuid, group_name text, member_count bigint)
language sql stable security definer set search_path = '' as $$
  select g.id, g.name, (select count(*) from public.group_members m where m.group_id = g.id)
  from public.group_invite_links l
  join public.groups g on g.id = l.group_id
  where l.token = p_token and auth.uid() is not null
    and l.revoked_at is null
    and (l.expires_at is null or l.expires_at >= now())
    and (l.max_uses is null or l.use_count < l.max_uses);
$$;

create function public.respond_to_invitation(p_invitation uuid, p_accept boolean) returns void
language plpgsql security definer set search_path = '' as $$
declare
  inv public.group_invitations;
begin
  select * into inv from public.group_invitations
   where id = p_invitation and invitee_id = auth.uid() and status = 'pending'
   for update;
  if not found then
    raise exception 'invitation not found';
  end if;

  update public.group_invitations
     set status = case when p_accept then 'accepted' else 'declined' end, responded_at = now()
   where id = inv.id;

  if p_accept then
    insert into public.group_members (group_id, user_id) values (inv.group_id, auth.uid())
    on conflict do nothing;
  end if;
end $$;

-- Owner-only soft delete. Entries using the activity revert to events via the
-- group_activities delete trigger.
create function public.delete_activity(p_activity uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not exists (select 1 from public.activities
                 where id = p_activity and owner_id = auth.uid() and deleted_at is null) then
    raise exception 'only the owner can delete this activity';
  end if;
  delete from public.group_activities where activity_id = p_activity;
  update public.activities set deleted_at = now() where id = p_activity;
end $$;

-- Creates an activity entry or an event in a group's schedule.
-- Returns {status: 'clash', clashes: [...]} without saving when members clash
-- and p_force is false; otherwise {status: 'created', entry_id, clashes}.
create function public.create_schedule_entry(
  p_group_id uuid,
  p_activity_id uuid,
  p_title text,
  p_all_day boolean,
  p_date date,
  p_start_at timestamptz,
  p_end_at timestamptz,
  p_participant_ids uuid[],
  p_force boolean default false
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_people  uuid[];
  v_clashes jsonb;
  v_entry   uuid;
begin
  if not public.is_group_member(p_group_id) then
    raise exception 'not a member of this group';
  end if;

  v_people := array(select distinct u from unnest(coalesce(p_participant_ids, array[auth.uid()])) u where u is not null);
  if exists (select 1 from unnest(v_people) u
             where not exists (select 1 from public.group_members gm
                               where gm.group_id = p_group_id and gm.user_id = u)) then
    raise exception 'all participants must be members of the group';
  end if;

  select coalesce(jsonb_agg(to_jsonb(c)), '[]') into v_clashes
  from public.find_clashes(v_people, p_all_day, p_date, p_start_at, p_end_at) c;

  if jsonb_array_length(v_clashes) > 0 and not p_force then
    return jsonb_build_object('status', 'clash', 'clashes', v_clashes);
  end if;

  insert into public.schedule_entries (group_id, activity_id, title, all_day, date, start_at, end_at)
  values (p_group_id, p_activity_id, nullif(trim(p_title), ''), coalesce(p_all_day, false),
          p_date, p_start_at, p_end_at)
  returning id into v_entry;

  perform public.apply_participants(v_entry, v_people, v_clashes);
  return jsonb_build_object('status', 'created', 'entry_id', v_entry, 'clashes', v_clashes);
end $$;

-- Moves an entry to a new time, re-checking every participant.
create function public.reschedule_entry(
  p_entry uuid,
  p_all_day boolean,
  p_date date,
  p_start_at timestamptz,
  p_end_at timestamptz,
  p_force boolean default false
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_people  uuid[];
  v_clashes jsonb;
begin
  if not public.is_group_member(public.entry_group(p_entry)) then
    raise exception 'not a member of this group';
  end if;

  v_people := array(select user_id from public.schedule_participants where entry_id = p_entry);
  select coalesce(jsonb_agg(to_jsonb(c)), '[]') into v_clashes
  from public.find_clashes(v_people, p_all_day, p_date, p_start_at, p_end_at, p_entry) c;

  if jsonb_array_length(v_clashes) > 0 and not p_force then
    return jsonb_build_object('status', 'clash', 'clashes', v_clashes);
  end if;

  update public.schedule_entries
     set all_day = coalesce(p_all_day, false), date = p_date, start_at = p_start_at, end_at = p_end_at
   where id = p_entry;

  perform public.apply_participants(p_entry, '{}', v_clashes);
  return jsonb_build_object('status', 'updated', 'entry_id', p_entry, 'clashes', v_clashes);
end $$;

-- Adds group members to an existing entry, checking only the new people.
create function public.add_entry_participants(
  p_entry uuid, p_user_ids uuid[], p_force boolean default false
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_entry   public.schedule_entries;
  v_people  uuid[];
  v_clashes jsonb;
  v_all     jsonb;
begin
  select * into v_entry from public.schedule_entries where id = p_entry;
  if not found or not public.is_group_member(v_entry.group_id) then
    raise exception 'not a member of this group';
  end if;

  v_people := array(select distinct u from unnest(p_user_ids) u
                    where u is not null
                      and not exists (select 1 from public.schedule_participants
                                      where entry_id = p_entry and user_id = u));
  if exists (select 1 from unnest(v_people) u
             where not exists (select 1 from public.group_members gm
                               where gm.group_id = v_entry.group_id and gm.user_id = u)) then
    raise exception 'all participants must be members of the group';
  end if;

  select coalesce(jsonb_agg(to_jsonb(c)), '[]') into v_clashes
  from public.find_clashes(v_people, v_entry.all_day, v_entry.date, v_entry.start_at, v_entry.end_at, p_entry) c;

  if jsonb_array_length(v_clashes) > 0 and not p_force then
    return jsonb_build_object('status', 'clash', 'clashes', v_clashes);
  end if;

  -- Keep existing participants' clash status intact.
  select coalesce(jsonb_agg(to_jsonb(c)), '[]') into v_all
  from public.find_clashes(
    array(select user_id from public.schedule_participants where entry_id = p_entry) || v_people,
    v_entry.all_day, v_entry.date, v_entry.start_at, v_entry.end_at, p_entry) c;

  perform public.apply_participants(p_entry, v_people, v_all);
  return jsonb_build_object('status', 'updated', 'entry_id', p_entry, 'clashes', v_clashes);
end $$;

------------------------------------------------------------------------------
-- Row Level Security
------------------------------------------------------------------------------

alter table public.profiles              enable row level security;
alter table public.groups                enable row level security;
alter table public.group_members         enable row level security;
alter table public.group_invite_links    enable row level security;
alter table public.group_invitations     enable row level security;
alter table public.activities            enable row level security;
alter table public.activity_photos       enable row level security;
alter table public.activity_types        enable row level security;
alter table public.group_activities      enable row level security;
alter table public.schedule_entries      enable row level security;
alter table public.schedule_participants enable row level security;
alter table public.change_log            enable row level security;
alter table public.notifications         enable row level security;

-- Profiles: public within the app (no emails stored here); users edit their own.
create policy profiles_select on public.profiles for select to authenticated using (true);
create policy profiles_update on public.profiles for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());

-- Groups
create policy groups_select on public.groups for select to authenticated using (
  created_by = auth.uid()
  or public.is_group_member(id)
  or exists (select 1 from public.group_invitations i
             where i.group_id = groups.id and i.invitee_id = auth.uid() and i.status = 'pending'));
create policy groups_insert on public.groups for insert to authenticated
  with check (created_by = auth.uid());
create policy groups_update on public.groups for update to authenticated
  using (public.is_group_owner(id));
create policy groups_delete on public.groups for delete to authenticated
  using (public.is_group_owner(id));

-- Members: visible to the group; leave yourself, or the owner removes you.
create policy group_members_select on public.group_members for select to authenticated
  using (public.is_group_member(group_id));
create policy group_members_delete on public.group_members for delete to authenticated
  using (user_id = auth.uid() or public.is_group_owner(group_id));

-- Invite links
create policy invite_links_select on public.group_invite_links for select to authenticated
  using (public.is_group_member(group_id));
create policy invite_links_insert on public.group_invite_links for insert to authenticated
  with check (created_by = auth.uid() and public.is_group_member(group_id));
create policy invite_links_update on public.group_invite_links for update to authenticated
  using (public.is_group_member(group_id));

-- Invitations
create policy invitations_select on public.group_invitations for select to authenticated
  using (invitee_id = auth.uid() or public.is_group_member(group_id));
create policy invitations_insert on public.group_invitations for insert to authenticated
  with check (
    invited_by = auth.uid()
    and public.is_group_member(group_id)
    and not exists (select 1 from public.group_members m
                    where m.group_id = group_invitations.group_id and m.user_id = invitee_id));

-- Activities: the owner, plus members of any group it's shared into.
create policy activities_select on public.activities for select to authenticated using (
  deleted_at is null and (owner_id = auth.uid() or public.is_activity_shared_with_me(id)));
create policy activities_insert on public.activities for insert to authenticated
  with check (owner_id = auth.uid());
create policy activities_update on public.activities for update to authenticated using (
  deleted_at is null and (owner_id = auth.uid() or public.is_activity_shared_with_me(id)));

create policy activity_photos_select on public.activity_photos for select to authenticated
  using (public.can_access_activity(activity_id));
create policy activity_photos_insert on public.activity_photos for insert to authenticated
  with check (uploaded_by = auth.uid() and public.can_access_activity(activity_id));
create policy activity_photos_update on public.activity_photos for update to authenticated
  using (public.can_access_activity(activity_id));
create policy activity_photos_delete on public.activity_photos for delete to authenticated
  using (public.can_access_activity(activity_id));

-- Activity types: any member manages their group's types.
create policy activity_types_select on public.activity_types for select to authenticated
  using (public.is_group_member(group_id));
create policy activity_types_insert on public.activity_types for insert to authenticated
  with check (public.is_group_member(group_id));
create policy activity_types_update on public.activity_types for update to authenticated
  using (public.is_group_member(group_id));
create policy activity_types_delete on public.activity_types for delete to authenticated
  using (public.is_group_member(group_id));

-- Group activities: share in, change type, or unshare — any member.
create policy group_activities_select on public.group_activities for select to authenticated
  using (public.is_group_member(group_id));
create policy group_activities_insert on public.group_activities for insert to authenticated
  with check (added_by = auth.uid() and public.is_group_member(group_id)
              and public.can_access_activity(activity_id));
create policy group_activities_update on public.group_activities for update to authenticated
  using (public.is_group_member(group_id));
create policy group_activities_delete on public.group_activities for delete to authenticated
  using (public.is_group_member(group_id));

-- Schedule entries: created through RPCs; members can swap activities and remove entries.
create policy schedule_entries_select on public.schedule_entries for select to authenticated
  using (public.is_group_member(group_id) or public.is_entry_participant(id));
create policy schedule_entries_update on public.schedule_entries for update to authenticated
  using (public.is_group_member(group_id));
create policy schedule_entries_delete on public.schedule_entries for delete to authenticated
  using (public.is_group_member(group_id));

-- Participants: added through RPCs; you can acknowledge a clash or leave.
create policy participants_select on public.schedule_participants for select to authenticated
  using (user_id = auth.uid() or public.is_group_member(public.entry_group(entry_id)));
create policy participants_update on public.schedule_participants for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid() and status = 'added');
create policy participants_delete on public.schedule_participants for delete to authenticated
  using (user_id = auth.uid());

-- Change log: read-only; written by triggers and RPCs.
create policy change_log_select on public.change_log for select to authenticated using (
  actor_id = auth.uid()
  or (group_id is not null and public.is_group_member(group_id))
  or (entity_type in ('activity', 'activity_photo') and public.can_access_activity(entity_id)));

create policy notifications_select on public.notifications for select to authenticated
  using (user_id = auth.uid());
create policy notifications_update on public.notifications for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

------------------------------------------------------------------------------
-- Column-level update grants (lock down ownership and bookkeeping columns)
------------------------------------------------------------------------------

revoke update on public.profiles, public.groups, public.group_invite_links, public.activities,
  public.activity_photos, public.activity_types, public.group_activities,
  public.schedule_entries, public.schedule_participants, public.notifications
  from anon, authenticated;
revoke insert on public.group_members, public.schedule_entries, public.schedule_participants,
  public.change_log, public.notifications
  from anon, authenticated;
revoke update, delete on public.change_log from anon, authenticated;

grant update (username, display_name, avatar_path, timezone) on public.profiles to authenticated;
grant update (name) on public.groups to authenticated;
grant update (revoked_at) on public.group_invite_links to authenticated;
grant update (name, description, location, price_min, price_max, currency, url)
  on public.activities to authenticated;
grant update (position) on public.activity_photos to authenticated;
grant update (name) on public.activity_types to authenticated;
grant update (type_id) on public.group_activities to authenticated;
grant update (activity_id, title) on public.schedule_entries to authenticated;
grant update (status) on public.schedule_participants to authenticated;
grant update (read_at) on public.notifications to authenticated;

------------------------------------------------------------------------------
-- Function privileges
------------------------------------------------------------------------------

revoke execute on all functions in schema public from public, anon;
grant execute on function public.username_available(text) to anon, authenticated;
grant execute on function
  public.find_user_by_email(text),
  public.is_group_member(uuid),
  public.is_group_owner(uuid),
  public.shares_group_with(uuid),
  public.is_activity_shared_with_me(uuid),
  public.can_access_activity(uuid),
  public.entry_group(uuid),
  public.is_entry_participant(uuid),
  public.try_uuid(text),
  public.entry_range(boolean, date, timestamptz, timestamptz, text),
  public.find_clashes(uuid[], boolean, date, timestamptz, timestamptz, uuid),
  public.join_group_via_link(text),
  public.preview_invite_link(text),
  public.respond_to_invitation(uuid, boolean),
  public.delete_activity(uuid),
  public.create_schedule_entry(uuid, uuid, text, boolean, date, timestamptz, timestamptz, uuid[], boolean),
  public.reschedule_entry(uuid, boolean, date, timestamptz, timestamptz, boolean),
  public.add_entry_participants(uuid, uuid[], boolean)
  to authenticated;
-- apply_participants is internal to the RPCs above.
revoke execute on function public.apply_participants(uuid, uuid[], jsonb) from authenticated;

------------------------------------------------------------------------------
-- Storage: activity photos at activity-photos/<activity_id>/<file>
------------------------------------------------------------------------------

insert into storage.buckets (id, name, public)
values ('activity-photos', 'activity-photos', false)
on conflict (id) do nothing;

create policy activity_photos_read on storage.objects for select to authenticated using (
  bucket_id = 'activity-photos'
  and public.can_access_activity(public.try_uuid((storage.foldername(name))[1])));
create policy activity_photos_write on storage.objects for insert to authenticated with check (
  bucket_id = 'activity-photos'
  and public.can_access_activity(public.try_uuid((storage.foldername(name))[1])));
create policy activity_photos_remove on storage.objects for delete to authenticated using (
  bucket_id = 'activity-photos'
  and public.can_access_activity(public.try_uuid((storage.foldername(name))[1])));

------------------------------------------------------------------------------
-- Realtime: live schedule and notification updates
------------------------------------------------------------------------------

alter publication supabase_realtime add table
  public.schedule_entries, public.schedule_participants, public.notifications, public.group_activities;

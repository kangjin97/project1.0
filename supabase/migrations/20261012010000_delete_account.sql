-- Account deletion (required by the App Store and Google Play) and group
-- ownership hand-over.
--
-- Deleting an account removes the auth user, which cascades to the profile.
-- Groups they owned pass to the longest-standing member (or are deleted when
-- empty); their activities are deleted (plans that used them become events);
-- "who did it" columns elsewhere become null and show as "deleted user".

------------------------------------------------------------------------------
-- "Who did it" columns: keep the row, forget the person.
------------------------------------------------------------------------------

alter table public.groups alter column created_by drop not null;
alter table public.groups drop constraint groups_created_by_fkey,
  add constraint groups_created_by_fkey foreign key (created_by) references public.profiles (id) on delete set null;

alter table public.group_invite_links alter column created_by drop not null;
alter table public.group_invite_links drop constraint group_invite_links_created_by_fkey,
  add constraint group_invite_links_created_by_fkey foreign key (created_by) references public.profiles (id) on delete set null;

alter table public.group_invitations alter column invited_by drop not null;
alter table public.group_invitations drop constraint group_invitations_invited_by_fkey,
  add constraint group_invitations_invited_by_fkey foreign key (invited_by) references public.profiles (id) on delete set null;

alter table public.activities drop constraint activities_updated_by_fkey,
  add constraint activities_updated_by_fkey foreign key (updated_by) references public.profiles (id) on delete set null;

alter table public.activity_photos alter column uploaded_by drop not null;
alter table public.activity_photos drop constraint activity_photos_uploaded_by_fkey,
  add constraint activity_photos_uploaded_by_fkey foreign key (uploaded_by) references public.profiles (id) on delete set null;

alter table public.group_activities alter column added_by drop not null;
alter table public.group_activities drop constraint group_activities_added_by_fkey,
  add constraint group_activities_added_by_fkey foreign key (added_by) references public.profiles (id) on delete set null;

alter table public.schedule_entries alter column created_by drop not null;
alter table public.schedule_entries drop constraint schedule_entries_created_by_fkey,
  add constraint schedule_entries_created_by_fkey foreign key (created_by) references public.profiles (id) on delete set null;
alter table public.schedule_entries drop constraint schedule_entries_updated_by_fkey,
  add constraint schedule_entries_updated_by_fkey foreign key (updated_by) references public.profiles (id) on delete set null;

alter table public.schedule_participants alter column added_by drop not null;
alter table public.schedule_participants drop constraint schedule_participants_added_by_fkey,
  add constraint schedule_participants_added_by_fkey foreign key (added_by) references public.profiles (id) on delete set null;

alter table public.type_merges alter column created_by drop not null;
alter table public.type_merges drop constraint type_merges_created_by_fkey,
  add constraint type_merges_created_by_fkey foreign key (created_by) references public.profiles (id) on delete set null;

------------------------------------------------------------------------------
-- Groups always keep an owner while they have members.
------------------------------------------------------------------------------

create function public.hand_over_ownership() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_next uuid;
begin
  -- Nothing to do when the whole group is being deleted.
  if not exists (select 1 from public.groups where id = old.group_id) then
    return old;
  end if;
  if exists (select 1 from public.group_members where group_id = old.group_id and role = 'owner') then
    return old;
  end if;

  select user_id into v_next from public.group_members
   where group_id = old.group_id
   order by joined_at, user_id
   limit 1;

  if v_next is null then
    delete from public.groups where id = old.group_id;
  else
    update public.group_members set role = 'owner' where group_id = old.group_id and user_id = v_next;
  end if;
  return old;
end $$;

create trigger group_members_hand_over after delete on public.group_members
  for each row execute function public.hand_over_ownership();

------------------------------------------------------------------------------
-- Delete the caller's account.
------------------------------------------------------------------------------

-- Storage files the caller should remove before deleting their account
-- (their avatar and their activities' photos), since rows in storage.objects
-- shouldn't be deleted directly.
create function public.my_storage_files()
returns table (bucket text, path text)
language sql stable security definer set search_path = '' as $$
  select 'avatars', avatar_path from public.profiles where id = auth.uid() and avatar_path is not null
  union all
  select 'activity-photos', p.storage_path
  from public.activity_photos p join public.activities a on a.id = p.activity_id
  where a.owner_id = auth.uid();
$$;

create function public.delete_my_account() returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_me uuid := auth.uid();
begin
  if v_me is null then
    raise exception 'not authenticated';
  end if;

  -- Their activities go first, so plans that used them revert to events
  -- (group_activities delete trigger) before the profile disappears.
  delete from public.activities where owner_id = v_me;

  -- Cascades: profile → memberships (ownership hand-over), participation,
  -- labels, invitations to them, notifications.
  delete from auth.users where id = v_me;
end $$;

revoke execute on function public.hand_over_ownership() from public, anon, authenticated;
revoke execute on function public.my_storage_files(), public.delete_my_account() from public, anon;
grant execute on function public.my_storage_files(), public.delete_my_account() to authenticated;

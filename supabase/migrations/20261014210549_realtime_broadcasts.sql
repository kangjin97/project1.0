-- Realtime updates (#7): triggers broadcast a "changed" message to private
-- Realtime channels, and the app re-fetches what it shows through the usual
-- RLS. The message says only which table changed, never row data, so a
-- listener learns nothing it couldn't already read.
--
-- Topics:
--   group:<group_id>  anything shown inside a group (activities, types,
--                     merges, members, plans, the group itself)
--   user:<user_id>    things about one person across groups (their
--                     notifications and invitations, plans they're in, groups
--                     they joined or left, their own activities)
--
-- Who may listen is decided by the realtime.messages policy below: members
-- for group topics, the user themselves for user topics. Nobody may send:
-- there's no insert policy, so only these triggers publish.
--
-- Broadcast rather than the supabase_realtime publication ("Postgres
-- Changes"), which doesn't apply RLS to deletes and sends every subscriber
-- the deleted row's key.

create function public.broadcast_change() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  r       jsonb := to_jsonb(coalesce(new, old));
  v_group uuid;
  topics  text[];
  t       text;
  sent    text := coalesce(current_setting('easyplan.broadcasts_sent', true), '');
  k       text;
begin
  case tg_table_name
    when 'groups' then
      topics := array['group:' || (r ->> 'id')];
    when 'group_members' then
      topics := array['group:' || (r ->> 'group_id'), 'user:' || (r ->> 'user_id')];
    when 'group_activities', 'activity_types', 'type_merges' then
      topics := array['group:' || (r ->> 'group_id')];
    when 'schedule_entries' then
      -- Participants too: someone who left the group can still be on its plans.
      topics := array['group:' || (r ->> 'group_id')]
             || array(select 'user:' || sp.user_id from public.schedule_participants sp
                      where sp.entry_id = (r ->> 'id')::uuid);
    when 'schedule_participants' then
      topics := array['user:' || (r ->> 'user_id')];
      -- Null when the plan itself is being deleted; its own trigger covers the group.
      v_group := public.entry_group((r ->> 'entry_id')::uuid);
      if v_group is not null then
        topics := topics || ('group:' || v_group);
      end if;
    when 'activities', 'activity_photos' then
      select array['user:' || a.owner_id]
             || array(select 'group:' || ga.group_id from public.group_activities ga where ga.activity_id = a.id)
        into topics
        from public.activities a
       where a.id = coalesce(r ->> 'activity_id', r ->> 'id')::uuid;
    when 'notifications' then
      topics := array['user:' || (r ->> 'user_id')];
    when 'group_invitations' then
      -- Accepted or declined on another device: the pending list changes.
      topics := array['user:' || (r ->> 'invitee_id')];
  end case;

  -- One message per topic and table per transaction is enough: listeners only
  -- see messages after commit, and they re-fetch everything for that table.
  foreach t in array coalesce(topics, '{}') loop
    k := '|' || t || '/' || tg_table_name || '|';
    continue when position(k in sent) > 0;
    sent := sent || k;
    perform realtime.send(jsonb_build_object('table', tg_table_name), 'changed', t, true);
  end loop;
  perform set_config('easyplan.broadcasts_sent', sent, true);
  return null;
end $$;

revoke execute on function public.broadcast_change() from public, anon, authenticated;

create trigger broadcast_groups after update or delete on public.groups
  for each row execute function public.broadcast_change();
create trigger broadcast_group_members after insert or update or delete on public.group_members
  for each row execute function public.broadcast_change();
create trigger broadcast_group_activities after insert or update or delete on public.group_activities
  for each row execute function public.broadcast_change();
create trigger broadcast_activities after insert or update or delete on public.activities
  for each row execute function public.broadcast_change();
create trigger broadcast_activity_photos after insert or update or delete on public.activity_photos
  for each row execute function public.broadcast_change();
create trigger broadcast_activity_types after insert or update or delete on public.activity_types
  for each row execute function public.broadcast_change();
create trigger broadcast_type_merges after insert or update or delete on public.type_merges
  for each row execute function public.broadcast_change();
create trigger broadcast_schedule_entries after insert or update or delete on public.schedule_entries
  for each row execute function public.broadcast_change();
create trigger broadcast_schedule_participants after insert or update or delete on public.schedule_participants
  for each row execute function public.broadcast_change();
create trigger broadcast_notifications after insert or update or delete on public.notifications
  for each row execute function public.broadcast_change();
create trigger broadcast_group_invitations after insert or update or delete on public.group_invitations
  for each row execute function public.broadcast_change();

-- Listening: members on their groups' topics, everyone on their own user topic.
create policy easyplan_listen on realtime.messages for select to authenticated using (
  realtime.messages.extension = 'broadcast'
  and (
    realtime.topic() = 'user:' || auth.uid()::text
    or (realtime.topic() like 'group:%'
        and public.is_group_member(public.try_uuid(substr(realtime.topic(), length('group:') + 1))))
  )
);

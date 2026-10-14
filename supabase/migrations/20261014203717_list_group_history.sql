-- list_group_history: a group's change log for its History page (#8), newest
-- first, with the names the screen needs. Log rows hold only ids and row
-- snapshots, and some of the things they name are no longer visible through
-- RLS (deleted types, removed members), so names are resolved here.
--
-- What a member sees:
--   * everything logged against the group (shares, types, merges, plans,
--     participants, members joining and leaving), from before they joined too;
--   * edits and photo changes to an activity made while it was shared in this
--     group. Edits from before it was shared stay private to the owner, and so
--     do label changes (personal_type_id), which are stripped from the snapshots.
-- Paged with p_before: pass the smallest id of the previous page.
create function public.list_group_history(
  p_group uuid, p_before bigint default null, p_limit int default 50
)
returns table (
  id              bigint,
  created_at      timestamptz,
  entity_type     text,
  entity_id       uuid,
  action          text,
  before          jsonb,
  after           jsonb,
  actor_id        uuid,
  actor_username  text,
  subject_name    text,  -- the activity, plan, type or merged label it's about
  person_username text,  -- the member or participant it's about
  from_type_name  text,
  to_type_name    text,
  event_title     text   -- a plan's own name, kept when an activity replaces the event
)
language sql stable security definer set search_path = '' as $$
  select cl.id, cl.created_at, cl.entity_type, cl.entity_id, cl.action,
         case when cl.entity_type = 'activity' then cl.before - 'personal_type_id' else cl.before end,
         case when cl.entity_type = 'activity' then cl.after - 'personal_type_id' else cl.after end,
         cl.actor_id, actor.username,
         case
           when cl.entity_type in ('activity', 'activity_photo', 'group_activity') then act.name
           when cl.entity_type in ('schedule_entry', 'schedule_participant')
             then coalesce(entry_act.name, se.title, snap_act.name, cl.before ->> 'title', cl.after ->> 'title')
           when cl.entity_type = 'activity_type' then coalesce(cl.after ->> 'name', cl.before ->> 'name')
           -- An updated rule's snapshot holds only the new target; its label is on the rule.
           when cl.entity_type = 'type_merge'
             then coalesce(cl.after ->> 'source_name', cl.before ->> 'source_name', tm.source_name)
         end,
         person.username,
         from_t.name, to_t.name,
         se.title
  from public.change_log cl
  left join public.profiles actor on actor.id = cl.actor_id
  -- Activity names only while the caller can still see the activity.
  left join public.activities act
         on cl.entity_type in ('activity', 'activity_photo', 'group_activity')
        and act.id = cl.entity_id
        and public.can_access_activity(act.id)
  left join public.schedule_entries se
         on cl.entity_type in ('schedule_entry', 'schedule_participant')
        and se.id = cl.entity_id and se.group_id = p_group
  left join public.activities entry_act on entry_act.id = se.activity_id
  -- A removed plan's activity, from the log's snapshot of the plan.
  left join public.activities snap_act
         on se.id is null
        and cl.entity_type = 'schedule_entry'
        and snap_act.id = public.try_uuid(coalesce(cl.before, cl.after) ->> 'activity_id')
        and public.can_access_activity(snap_act.id)
  left join public.type_merges tm
         on cl.entity_type = 'type_merge' and tm.id = cl.entity_id and tm.group_id = p_group
  left join public.profiles person
         on person.id = case cl.entity_type
                          when 'group_member' then cl.entity_id
                          when 'schedule_participant' then public.try_uuid(coalesce(cl.after, cl.before) ->> 'user_id')
                        end
  left join public.activity_types from_t
         on cl.entity_type = 'group_activity'
        and from_t.id = public.try_uuid(cl.before ->> 'type_id') and from_t.group_id = p_group
  left join public.activity_types to_t
         on cl.entity_type in ('group_activity', 'type_merge')
        and to_t.id = public.try_uuid(coalesce(cl.after ->> 'type_id', cl.after ->> 'target_type_id',
                                               cl.before ->> 'target_type_id'))
        and to_t.group_id = p_group
  where public.is_group_member(p_group)
    and (p_before is null or cl.id < p_before)
    and (cl.group_id = p_group
         or (cl.entity_type in ('activity', 'activity_photo')
             and exists (select 1 from public.group_activities ga
                         where ga.group_id = p_group and ga.activity_id = cl.entity_id
                           and cl.created_at >= ga.added_at)))
    -- Bookkeeping, not something a person did: an edit that only changed the
    -- owner's private label, a label being cleared from a share (its type
    -- stays), and a participant marked as clashing (the planner's
    -- clash_override row already says so).
    and not (cl.entity_type = 'activity' and cl.action = 'updated'
             and coalesce(cl.after - 'personal_type_id', '{}'::jsonb) = '{}'::jsonb)
    and not (cl.entity_type = 'group_activity' and cl.action = 'updated')
    and not (cl.entity_type = 'schedule_participant' and cl.action = 'updated'
             and cl.after ->> 'status' = 'clash')
  order by cl.id desc
  limit greatest(1, least(coalesce(p_limit, 50), 200));
$$;

revoke execute on function public.list_group_history(uuid, bigint, int) from public, anon;
grant execute on function public.list_group_history(uuid, bigint, int) to authenticated;

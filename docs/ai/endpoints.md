# Endpoints reference

Every backend call the app makes, plus the RPCs the database exposes but the app doesn't use yet. All calls go through supabase-dart; "REST" means PostgREST on `/rest/v1/<table>`. RLS applies to every call as the signed-in user.

**Conventions**
- "Who" is enforced by the database (RLS, grants or the RPC body), not by the app.
- `P0001 "<msg>"` means the RPC raises that message; the app shows it via `friendlyError`.
- Dart methods are in `app/lib/data/groups_repository.dart` (G) and `app/lib/data/activities_repository.dart` (A).

---

## Auth

| Dart | Call | Notes |
|---|---|---|
| `AuthPage._submit` (sign up) | `rpc username_available(p_username text) → bool`, then `auth.signUp(email, password, data: {username, display_name})` | Callable signed-out. Trigger creates `profiles` row; username lower-cased. Duplicate username at insert → sign-up fails. |
| `AuthPage._submit` (sign in) | `auth.signInWithPassword(email, password)` | |
| `HomeShell` / pages | `auth.signOut()` | |

## Profiles

| Dart | Call | Who | Notes |
|---|---|---|---|
| G `searchUsers(q)` (no `@`) | REST `GET profiles?select=id,username,display_name&username=ilike.<prefix>*&id=neq.<me>&limit=10` | signed in | Query stripped to `[a-z0-9_]`, `_` escaped. |
| G `searchUsers(q)` (has `@`) | `rpc find_user_by_email(p_email text) → setof profiles` | signed in | Exact, case-insensitive. |

## Groups

| Dart | Call | Who | Errors / side effects |
|---|---|---|---|
| G `myGroups()` | REST `GET group_members?select=group_id&user_id=eq.<me>` then `GET groups?select=id,name,group_members(count)&id=in.(...)&order=created_at.asc` | members | |
| G `group(id)` | REST `GET groups?select=id,name,group_members(count)&id=eq.<id>` (single) | members or pending invitee | |
| G `createGroup(name)` | REST `POST groups {name}` → `id` | signed in | Trigger: creator → owner; seeds types Food/Outdoors/Entertainment/Other. |
| G `renameGroup(id, name)` | REST `PATCH groups?id=eq {name}` | owner | 42501 otherwise. |
| G `leaveGroup(id)` | REST `DELETE group_members?group_id&user_id=<me>` | self | |
| G `members(groupId)` | REST `GET group_members?select=role,profiles(id,username,display_name)&order=joined_at.asc` | members | |
| G `removeMember(groupId, userId)` | REST `DELETE group_members?...` | owner | |

## Invites

| Dart | Call | Who | Errors / side effects |
|---|---|---|---|
| G `invite(groupId, userId)` | REST `POST group_invitations {group_id, invitee_id}` | members; invitee must not be a member | 23505 if a pending invite exists. Trigger: `group_invitation` notification. |
| G `pendingInvitations()` | REST `GET group_invitations?select=id,groups(name),inviter:profiles!group_invitations_invited_by_fkey(username)&invitee_id=eq.<me>&status=eq.pending` | invitee | |
| G `respond(id, accept)` | `rpc respond_to_invitation(p_invitation uuid, p_accept bool) → void` | invitee | P0001 "invitation not found". Accept → membership. |
| G `createInviteLink(groupId)` | REST `POST group_invite_links {group_id, expires_at: now+7d}` → `token` | members | |
| G `previewLink(token)` | `rpc preview_invite_link(p_token text) → [{group_id, group_name, member_count}]` | signed in | Empty when invalid/expired/revoked/used up. |
| G `joinViaLink(token)` | `rpc join_group_via_link(p_token text) → uuid group_id` | signed in | P0001 "invite link is invalid or expired". Idempotent for existing members. |
| — (no UI) | REST `PATCH group_invite_links {revoked_at}` | members | Revokes a link. |

## Activity types (per group)

| Dart | Call | Who | Errors |
|---|---|---|---|
| G `types(groupId)` | REST `GET activity_types?select=id,name&group_id=eq` (sorted A–Z client-side) | members | |
| G `addType(groupId, name)` | REST `POST activity_types {group_id, name}` | members | 23505 duplicate (case-insensitive). |
| G `renameType(id, name)` | REST `PATCH activity_types {name}` | members | 23505. |
| G `deleteType(id)` | REST `DELETE activity_types?id=eq` | members | 23503 if any activity uses it. Cascades merge rules targeting it. |

## Type merging

| Dart | Call | Who | Errors / effects |
|---|---|---|---|
| G `merges(groupId)` | REST `GET type_merges?select=id,source_name,target_type_id&group_id=eq&order=source_name.asc` | members | |
| G `mergeTypes(groupId, sourceIds, {targetTypeId, targetName})` | `rpc merge_types(p_group uuid, p_source_type_ids uuid[], p_target_type_id uuid = null, p_target_name text = null) → uuid target_id` | members | P0001 "not a member of this group", "target type not found", "choose what to merge them into", "choose at least one type to merge". Moves activities, deletes source types, upserts rules, re-points chained rules. |
| G `removeMerge(id)` | `rpc remove_type_merge(p_merge uuid) → void` | members | P0001 "merge not found". Re-files activities whose `source_type_name` matches back to a same-name type (created if needed). |
| A `previewType(groupId, label)` | `rpc preview_group_type(p_group uuid, p_name text) → [{type_id, type_name, merged, is_new}]` | members | Read-only. `type_id` null when `is_new`. |

## Activities

Select string `Activity.columns` (in `models.dart`):
`id, owner_id, name, description, location, price_min, price_max, currency, url, created_at, updated_at, personal_type_id, activity_photos(id, storage_path, position), personal_type:personal_types!activities_personal_type_fk(name)`

| Dart | Call | Who | Errors / effects |
|---|---|---|---|
| A `myActivities()` | REST `GET activities?select=<columns>,group_activities(group_id)&owner_id=eq.<me>&deleted_at=is.null&order=created_at.desc` | owner | `group_activities` length → `sharedGroupCount` (only groups the user is in). |
| A `activity(id)` | REST `GET activities?select=<columns>&id=eq` (maybeSingle) | owner or member of a sharing group | null if deleted / not visible. `personal_type` is null for non-owners (RLS). |
| A `create(input)` | REST `POST activities <ActivityInput.toJson()>` → `id` | signed in | `owner_id` defaults to caller. 23503 if `personal_type_id` isn't the caller's label. |
| A `update(id, input)` | REST `PATCH activities?id=eq <fields>` | owner or sharing-group member | Columns granted: name, description, location, price_min, price_max, currency, url, personal_type_id. `personal_type_id` only sent when `setLabel` (owner); non-owner change → 42501. Label change re-files in all groups. |
| A `delete(id)` | `rpc delete_activity(p_activity uuid) → void` | owner | P0001 "only the owner can delete this activity". Unshares everywhere (entries → events), sets `deleted_at`. |

`ActivityInput.toJson()` keys: `name, description, location, price_min, price_max, currency, url` (+ `personal_type_id` when `setLabel`). Blank strings become null.

## Sharing

| Dart | Call | Who | Errors / effects |
|---|---|---|---|
| A `groupActivities(groupId)` | REST `GET group_activities?select=<GroupActivity.columns>&group_id=eq&order=added_at.desc` | members | `GroupActivity.columns` = `group_id, activity_id, type_id, added_by, added_at, source_type_name, activities!inner(<Activity.columns>), activity_types(name), sharer:profiles!group_activities_added_by_fkey(username)` |
| A `sharedIn(activityId)` | REST `GET group_activities?select=group_id,type_id,groups(name),activity_types(name)&activity_id=eq` | — | Returns only groups the caller is in. |
| A `share({activityId, groupId, typeId?})` | REST `POST group_activities {group_id, activity_id[, type_id]}` | member of group who can access the activity | Omit `type_id` → filed by owner's label via `resolve_group_type`; P0001 "choose a type for this group" if no label. 23505 if already shared. |
| A `changeType(...)` | REST `PATCH group_activities?group_id&activity_id {type_id}` | members | Type must belong to the group (FK). |
| A `unshare(...)` | REST `DELETE group_activities?group_id&activity_id` | members | Entries in that group revert to events. |

## Personal labels

| Dart | Call | Who | Effects |
|---|---|---|---|
| A `labels()` | REST `GET personal_types?select=id,name` (sorted A–Z client-side) | owner (RLS) | |
| A `addLabel(name)` | REST `POST personal_types {name}` → `id` | signed in | 23505 duplicate (case/space-insensitive). |
| A `renameLabel(id, name)` | REST `PATCH personal_types {name}` | owner | Re-files every activity with this label in all groups. |
| A `deleteLabel(id)` | REST `DELETE personal_types?id=eq` | owner | Activities' `personal_type_id` → null; group types unchanged. |

## Photos (Storage)

| Dart | Call | Who | Notes |
|---|---|---|---|
| A `addPhoto(activityId, bytes, extension, position)` | `storage.from('activity-photos').uploadBinary('<activityId>/<random>.<ext>')` then REST `POST activity_photos {activity_id, storage_path, position}` | can access activity | Content type png or jpeg. |
| A `removePhoto(photo)` | REST `DELETE activity_photos?id=eq` then `storage.remove([path])` | can access activity | |
| A `photoUrl(path)` | `storage.createSignedUrl(path, 3600)` | can access activity | Cached per path by `photoUrlProvider`. |

## History

| Dart | Call | Who |
|---|---|---|
| A `history(activityId)` | REST `GET change_log?select=entity_type,action,actor_id,before,after,created_at&entity_id=eq&entity_type=in.(activity,activity_photo,group_activity)&order=created_at.desc&limit=50`, then `GET profiles?select=id,username&id=in.(actors)` | actor, group members, or activity accessors |

Rendered by `describeChange()` in `activity_detail_page.dart`.

## Schedules

Dart: `app/lib/data/schedule_repository.dart` (S). Times are sent as UTC ISO strings; dates as `YYYY-MM-DD`.

| Dart | Call | Who | Notes |
|---|---|---|---|
| S `list(query)` | `rpc list_schedule(p_from date, p_to date, p_tz text, p_group uuid = null, p_include_unscheduled bool = false)` | signed in | No group → caller's own entries; with group → whole group (members only), plus "no date yet" events when asked. Returns rows `{id, group_id, group_name, activity_id, activity_name, title, all_day, date, start_at, end_at, created_by, my_status, participants:[{user_id, username, display_name, status}]}`. `p_tz` is the device zone; dates are inclusive local days. |
| S `create(...)` | `rpc create_schedule_entry` (below) | members | First call without force; on `{status:'clash'}` the UI asks, then retries with `p_force: true`. |
| S `reschedule(id, timing)` | `rpc reschedule_entry` | members | Same clash flow. |
| S `addParticipants(id, userIds)` | `rpc add_entry_participants` | members | Same clash flow. |
| S `setActivity(id, activityId)` | REST `PATCH schedule_entries?id=eq {activity_id}` | members | Replace event / swap activity; activity must be shared in the group (FK). |
| S `rename(id, title)` | REST `PATCH schedule_entries?id=eq {title}` | members | |
| S `delete(id)` | REST `DELETE schedule_entries?id=eq` | members | Removes for everyone. |
| S `leave(id)` | REST `DELETE schedule_participants?entry_id&user_id=<me>` | self | |
| S `acknowledgeClash(id)` | REST `PATCH schedule_participants?entry_id&user_id=<me> {status:'added'}` | self | |
| S `history(id)` | REST `GET change_log?entity_id=eq&entity_type=in.(schedule_entry,schedule_participant)` + profiles | group members | Rendered by `describeEntryChange()`. |
| `syncProfileTimezone()` | REST `PATCH profiles?id=eq.<me>&timezone=neq.<tz> {timezone}` | self | Called on sign-in / session restore from `main.dart`. |

---

## Schedule RPC reference

### `create_schedule_entry`
```
create_schedule_entry(
  p_group_id uuid, p_activity_id uuid,       -- null activity → event (needs p_title)
  p_title text, p_all_day boolean, p_date date,
  p_start_at timestamptz, p_end_at timestamptz,
  p_participant_ids uuid[],                  -- null → [caller]; all must be group members
  p_force boolean = false
) → jsonb
```
Returns `{status:'clash', clashes:[...]}` (nothing saved) or `{status:'created', entry_id, clashes}`. Clash item: `{user_id, username, entry_id, title ('Busy' if caller not in that group), all_day, entry_date, start_at, end_at}`. Errors: P0001 "not a member of this group", "all participants must be members of the group"; CHECK violations (23514) for invalid timing. Effects: participants `added`/`clash`, notifications `added_to_entry`/`schedule_clash`, `clash_override` log when forced.

### `reschedule_entry`
`reschedule_entry(p_entry uuid, p_all_day boolean, p_date date, p_start_at timestamptz, p_end_at timestamptz, p_force boolean = false) → jsonb` — same shape; status `'updated'`. Re-evaluates every participant's status.

### `add_entry_participants`
`add_entry_participants(p_entry uuid, p_user_ids uuid[], p_force boolean = false) → jsonb` — checks only the new people; status `'updated'`.

### `find_clashes`
`find_clashes(p_user_ids uuid[], p_all_day boolean, p_date date, p_start_at timestamptz, p_end_at timestamptz, p_exclude_entry uuid = null) → table(...)` — only for the caller and users sharing a group with them.

### Not yet used by the app
- `GET/PATCH notifications {read_at}` — own (for the notifications branch).
- `find_clashes` directly (the RPCs above call it).

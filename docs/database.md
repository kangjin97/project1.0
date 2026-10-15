# Database reference

Source of truth: `supabase/migrations/`. Test coverage: `supabase/tests/database/`.

| Migration | Adds |
|---|---|
| `20261002000000_init.sql` | Profiles, groups, invites, activities, photos, types, schedules, change log, notifications, RLS, RPCs, storage bucket, realtime publication |
| `20261009000000_labels_and_type_merges.sql` | Personal labels, `group_activities.source_type_name`, `type_merges`, label filing and re-filing, merge RPCs |
| `20261010000000_list_schedule.sql` | `list_schedule` read model for the schedule screens |
| `20261011000000_profiles.sql` | `profiles.bio`, `avatars` bucket, `shared_groups`, `my_profile_stats`; avatars in `list_schedule` |
| `20261012000000_timezones.sql` | Zone set at sign-up from metadata, `profiles_guard_timezone` validation, `is_valid_timezone`, `list_timezones` |
| `20261012010000_delete_account.sql` | "Who did it" FKs → `on delete set null`; `hand_over_ownership` trigger; `my_storage_files`, `delete_my_account` |
| `20261012020000_delete_account_order.sql` | `delete_my_account` unshares activities before deleting them |
| `20261012030000_touch_updated_existing_users.sql` | `touch_updated` stamps `updated_by` only for existing users |
| `20261014064145_cancel_email_change.sql` | `cancel_email_change` |
| `20261014082408_function_grants_and_search_path.sql` | Revoke `execute` on trigger functions and `entry_range` from `authenticated`; pin `search_path` on the remaining invoker functions |
| `20261014085422_list_notifications.sql` | `list_notifications` |
| `20261014203717_list_group_history.sql` | `list_group_history` |
| `20261014210549_realtime_broadcasts.sql` | `broadcast_change` triggers; who may listen on `realtime.messages` |
| `20261014220820_invite_management.sql` | One-way link revoke (`guard_invite_link_revoke`), invitation status `cancelled` + `cancel_invitation`, change log for links and invitations, `list_group_history` and `broadcast_change` extended for them |

## Tables

### `profiles`
One per auth user, created by the `on_auth_user_created` trigger from sign-up metadata (`username`, `display_name`).

| Column | Notes |
|---|---|
| `id` | = `auth.users.id` |
| `username` | Unique; `^[a-z0-9_]{3,30}$`, lower-cased on creation |
| `display_name` | Optional |
| `avatar_path` | Optional; `<user_id>/<file>` in the `avatars` bucket |
| `bio` | Optional, ≤ 160 characters |
| `timezone` | IANA name. Set at sign-up from the device (`timezone` in sign-up metadata, falls back to `UTC`); afterwards changed only by the user. Validated by the `profiles_guard_timezone` trigger (22023 for unknown names). Used for all-day clashes and as the app's display zone. |

Access: any signed-in user can read; users update their own row (`username`, `display_name`, `avatar_path`, `bio`, `timezone`).

### `groups`, `group_members`
- `groups`: `name` (1–80 characters), `created_by`. The `on_group_created` trigger adds the creator as `owner` and seeds the types Food, Outdoors, Entertainment and Other.
- `group_members`: primary key `(group_id, user_id)`, `role` `owner|member`.

Access:
- **Groups:** members can read, and so can the group's creator. Invitees with a pending invitation can read the group too, to see its name. Only owners can rename or delete.
- **Members:** members can read the member list. You can remove yourself (leave), and the owner can remove anyone. Joining only happens through `respond_to_invitation` or `join_group_via_link`. If the owner leaves, ownership passes to the longest-standing member.

### `group_invite_links`, `group_invitations`
- **Links:** a random 64-hex `token`, optional `expires_at` and `max_uses`, plus `use_count` and `revoked_at`. Members create and read them.
  - Only `revoked_at` can be updated, by any member, and only once: the `group_invite_links_guard_revoke` trigger sets it to `now()` and refuses to change or clear it afterwards (P0001).
  - Logged (`invite_link`) and broadcast to the group.
- **Invitations:** `invitee_id`, `invited_by`, `status` `pending|accepted|declined|cancelled`, `responded_at`.
  - At most one pending invitation per (group, invitee). Members can invite non-members.
  - The `on_invitation_created` trigger sends the invitee a `group_invitation` notification.
  - Accept or decline goes through `respond_to_invitation` (invitee); cancel goes through `cancel_invitation` (any member, pending only).
  - Logged (`invitation`) and broadcast to the invitee and the group.

### `activities`

| Column | Notes |
|---|---|
| `owner_id` | Creator. Can't be changed (no column grant). FK to `profiles` has no `on delete`, so the owner's activities must be deleted first (`delete_my_account` does). |
| `name` | 1–120 characters, required |
| `description`, `location`, `url` | Optional |
| `price_min`, `price_max`, `currency` | Numeric ≥ 0, `max ≥ min`; currency is `char(3)` (length only, no letter check), default `SGD` |
| `personal_type_id` | The owner's label. Composite FK `(personal_type_id, owner_id)` → `personal_types`, so it must be the owner's own label. Set to null if the label is deleted. Only the owner can change it (guard trigger, 42501). |
| `updated_at`, `updated_by` | Set by trigger |
| `deleted_at` | Soft delete, through `delete_activity` only |

Access: the owner, plus members of any group it's shared into, can read and update the editable columns. Nobody can delete rows directly.

### `activity_photos`
`storage_path` (`<activity_id>/<file>` in the `activity-photos` bucket) and `position`. Anyone who can access the activity can add, remove or reorder its photos.

### `activity_types`
Per-group types. Names are 1–40 characters and unique per group, ignoring case (`lower(name)`, not trimmed). Members can create, rename and delete them. Deleting a type that's in use fails with 23503 (FK from `group_activities`).

### `group_activities`
An activity shared into a group.

| Column | Notes |
|---|---|
| `(group_id, activity_id)` | Primary key |
| `type_id` | Required. Composite FK `(type_id, group_id)` keeps the type inside the group. If omitted on insert, it's filled from the owner's label. |
| `source_type_name` | The label it was filed by (null if a type was picked by hand). Used when undoing merges. |
| `added_by`, `added_at` | |

Access: members read, insert (only activities they can access), change `type_id`, and delete (unshare). Unsharing turns the group's schedule entries for that activity back into events.

### `personal_types`
A user's private labels. Names are 1–40 characters and unique per owner, ignoring case and surrounding spaces. Only the owner can see or change them. Renaming re-files every activity with that label.

### `type_merges`
`(group_id, source_name) → target_type_id`. Source names (1–40 characters) are unique per group, ignoring case and surrounding spaces. A rule is removed when its target type is deleted. Members can read; writes only through `merge_types` and `remove_type_merge`.

### `schedule_entries`, `schedule_participants`
- **Entry:**
  - `group_id` is required.
  - `activity_id` is optional (null means an **event**, and then `title` is required). Composite FK to `group_activities`, so the activity must be shared in that group.
  - Timing must be one of:
    1. all-day: `date` set, no times
    2. timed: `start_at < end_at`, no `date`
    3. unscheduled: no date or times, events only
- **Participant:** `(entry_id, user_id)`, `status` `added|clash`.

Access:
- Group members can read entries; participants can also read entries in groups they've left.
- Entries are created only through `create_schedule_entry`.
- Members can update `activity_id` and `title` (swapping in an activity, or replacing an event) and delete entries.
- Times change only through `reschedule_entry`.
- Participants are added only through the RPCs. A participant can remove themselves, or set their own `status` to `added` to acknowledge a clash.

### `change_log`
`actor_id`, `group_id`, `entity_type`, `entity_id`, `action`, `before`, `after` (jsonb; for updates, only the changed fields), `created_at`. It has no foreign keys, so history survives deletes. It's written only by the `log_change` trigger and by `apply_participants` (`clash_override`).

You can read an entry if any of these is true:
- you made the change;
- you're a member of its group;
- it's about an activity or activity photo you can access (`entity_type` `activity` or `activity_photo`).

The group History page reads it through `list_group_history` instead, which applies its own rules (members only; activity edits only from while the activity was shared in the group; no labels).

| `entity_type` | `entity_id` is | Actions |
|---|---|---|
| `activity` | activity id | created, updated, deleted |
| `activity_photo` | activity id | created, deleted |
| `activity_type` | type id | created, updated, deleted |
| `group_activity` | activity id | created (shared), deleted (unshared), updated, type_changed |
| `group_member` | user id | created (joined), deleted (left or removed) |
| `invite_link` | link id | created, updated (revoked; also use-count bumps, which group history hides) |
| `invitation` | invitation id | created (invited), updated (accepted, declined, cancelled) |
| `schedule_entry` | entry id | created, updated, deleted, event_replaced, activity_swapped, reverted_to_event, clash_override |
| `schedule_participant` | entry id | created, updated, deleted |
| `type_merge` | rule id | created, deleted |

### `notifications`
`user_id`, `kind`, `payload` jsonb, `read_at`. You read your own and can set `read_at`. The app reads them through `list_notifications`, which resolves the payload's ids. Kinds written so far:

| Kind | Payload |
|---|---|
| `group_invitation` | `{invitation_id, group_id, invited_by}` |
| `added_to_entry` | `{entry_id, group_id, by, clashes}` |
| `schedule_clash` | `{entry_id, group_id, by, clashes}` |

## RPCs (callable by signed-in users)

See [`ai/endpoints.md`](ai/endpoints.md) for parameters, return shapes and errors.

| Function | Purpose |
|---|---|
| `username_available(text)` | Sign-up check (also callable signed-out) |
| `find_user_by_email(text)` | Exact email → profile |
| `join_group_via_link(token)` / `preview_invite_link(token)` | Invite links |
| `respond_to_invitation(id, accept)` | Accept or decline |
| `cancel_invitation(id)` | Any member cancels a pending invitation from their group |
| `delete_activity(id)` | Owner soft delete; removes the activity from groups, entries revert to events |
| `preview_group_type(group, name)` | Where a label would be filed |
| `merge_types(group, source_ids[], target_id?, target_name?)` | Merge types |
| `remove_type_merge(rule_id)` | Undo one merge rule |
| `create_schedule_entry(...)`, `reschedule_entry(...)`, `add_entry_participants(...)` | Scheduling with clash checks |
| `find_clashes(...)` | Overlapping entries per user |
| `list_schedule(from, to, tz, group?, include_unscheduled?)` | Entries in a date window with group/activity/participant names; personal or group view |
| `shared_groups(user)` | Groups the caller shares with a user |
| `my_profile_stats()` | Caller's counts: groups, activities, upcoming plans |
| `delete_my_account()` | Deletes the caller's activities (plans become events) and auth user (cascades; groups handed over) |
| `my_storage_files()` | Caller's avatar and activity photo paths, to remove before deletion |
| `list_notifications(limit = 50)` | Caller's notifications, newest first, with actor name, group name, invitation status, plan title and timing, clash count. Plan details only while the caller is in the plan or its group; group name only for members or the invitee |
| `list_group_history(group, before = null, limit = 50)` | A group's change log for its History page, newest first, paged by id, with actor, activity/plan/type names, the member or participant, and old/new type names. Members only. Includes activity edits made while the activity was shared in the group (decided from the log's share and removal rows, so they stay after it leaves); strips the owner's label; leaves out bookkeeping rows; plans come with their id and timing while they exist |
| `cancel_email_change()` | Clears the caller's pending email change in `auth.users` (address and both tokens), so the links already sent stop working. Supabase Auth has no API for this. |
| `list_timezones()` | Zones for the picker: name, region, readable city, current offset in minutes (sorted by offset) |

### Internal helpers

Used by RLS policies and RPCs. Clients can call the read-only access helpers, but they only answer about the caller.

| Function | Returns |
|---|---|
| `is_group_member(group)` / `is_group_owner(group)` | Whether the caller is a member / the owner |
| `shares_group_with(user)` | Whether the caller and that user share any group |
| `is_activity_shared_with_me(activity)` | Whether the activity is in one of the caller's groups |
| `can_access_activity(activity)` | Owner, or member of a group it's shared into (and not deleted) |
| `entry_group(entry)` / `is_entry_participant(entry)` | An entry's group / whether the caller is on it |
| `entry_range(all_day, date, start, end, tz)` | The time range an entry occupies (all-day = the whole local day in `tz`) |
| `is_valid_timezone(name)` | Whether Postgres knows the zone name |
| `try_uuid(text)` | The text as a uuid, or null (used on storage paths) |

Not executable by clients (`function_privileges.test.sql` checks all of this):
- Internal helpers `resolve_group_type`, `apply_participants`, `entry_range` (only called inside `security definer` RPCs).
- Every trigger function: `handle_new_user`, `handle_new_group`, `log_change`, `notify_invitee`, `revert_entries_to_events`, `touch_updated`, `group_activity_defaults`, `guard_personal_type`, `refile_activity`, `refile_renamed_label`, `guard_timezone`, `hand_over_ownership`, `broadcast_change`, `guard_invite_link_revoke`. Postgres doesn't check `execute` when firing a trigger.
- Still callable by signed-in users because policies or invoker triggers use them: `try_uuid` (storage policies), `is_valid_timezone` (`guard_timezone`); and `list_timezones` (the picker).
- Signed-out (`anon`) callers can execute only `username_available`.
- Every function in `public` sets `search_path` (`= ''` and fully qualified names).

## Triggers

| Table | Trigger | Does |
|---|---|---|
| `auth.users` | `on_auth_user_created` | Creates the profile, with the time zone from sign-up metadata |
| `profiles` | `profiles_guard_timezone` | Rejects unknown time zone names (22023) |
| `groups` | `on_group_created` | Owner membership and starter types |
| `group_members` | `group_members_hand_over` | When the last owner leaves (or is deleted), the longest-standing member becomes owner; an empty group is deleted |
| `group_invitations` | `on_invitation_created` | Notifies the invitee |
| `group_invite_links` | `group_invite_links_guard_revoke` | Revoking is one-way; sets `revoked_at` to `now()` |
| `activities` | `activities_touch` | Sets `updated_at` / `updated_by` |
| `activities` | `activities_guard_personal_type` | Only the owner may change the label (42501) |
| `activities` | `activities_refile` | Label change → re-resolve type in every group (label removed → only `source_type_name` is cleared; types stay) |
| `personal_types` | `personal_types_refile` | Rename → re-resolve type for activities with that label |
| `group_activities` | `group_activities_defaults` | Records `source_type_name`; fills `type_id` from the label |
| `group_activities` | `group_activities_revert` | On unshare, the group's entries become events titled with the activity name |
| `schedule_entries` | `schedule_entries_touch` | Sets `updated_at` / `updated_by` |
| many | `log_*` | Writes `change_log` |
| many | `broadcast_*` | Sends a Realtime "changed" message to the group and/or user topics (see Realtime) |

## Storage

- `activity-photos` (private): select, insert and delete on `storage.objects` all require `can_access_activity(<first path segment>)`.
- `avatars` (private): any signed-in user can read; insert, update and delete only when the first path segment is your own user id.

## Realtime

Live updates use **Broadcast from the database** on private channels:
- **Sending:** the `broadcast_change` trigger (after insert/update/delete) calls `realtime.send({table}, 'changed', <topic>, private => true)`.
  - Topics: `group:<group_id>` and/or `user:<user_id>`, depending on the table. Activities go to their owner and every group they're shared in. Plans go to their group and each participant (who may have left the group). Plan participants go to the person and the plan's group. Invitations go to the invitee and the group. Invite links go to the group.
  - Tables: `groups`, `group_members`, `group_invitations`, `group_invite_links`, `group_activities`, `activities`, `activity_photos`, `activity_types`, `type_merges`, `schedule_entries`, `schedule_participants`, `notifications`.
  - Messages carry only the table name, never row data. At most one is sent per topic and table per transaction (tracked in the `easyplan.broadcasts_sent` setting).
  - `realtime.send` swallows its own errors, so a failed broadcast never blocks a write.
- **Listening:** the `easyplan_listen` select policy on `realtime.messages` lets an authenticated user join a private channel when `realtime.topic()` is `user:<their id>`, or `group:<id>` of a group they're a member of. There's no insert or update policy, so clients can't send. Signed-out users can't listen.
- **Not used:** the `supabase_realtime` publication from the init migration (`schedule_entries`, `schedule_participants`, `notifications`, `group_activities`, for "Postgres Changes") is still there but unused. That feed doesn't apply RLS to deletes and sends every subscriber the deleted row's key.

## Known gaps

- Accounts created before the time zone migration keep whatever zone they had (the seed accounts start as `UTC`).
- Group deletion is allowed by policy, but there's no UI for it.
- `change_log` keeps entries by deleted users (no FK); their `before`/`after` may still contain names of things they created.

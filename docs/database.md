# Database reference

Source of truth: `supabase/migrations/`. Test coverage: `supabase/tests/database/`.

| Migration | Adds |
|---|---|
| `20261002000000_init.sql` | Profiles, groups, invites, activities, photos, types, schedules, change log, notifications, RLS, RPCs, storage bucket, realtime publication |
| `20261009000000_labels_and_type_merges.sql` | Personal labels, `group_activities.source_type_name`, `type_merges`, label filing and re-filing, merge RPCs |

## Tables

### `profiles`
One per auth user, created by the `on_auth_user_created` trigger from sign-up metadata (`username`, `display_name`).

| Column | Notes |
|---|---|
| `id` | = `auth.users.id` |
| `username` | Unique; `^[a-z0-9_]{3,30}$`, lower-cased on creation |
| `display_name`, `avatar_path` | Optional |
| `timezone` | IANA name, default `UTC`. Used to work out all-day clashes. The app doesn't set it yet. |

Access: any signed-in user can read; users update their own row (`username`, `display_name`, `avatar_path`, `timezone`).

### `groups`, `group_members`
- `groups`: `name` (1–80 characters), `created_by`. The `on_group_created` trigger adds the creator as `owner` and seeds the types Food, Outdoors, Entertainment and Other.
- `group_members`: primary key `(group_id, user_id)`, `role` `owner|member`.

Access:
- **Groups:** members can read. Invitees with a pending invitation can read the group too, to see its name. Only owners can rename or delete.
- **Members:** members can read the member list. You can remove yourself (leave), and the owner can remove anyone. Joining only happens through `respond_to_invitation` or `join_group_via_link`.

### `group_invite_links`, `group_invitations`
- **Links:** a random 64-hex `token`, optional `expires_at` and `max_uses`, plus `use_count` and `revoked_at`. Members create and read them; only `revoked_at` can be updated.
- **Invitations:** `invitee_id`, `invited_by`, `status` `pending|accepted|declined`. At most one pending invitation per (group, invitee). Members can invite non-members. The `on_invitation_created` trigger sends the invitee a `group_invitation` notification.

### `activities`

| Column | Notes |
|---|---|
| `owner_id` | Creator. Can't be changed (no column grant). |
| `name` | 1–120 characters, required |
| `description`, `location`, `url` | Optional |
| `price_min`, `price_max`, `currency` | Numeric ≥ 0, `max ≥ min`; currency is 3 letters, default `SGD` |
| `personal_type_id` | The owner's label. Composite FK `(personal_type_id, owner_id)` → `personal_types`, so it must be the owner's own label. Set to null if the label is deleted. Only the owner can change it (guard trigger, 42501). |
| `updated_at`, `updated_by` | Set by trigger |
| `deleted_at` | Soft delete, through `delete_activity` only |

Access: the owner, plus members of any group it's shared into, can read and update the editable columns. Nobody can delete rows directly.

### `activity_photos`
`storage_path` (`<activity_id>/<file>` in the `activity-photos` bucket) and `position`. Anyone who can access the activity can add, remove or reorder its photos.

### `activity_types`
Per-group types. Names are unique per group, ignoring case. Members can create, rename and delete them. Deleting a type that's in use fails with 23503 (FK from `group_activities`).

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
A user's private labels. Names are unique per owner, ignoring case and surrounding spaces. Only the owner can see or change them. Renaming re-files every activity with that label.

### `type_merges`
`(group_id, source_name) → target_type_id`. Source names are unique per group, ignoring case. A rule is removed when its target type is deleted. Members can read; writes only through `merge_types` and `remove_type_merge`.

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
- Entries are created only through `create_schedule_entry`.
- Members can update `activity_id` and `title` (swapping in an activity, or replacing an event) and delete entries.
- Times change only through `reschedule_entry`.
- Participants are added only through the RPCs. A participant can remove themselves, or set their own `status` to `added` to acknowledge a clash.

### `change_log`
`actor_id`, `group_id`, `entity_type`, `entity_id`, `action`, `before`, `after` (jsonb; for updates, only the changed fields), `created_at`. It has no foreign keys, so history survives deletes. It's written only by the `log_change` trigger and by `apply_participants` (`clash_override`).

You can read an entry if any of these is true:
- you made the change;
- you're a member of its group;
- it's about an activity you can access.

| `entity_type` | `entity_id` is | Actions |
|---|---|---|
| `activity` | activity id | created, updated, deleted |
| `activity_photo` | activity id | created, deleted |
| `activity_type` | type id | created, updated, deleted |
| `group_activity` | activity id | created (shared), deleted (unshared), updated, type_changed |
| `group_member` | user id | created (joined), deleted (left or removed) |
| `schedule_entry` | entry id | created, updated, deleted, event_replaced, activity_swapped, reverted_to_event, clash_override |
| `schedule_participant` | entry id | created, updated, deleted |
| `type_merge` | rule id | created, deleted |

### `notifications`
`user_id`, `kind`, `payload` jsonb, `read_at`. You read your own and can set `read_at`. Kinds written so far:

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
| `delete_activity(id)` | Owner soft delete; removes the activity from groups, entries revert to events |
| `preview_group_type(group, name)` | Where a label would be filed |
| `merge_types(group, source_ids[], target_id?, target_name?)` | Merge types |
| `remove_type_merge(rule_id)` | Undo one merge rule |
| `create_schedule_entry(...)`, `reschedule_entry(...)`, `add_entry_participants(...)` | Scheduling with clash checks |
| `find_clashes(...)` | Overlapping entries per user |

Internal (not executable by clients): `resolve_group_type`, `apply_participants`, and the trigger functions.

## Triggers

| Table | Trigger | Does |
|---|---|---|
| `auth.users` | `on_auth_user_created` | Creates the profile |
| `groups` | `on_group_created` | Owner membership and starter types |
| `group_invitations` | `on_invitation_created` | Notifies the invitee |
| `activities` | `activities_touch` | Sets `updated_at` / `updated_by` |
| `activities` | `activities_guard_personal_type` | Only the owner may change the label (42501) |
| `activities` | `activities_refile` | Label change → re-resolve type in every group |
| `personal_types` | `personal_types_refile` | Rename → re-resolve type for activities with that label |
| `group_activities` | `group_activities_defaults` | Records `source_type_name`; fills `type_id` from the label |
| `group_activities` | `group_activities_revert` | On unshare, the group's entries become events titled with the activity name |
| `schedule_entries` | `schedule_entries_touch` | Sets `updated_at` / `updated_by` |
| many | `log_*` | Writes `change_log` |

## Storage

The bucket `activity-photos` is private. The select, insert and delete policies on `storage.objects` all require `can_access_activity(<first path segment>)`.

## Realtime

The `supabase_realtime` publication includes `schedule_entries`, `schedule_participants`, `notifications` and `group_activities`. The app doesn't subscribe to it yet.

## Known gaps

- `profiles.timezone` is never set by the app, so all-day clash checks currently use UTC.
- The trigger functions `handle_new_user`, `handle_new_group`, `log_change`, `notify_invitee`, `revert_entries_to_events` and `touch_updated` still have `execute` granted to `authenticated`. This is harmless, because Postgres refuses to call a trigger function outside a trigger, but it could be revoked for tidiness.
- Group deletion is allowed by policy, but there's no UI for it.

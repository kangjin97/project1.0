# Group Planning App — Specification

A web and mobile app for friends to plan things to do together: collect activity ideas, share them into groups, and put them on each other's schedules.

**Stack:** Flutter (web, iOS, Android) + Supabase (Postgres, Auth, Storage, Row Level Security).

---

## 1. Core concepts

| Concept | Summary |
|---|---|
| **User** | Has a unique username, email, and a personal schedule. |
| **Group** | A set of users. Has its own activity types, shared activities, and events. |
| **Activity** | A real thing to do (name, description, location, price, URL, photos). Starts private to its owner; becomes visible to a group once shared into it. |
| **Activity type** | A category defined per group (e.g. "Food", "Outdoors"). Each group creates and edits its own. |
| **Label** | A user's own private category for their activities (e.g. "yummy"). When shared, it decides the activity's group type. |
| **Type merge** | A group rule folding several labels/types into one type (e.g. "yummy" + "goodfood" → "Food"). |
| **Schedule entry** | Something on users' schedules at a date/time. Either linked to an activity, or an **event** (placeholder with only a name). |
| **Event** | An ad-hoc placeholder in a group, e.g. "eat some steak". Any group member can later replace it with a real activity. |

---

## 2. Functional requirements

### 2.1 Groups & membership
- A user can create a group and becomes its owner.
- Members join by:
  - **Invite link** — shareable token, optional expiry, optional max uses.
  - **Direct invite** — search users by username or email; invitee accepts or declines.
- Any member can leave a group.

### 2.2 Activities
- Fields: `name` (required), `description`, `location`, `price_min`, `price_max`, `currency`, `url`, photos, and the owner's **label** (optional, see §2.3).
- New activities are private to the owner.
- **Sharing:** the owner (or any member of a group it's already in) shares it into a group. If the activity has a label, it is filed automatically (§2.3); otherwise the sharer **must pick an activity type** for that group. The sharer can always override and pick a type by hand.
- **One source of truth:** there is a single activity record. Edits by the owner or any member of any group it's shared into apply everywhere — all groups and the owner's view see the same data. (Rationale: corrections like a fixed price or address should reach everyone.)
- Any group member can change the activity's **type within their group**.
- **Only the owner can delete** an activity (see §4.4 for effects).

### 2.3 Activity types, labels and merging
- Each group creates, renames, and deletes its own types. Deleting a type in use requires reassigning its activities first.
- **Labels:** each user keeps private labels and can put one on each of their activities. Only the owner sees or sets an activity's label.
- **Filing by label:** when a labelled activity is shared, its group type is
  1. the merge target, if the group has a merge rule for that label name; otherwise
  2. the group type with the same name; otherwise
  3. a new group type with that name.
  Names match ignoring case and surrounding spaces.
- **Merging:** any member can merge types into one (an existing type or a new name). Their activities move now, and activities shared later with any of those labels go to the merged type. A merge can be undone per label, which moves those activities back to a type of that name.
- **Label changes follow through:** if the owner changes or renames an activity's label, the activity is re-filed in every group it's in (into a merged type where one applies), overriding any manual type change. Deleting a label leaves group types unchanged.

### 2.4 Search & filter
- **My activities:** text search on name, description, location, label; filters: label, private/shared, max budget.
- **Group activities:** text search on name, description, location, type; filters: type, max budget, added by.
- Sort: newest, name, price (cheapest first).
- Not yet: has URL / has photos filters.

### 2.5 Schedules
- Every user has a schedule showing all entries they participate in, across all groups.
- An entry is either **all-day** or has a **start and end time**.
- Entries are created **within a group**: pick an activity (or create an event), a date/time, and which group members take part (defaults to the creator).
- Selected members are **added automatically** — no accept step — subject to the clash check (§2.6).
- Any participant can remove themselves from an entry. Any group member can remove an entry from the group schedule.

### 2.6 Clash detection
- Before saving an entry (or changing its time or participants), check every selected member's schedule for overlaps.
- **All-day entries clash with everything on that day**, and vice versa.
- If there are clashes, show the planner a confirmation:
  > *user1 already has "Dinner at Marco's" 7:00–9:00pm and "Beach day" (all day) on Sat 12 Oct. Proceed?*
- On **Proceed**: the entry is created, everyone is added, and clashing members get a notification listing the clash. Their participation is marked `clash` until they resolve it (keep both, or leave one).
- On **Cancel**: nothing is saved.

### 2.7 Events (placeholders)
- Created only inside a group, exactly like scheduling an activity but with no activity attached. Only `name` is required (date/time and participants are optional).
- Visible to all members of that group, so others can suggest something suitable.
- **Any group member** can:
  - replace an event with an activity, or
  - replace the activity on an entry with a different activity.
- Replacing keeps the entry's date/time and participants.

### 2.8 Change log
Every change is recorded with who made it and when, so it's always traceable who planned what. Logged actions include:
- Activity created / edited (field-level before → after) / deleted / shared into group / removed from group
- Activity type changed within a group
- Schedule entry created / time changed / removed
- Event replaced with an activity; activity swapped for another
- Participants added / removed
- Clash warning overridden (who proceeded, which members clashed)

Users can view the log per activity, per schedule entry, and per group.

---

## 3. Data model (Postgres)

The full, current schema is documented in [`docs/database.md`](docs/database.md) (source of truth: `supabase/migrations/`). Main tables:

| Table | Holds |
|---|---|
| `profiles` | Username, display name, timezone (one per auth user) |
| `groups`, `group_members` | Groups and membership with roles |
| `group_invite_links`, `group_invitations` | Invite codes and direct invites |
| `activities`, `activity_photos` | Activities (incl. owner's `personal_type_id`) and their photos |
| `personal_types` | Users' private labels |
| `activity_types`, `type_merges` | Per-group types and merge rules |
| `group_activities` | Activity shared into a group, with its type and `source_type_name` |
| `schedule_entries`, `schedule_participants` | Plans/events and who's in them |
| `change_log`, `notifications` | Audit trail and in-app notifications |

Notes:
- **Event** = `schedule_entries` row with `activity_id IS NULL`. Replacing it sets `activity_id`; `title` is kept for history.
- Activity type lives on `group_activities`, so one activity can have a different type in each group.
- `change_log` is written by database triggers, so no client can skip logging.
- Clash checks are Postgres functions (`find_clashes`, used by `create_schedule_entry` / `reschedule_entry` / `add_entry_participants`).

---

## 4. Permissions (enforced with Row Level Security)

### 4.1 Groups
- Members can read the group, its members, types, activities, and schedule entries.
- Any member can invite others and manage activity types.

### 4.2 Activities
- **Read / edit:** the owner, plus members of any group the activity is shared into.
- **Delete:** owner only.
- **Share into a group:** any user who can read it and is a member of the target group.

### 4.3 Schedule entries
- **Create / edit / replace activity / remove from group schedule:** any member of the entry's group.
- **Leave an entry:** any participant (themselves only).
- **Read:** group members; participants always see their own entries on their personal schedule.

### 4.4 Deleting an activity (owner)
- It is soft-deleted (`deleted_at`) so the log stays intact.
- It is removed from all groups.
- Schedule entries that used it **revert to events**, titled with the activity's name, so plans aren't silently lost.

---

## 5. Screens

1. **Auth:** sign up (pick a unique username), log in
2. **Home / My Schedule:** day, week, and month views across all groups; clash badges
3. **My Activities:** private and shared activities; create/edit; share to a group
4. **Activity detail:** fields, photos, groups it's in, change history
5. **Groups list:** create group, pending invitations
6. **Group home:** tabs for Activities (search/filter), Schedule, Events, Members, Types, Log
7. **Schedule entry sheet:** pick activity or name an event, all-day or a time range, pick members, then the clash confirmation dialog
8. **Replace event:** pick an activity from the group to fill the placeholder
9. **Invite:** copy link, or search by username/email
10. **Notifications:** invitations, added to entry, clash alerts, event replaced

---

## 6. Build order and status

| # | Step | Status |
|---|---|---|
| 1 | Supabase project: schema, RLS policies, triggers (change log), clash-check function | Done |
| 2 | Flutter app shell: auth, profiles, routing (web + mobile) | Done |
| 3 | Groups, membership, invites | Done |
| 4 | Activities, photos, sharing, per-group types | Done |
| 4a | Personal labels and type merging | Done |
| 5 | Search & filter (my activities and group) | Done |
| 6 | Schedules: entries, participants, clash detection | Database done; UI next |
| 7 | Events and replacement | Database done; UI next |
| 8 | Change-log views and notifications | Activity history done; group log and notifications UI to do |

Details and backlog: [`docs/ai/features.md`](docs/ai/features.md).

---

## 7. Open points

- Decisions made so far (including assumptions awaiting confirmation) are logged in [`docs/ai/decisions.md`](docs/ai/decisions.md).
- Can members **remove an activity from the group** (unshare), or only remove its schedule entries? Assumed: any member can unshare; it's logged.
- Should "similar" labels merge automatically (fuzzy matching)? Currently only explicit merge rules and exact (case-insensitive) names.
- Recurring entries (e.g. weekly game night): out of scope for v1.
- Push notifications on mobile vs. in-app only for v1.
- Time zones: store UTC (`timestamptz`), display in each user's local zone.

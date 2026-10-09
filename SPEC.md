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
| **Activity type** | A label defined per group (e.g. "Food", "Outdoors"). Each group creates and edits its own. |
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
- Fields: `name` (required), `description`, `location`, `price_min`, `price_max`, `currency`, `url`, photos.
- New activities are private to the owner.
- **Sharing:** the owner (or any member of a group it's already in) shares it into a group and **must pick an activity type** for that group.
- **One source of truth:** there is a single activity record. Edits by the owner or any member of any group it's shared into apply everywhere — all groups and the owner's view see the same data. (Rationale: corrections like a fixed price or address should reach everyone.)
- Any group member can change the activity's **type within their group**.
- **Only the owner can delete** an activity (see §4.4 for effects).

### 2.3 Activity types
- Each group creates, renames, and deletes its own types.
- Deleting a type in use requires reassigning affected activities to another type.

### 2.4 Search & filter (within a group)
- Text search on name, description, location.
- Filters: activity type, price range (e.g. "max ≤ 30"), has URL / has photos, added by.
- Sort: newest, name, price.

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

```text
profiles            id (= auth.users.id), username UNIQUE, email, display_name, avatar_path, created_at

groups              id, name, created_by → profiles, created_at
group_members       group_id → groups, user_id → profiles, role ('owner' | 'member'), joined_at
                    PK (group_id, user_id)
group_invite_links  id, group_id, token UNIQUE, created_by, expires_at NULL, max_uses NULL, use_count
group_invitations   id, group_id, invitee_id → profiles, invited_by, status ('pending'|'accepted'|'declined'), created_at

activities          id, owner_id → profiles, name, description, location,
                    price_min NUMERIC NULL, price_max NUMERIC NULL, currency CHAR(3),
                    url, created_at, updated_at, updated_by → profiles, deleted_at NULL
activity_photos     id, activity_id → activities, storage_path, position, uploaded_by

activity_types      id, group_id → groups, name, UNIQUE (group_id, name)
group_activities    group_id → groups, activity_id → activities, type_id → activity_types,
                    added_by → profiles, added_at
                    PK (group_id, activity_id)

schedule_entries    id, group_id → groups (NOT NULL), activity_id → activities NULL,
                    title NULL,             -- required when activity_id IS NULL (event)
                    all_day BOOLEAN, date DATE NULL,
                    start_at TIMESTAMPTZ NULL, end_at TIMESTAMPTZ NULL,
                    created_by → profiles, created_at, updated_at, updated_by
                    CHECK (activity_id IS NOT NULL OR title IS NOT NULL)
                    CHECK (all_day OR start_at IS NULL OR end_at > start_at)
schedule_participants entry_id → schedule_entries, user_id → profiles,
                    status ('added' | 'clash'), added_by, added_at
                    PK (entry_id, user_id)

change_log          id, actor_id → profiles, group_id NULL, entity_type, entity_id,
                    action, before JSONB NULL, after JSONB NULL, created_at
notifications       id, user_id → profiles, kind, payload JSONB, read_at NULL, created_at
```

Notes:
- **Event** = `schedule_entries` row with `activity_id IS NULL`. Replacing it sets `activity_id`; `title` is kept for history.
- Activity type lives on `group_activities`, so one activity can have a different type in each group.
- `change_log` is written by database triggers, so no client can skip logging.
- Clash check is a Postgres function (`check_clashes(user_ids, date, start_at, end_at, all_day)`) called before insert/update; it returns conflicting entries per user.

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

## 6. Build order

1. Supabase project: schema, RLS policies, triggers (change log), clash-check function
2. Flutter app shell: auth, profiles, routing (web + mobile)
3. Groups, membership, invites
4. Activities, photos, sharing, per-group types
5. Group search & filter
6. Schedules: entries, participants, clash detection
7. Events and replacement
8. Change-log views and notifications

---

## 7. Open points

- Can members **remove an activity from the group** (unshare), or only remove its schedule entries? Assumed: any member can unshare; it's logged.
- Recurring entries (e.g. weekly game night): out of scope for v1.
- Push notifications on mobile vs. in-app only for v1.
- Time zones: store UTC (`timestamptz`), display in each user's local zone.

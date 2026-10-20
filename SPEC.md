# EasyPlan — Specification

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
  - **Invite link** — shareable code/link, valid for 7 days; can be revoked (the database also supports a max-uses limit, which the app doesn't offer).
  - **Direct invite** — search users by username or email; invitee accepts or declines.
- Any member can see the group's active invite links (who made them, expiry, how many joined) and revoke one, and see pending invitations and cancel one. Revoking can't be undone; a cancelled invitation shows as cancelled to the invitee. Both are logged.
- Any member can leave a group. The owner can rename the group and remove members.
- The owner can **hand ownership to another member** (immediate; they become a regular member; the new owner is notified).
- The owner can **delete the group** after typing its name. Its plans, types and invites go with it; activities stay with their owners. Members and anyone in its plans are notified.

### 2.2 Activities
- Fields: `name` (required), `description`, `location`, `price_min`, `price_max`, `currency`, `url`, photos, and the owner's **label** (optional, see §2.3).
- **Location from Google Maps:** typing a location suggests real places from Google Maps; picking one keeps that exact place, so "Open in Google Maps" shows the right pin. Free text is still allowed. Each person can run 100 place searches a day.
- **Fill from link:** on New activity, paste a TikTok, YouTube or web link (plus an optional screenshot or caption, which is how Instagram works) and AI fills the form: name, description, location (matched to a Google place), price range, link and label, with the link's preview image offered as the first photo. Nothing is saved until the user reviews and saves. 30 fills per person per day.
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
- **My activities:** text search on name, description, location, label; filters: label, private/shared, max budget, has a link, has photos.
- **Group activities:** text search on name, description, location, type; filters: type, max budget, added by, has a link, has photos.
- **Near…** (both lists, and the activity picker when adding to a schedule): activities within a chosen straight-line distance (1–20 km) of your location or a searched place, nearest first with the distance shown. Only activities with a place picked from Google Maps can be measured; the others are counted in a note with a way to fix them. Your device location stays on the device.
- Sort: newest, name, price (cheapest first).

### 2.5 Schedules
- Every user has a schedule showing all entries they participate in, across all groups.
- An entry is either **all-day** or has a **start and end time**.
- Entries are created **within a group**: pick an activity (or create an event), a date/time, and which group members take part (defaults to the creator).
- Selected members are **added automatically** — no accept step — subject to the clash check (§2.6).
- Any participant can remove themselves from an entry. Any group member can remove an entry from the group schedule.
- On wide screens, a timed plan can be dragged to another time or day in the week view (same clash check; Undo afterwards).
- **Export an itinerary** (group Schedule tab): the group's plans for chosen days as an Excel itinerary (every detail and a cost summary), a PDF timetable (days as columns, plans as blocks), an image of that timetable, a day-by-day text to paste into a chat, or a calendar file (.ics) to add the plans to Google Calendar, Apple Calendar or Outlook.
- **Add to Google Calendar** on a plan: opens Google Calendar with the plan filled in. Calendar copies don't follow later changes.

### 2.6 Clash detection
- Before saving an entry (or changing its time or participants), check every selected member's schedule for overlaps.
- **All-day entries clash with everything on that day**, and vice versa.
- If there are clashes, show the planner a confirmation:
  > *user1 already has "Dinner at Marco's" 7:00–9:00pm and "Beach day" (all day) on Sat 12 Oct. Proceed?*
- On **Proceed**: the entry is created, everyone is added, and clashing members get a notification listing the clash. Their participation is marked `clash` until they resolve it (keep both, or leave one).
- On **Cancel**: nothing is saved.

### 2.7 Events (placeholders)
- Created only inside a group, exactly like scheduling an activity but with no activity attached. Only `name` is required (date/time is optional; participants default to the creator, and at least one is needed).
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
- Members joined / left; invite links created / revoked; people invited, invitations declined / cancelled
- Clash warning overridden (who proceeded, which members clashed)

Users can view the log per activity, per schedule entry, and per group. A group's log shows everything done in the group, plus edits to an activity made while it was shared there; the owner's private edits from before sharing, and labels, stay private.

### 2.9 Profiles
- Everyone has a profile page: picture, display name (≤50 characters), @username, and a short bio (≤160 characters).
- Users can change their picture, display name, bio, and username (if the new one isn't taken; same rules as sign-up). Account settings: change email (confirmed by links sent to both the current and the new address; a pending change can be cancelled, which voids the links) and password (current password required, or "Email me a link" to set one, e.g. for a Google account); sign out.
- Tapping someone in a group's members list or a plan's "who's going" opens their profile: picture, names, bio, and the groups you share.
- Your own profile also shows your counts: groups, activities, upcoming plans.
- **Forgot password:** request a reset link by email from the sign-in screen; the link opens a page to set a new password.
- **Continue with Google** (sign-in and sign-up): a Google account signs in with Google. The first time, the person picks a username (a suggestion from their name is filled in) and can use their Google photo. Signing up with an email that already has an account says it's already registered. A Google account has no password until the person sets one with Forgot password; then email and password work too. An existing account that uses Google with the same email becomes one account. Facebook may follow (#88).
- **Delete account** (Profile → Delete account, confirm by typing your username): deletes your profile, pictures, labels and activities; plans that used your activities stay as events; groups you own pass to their longest-standing member (empty groups are deleted); history shows "a deleted user". When any group owner leaves, ownership passes the same way.
- A privacy policy page is published with the web app and linked from sign-up and the profile.
- **Time zone**: set automatically from the device at sign-up (for Google, on the first-sign-in step); changeable later on the profile from a searchable list, where each zone shows its city, region and current UTC offset (e.g. "Singapore · Asia · UTC+08:00"). All times and calendar days in the app use the chosen zone.

---

## 3. Data model (Postgres)

The full, current schema is documented in [`docs/database.md`](docs/database.md) (source of truth: `supabase/migrations/`). Main tables:

| Table | Holds |
|---|---|
| `profiles` | Username, display name, avatar, bio, timezone (one per auth user) |
| `groups`, `group_members` | Groups and membership with roles |
| `group_invite_links`, `group_invitations` | Invite codes (revocable) and direct invites (pending, accepted, declined or cancelled) |
| `activities`, `activity_photos` | Activities (incl. owner's `personal_type_id`) and their photos |
| `personal_types` | Users' private labels |
| `activity_types`, `type_merges` | Per-group types and merge rules |
| `group_activities` | Activity shared into a group, with its type and `source_type_name` |
| `schedule_entries`, `schedule_participants`, `schedule_series` | Plans/events, who's in them, and repeating-plan series |
| `api_usage` | Per-user daily counts for paid outside APIs (place searches, AI fills) |
| `change_log`, `notifications` | Audit trail and in-app notifications |

Notes:
- **Event** = `schedule_entries` row with `activity_id IS NULL`. Replacing it sets `activity_id`; `title` is kept for history.
- Activity type lives on `group_activities`, so one activity can have a different type in each group.
- `change_log` is written by database triggers, so no client can skip logging.
- Clash checks are Postgres functions (`find_clashes`, used by `create_schedule_entry` / `reschedule_entry` / `add_entry_participants` and the repeating-plan RPCs `create_schedule_series` / `extend_series` / `reschedule_following` / `add_participants_following`).

---

## 4. Permissions (enforced with Row Level Security)

### 4.1 Groups
- Members can read the group, its members, types, activities, and schedule entries.
- Any member can invite others, see and revoke invite links, cancel pending invitations, and manage activity types. Only the owner can rename or delete the group, remove members, or hand ownership to another member.

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

While the app is open, screens update by themselves within a second or two when other people change something (no banners or pop-ups); the Alerts badge counts up live.

1. **Auth:** sign up (pick a unique username) or log in, with email and password or **Continue with Google**; a first Google sign-in goes to a **Welcome** step to pick a username
2. **Home / My Schedule:** list (agenda), week and month views across all groups; clash badges. The list starts today and can show earlier weeks; plans that are over are muted (the group Schedule tab works the same).
3. **My Activities:** private and shared activities; create/edit; share to a group
4. **Activity detail:** fields, photos, groups it's in, change history
5. **Groups list:** create group, pending invitations
6. **Group home:** tabs for Activities (search/filter), Schedule (with unscheduled events as "Ideas"), Members (invite people or create a link; active invite links with Revoke; invitations "Waiting for an answer" with Cancel; the member list, where the owner can remove people or make another member the owner), Types; **History** (the group's change log) from the group's menu.
7. **Schedule entry sheet:** pick activity or name an event, all-day or a time range, pick members, then the clash confirmation dialog
8. **Replace event:** pick an activity from the group to fill the placeholder
9. **Invite:** copy link, or search by username/email
10. **Notifications** ("Alerts" tab with an unread badge): invitations, added to a plan or a repeating plan, clash alerts, group deleted, made the group's owner. "Event replaced" isn't written by the database yet.
11. **Profile:** own profile, stats, account settings; **other people's profiles** from shared groups
12. **Join:** preview and join a group from an invite link
13. **Reset password:** set a new password from the emailed link

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
| 6 | Schedules: entries, participants, clash detection | Done |
| 7 | Events and replacement | Done |
| 8 | Change-log views, notifications and live updates | Done: activity, entry and group history; notifications screen; live updates (#7) |
| 9 | Group admin and invites: delete group, hand over ownership, manage invite links and invitations (#9, #10) | Done |
| 10 | Schedule extras: past plans, drag to reschedule, repeating plans (#11, #12, #17) | Done |
| 11 | Google Maps locations and Fill from link with AI (#73, #74) | Done |
| 12 | Store builds and app icon (#13, #14, #15) | Not started |
| 13 | Itinerary export (#96) and Google Calendar (#97) | Done |

Details and backlog: [`docs/ai/features.md`](docs/ai/features.md).

---

## 7. Open points

- Decisions made so far (including assumptions awaiting confirmation) are logged in [`docs/ai/decisions.md`](docs/ai/decisions.md).
- Assumed, awaiting the owner's confirmation (see `decisions.md`): any member can unshare an activity (logged); labels match by name, ignoring case and surrounding spaces (no fuzzy "similar" matching).
- Recurring entries (e.g. weekly game night): built (#17). Weekly, every 2 weeks or monthly, ending on a date at most a year ahead; edits apply to one date or that date and later ones; one notification per series.
- Push notifications on phones: in-app only for v1; tracked as #18.
- Time zones: stored in UTC (`timestamptz`), shown in each user's **profile** time zone (not the device's).

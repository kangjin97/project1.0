# Feature map

One section per feature: status, behaviour rules, where the code lives, how it's tested. Paths are relative to the repo root. Keep this file current when you change a feature.

Status legend: **Done** = DB + UI + tests. **DB only** = schema/RPCs/tests exist, no UI. **Not started**.

---

## F1. Accounts and auth — Done
- Email + password via Supabase Auth. Sign-up requires a unique username `^[a-z0-9_]{3,30}$` (checked with `username_available`, enforced by unique constraint). Optional display name.
- Signed-out users are redirected to `/auth?next=<original>`; after sign-in they return there (keeps invite links working).
- UI: `app/lib/features/auth/auth_page.dart`; redirect in `app/lib/router.dart`.
- DB: `profiles`, trigger `handle_new_user`, `username_available`.
- Tests: `core_rules.test.sql` (profile creation).

## F2. Groups and membership — Done
- Create (creator = owner, starter types seeded), rename (owner), leave (anyone), remove member (owner).
- UI: `features/groups/groups_page.dart` (list, create, pending invitations), `group_page.dart` (tabs, rename/leave menu, Members tab).
- Data: G `myGroups`, `group`, `createGroup`, `renameGroup`, `leaveGroup`, `members`, `removeMember`; providers `myGroupsProvider`, `groupProvider(id)`, `membersProvider(id)`.
- DB: `groups`, `group_members`, `handle_new_group`.
- Tests: `core_rules.test.sql`.
- Gaps: no delete-group UI; no owner transfer (owner leaving leaves the group ownerless).

## F3. Invites — Done
- Direct: search by username prefix or exact email → invitation → invitee accepts/declines on Groups page.
- Link: 7-day invite code/link (`/#/join/<token>`); preview shows group name and member count; joining is idempotent.
- UI: `group_page.dart` (`_InviteSheet`, invite link dialog), `groups_page.dart` (invitations, "Join with code"), `join_page.dart`.
- Data: G `searchUsers`, `invite`, `pendingInvitations`, `respond`, `createInviteLink`, `previewLink`, `joinViaLink`.
- DB: `group_invitations`, `group_invite_links`, `find_user_by_email`, `respond_to_invitation`, `preview_invite_link`, `join_group_via_link`, trigger `notify_invitee`.
- Tests: `core_rules.test.sql`.
- Gaps: no UI to revoke links or see sent invitations.

## F4. Activities — Done
- Fields: name (required), description, location, price min/max + currency (max ≥ min; 0/0 shows "Free"), link (https:// added if missing), photos, personal label.
- Private to the owner until shared. Once shared, **one shared record**: owner and members of any group it's in can edit; edits show everywhere.
- Only the owner deletes (soft delete); the activity leaves all groups and its schedule entries become events.
- Detail page: photos, label (owner only), location → Google Maps search, link, groups it's in (change type / remove), history.
- UI: `features/activities/activities_page.dart`, `activity_form_page.dart` (`showActivityForm`), `activity_detail_page.dart` (`describeChange`), `activity_widgets.dart` (`ActivityCard`, `ActivityPhotoImage`).
- Data: A `myActivities`, `activity`, `create`, `update`, `delete`, `addPhoto`, `removePhoto`, `photoUrl`, `history`; providers `myActivitiesProvider`, `activityProvider(id)`, `activityHistoryProvider(id)`, `photoUrlProvider(path)`; helper `invalidateActivity`.
- DB: `activities`, `activity_photos`, storage bucket `activity-photos`, `delete_activity`, `can_access_activity`, `log_change`.
- Tests: `core_rules.test.sql` (visibility, member edits, owner-only delete, logging).

## F5. Sharing into groups and per-group types — Done
- Share from an activity (pick group) or from a group (pick one of your activities, or create one inline).
- Every shared activity has a group type. With a label and no manual pick, it's filed automatically (F6); otherwise the sharer picks a type (can add a new type inline).
- Any member can change an activity's type in the group or remove it from the group.
- Types tab: add, rename, delete (blocked while in use), merge (F6). Shows activity counts.
- UI: `features/activities/share_activity_sheet.dart` (`showShareActivitySheet`), `features/groups/group_activities_tab.dart`, `features/groups/group_types_tab.dart`.
- Data: A `groupActivities`, `sharedIn`, `share`, `changeType`, `unshare`; G `types`, `addType`, `renameType`, `deleteType`; providers `groupActivitiesProvider(groupId)`, `sharedInProvider(activityId)`, `typesProvider(groupId)`.
- DB: `group_activities`, `activity_types`, triggers `group_activity_defaults`, `revert_entries_to_events`.

## F6. Personal labels and type merging — Done
- Labels are private per user; one label per activity; only the owner sets it.
- Filing rule (`resolve_group_type`): merge rule for the label name → its target; else group type with the same name (case/space-insensitive); else create that type.
- Share sheet previews the result (`preview_group_type`): "Filed under X", "X merged Y into it", or "Adds a new type".
- Merging (Types tab → Merge types): choose source types and a target (existing or new name). Existing activities move now; future activities with those labels go to the target. Target shows "Includes …" chips; removing a chip undoes that rule and moves matching activities back to a same-name type.
- Changing or renaming a label re-files the activity in every group, **overriding** manual type changes. Deleting a label leaves group types as they are.
- UI: label picker in `activity_form_page.dart`; `_LabelsSheet` in `activities_page.dart`; `_labelPreview` in `share_activity_sheet.dart`; `group_types_tab.dart` (`_MergeSheet`, `_TypeTile`).
- Data: A `labels`, `addLabel`, `renameLabel`, `deleteLabel`, `previewType`; G `merges`, `mergeTypes`, `removeMerge`; providers `labelsProvider`, `typePreviewProvider((groupId, label))`, `mergesProvider(groupId)`; helper `invalidateLabels`.
- DB: `personal_types`, `type_merges`, `group_activities.source_type_name`, `resolve_group_type`, `preview_group_type`, `merge_types`, `remove_type_merge`, triggers `guard_personal_type`, `refile_activity`, `refile_renamed_label`.
- Tests: `labels_and_merges.test.sql` (the yummy/goodfood scenario end to end).

## F7. Search and filters — Done (client-side)
- My activities: text search over name, description, location, label; filters label (multi), sharing (all/private/shared), max budget; sort newest/name/cheapest.
- Group activities: text search over name, description, location, group type; filters type (multi), max budget, added by; same sorts.
- Budget filter keeps activities whose range overlaps `[0, max]` or that have no price (`Activity.fitsBudget`).
- Runs in memory on the loaded list. If groups grow large, move to server-side filtering (PostgREST filters or an RPC).
- UI: `activities_page.dart` (`_apply`), `group_activities_tab.dart` (`_apply`).

## F8. Schedules, clash detection, events — Done
- Entries belong to a group; either an activity or an event (title only). Timing: timed (may run past midnight), all-day, or "no date yet" (events only).
- Adding people adds them directly; if anyone is busy the planner sees a clash dialog listing who has what (all-day clashes with everything that day, in each person's time zone; other groups' entries show as "Busy"). Proceeding saves with `clash` status for those people, notifies them and logs it.
- **My schedule** (`/schedule`): entries the user is in, across groups, with a **List | Week | Month** switch on every screen size (phones default to List, ≥720 px to Week).
  - List: day-by-day agenda from today (4 weeks, "Show 4 more weeks").
  - Week: all-day row + hourly blocks, overlaps side by side, opens at 8am. Phones get single-letter days, a slim hour gutter and title-only blocks.
  - Month: six-week grid with titles; on phones, coloured dots (primary = yours, red = clash).
  - Week/Month have ‹ › Today navigation; tapping a day opens that day's list with "Add". On phone calendars the add button is a small round FAB.
- **Group Schedule tab**: "Ideas · not scheduled yet" events first, then the next 8 weeks of the group's entries (all members' plans; the user's highlighted).
- **Entry detail sheet**: when, who (clash badges), change time (re-checks clashes), add people (checks new people), replace event with activity / swap activity, rename event, view activity, leave, remove for everyone, history. If the user has a clash: "Keep both" or "Leave this".
- **Add to schedule** from: My schedule FAB, group Schedule tab, and the activity detail page (per group).
- The device's IANA time zone is saved to `profiles.timezone` on sign-in (used by all-day clash checks).
- UI: `features/schedule/my_schedule_page.dart`, `calendar_views.dart` (`WeekView`, `MonthView`), `schedule_widgets.dart` (`EntryTile`, `AgendaList`, `confirmClashes`, time labels), `entry_editor.dart` (`showEntryEditor`, `showRescheduleEditor`), `entry_detail_sheet.dart` (`showEntryDetail`, `describeEntryChange`); `features/groups/group_schedule_tab.dart`.
- Data: `data/schedule_models.dart` (`ScheduleEntry`, `ScheduleParticipant`, `ScheduleClash`, `ScheduleResult`, `EntryTiming`, date helpers), `data/schedule_repository.dart` (`list`, `create`, `reschedule`, `addParticipants`, `setActivity`, `rename`, `delete`, `leave`, `acknowledgeClash`, `history`, `syncProfileTimezone`); providers `scheduleProvider(ScheduleQuery)`, `entryHistoryProvider(id)`; helper `invalidateSchedule`.
- DB: `schedule_entries`, `schedule_participants`, `list_schedule`, `create_schedule_entry`, `reschedule_entry`, `add_entry_participants`, `find_clashes`, `apply_participants`, `entry_range`.
- Tests: `core_rules.test.sql` (clash, force, acknowledge, reschedule, replace event, delete → event), `list_schedule.test.sql` (personal vs group view, windows, time zones, privacy).
- Gaps: past entries aren't browsable on phones (agenda starts today); no drag-to-reschedule; no recurring entries.

## F9. Notifications — DB only (planned as its own branch)
- Kinds: `group_invitation`, `added_to_entry`, `schedule_clash` (the schedule feature already writes the last two).
- **To build:** notifications screen/badge, mark read (`PATCH notifications {read_at}`), realtime subscription, optional push.

## F10. Change log — Done for activities, DB for everything else
- Every insert/update/delete on core tables is logged by trigger with actor and before/after.
- Shown on the activity detail page and the schedule entry sheet. **To build:** per-group log view.

---

## Backlog (priority order suggested)
1. F9 notifications UI (own branch).
2. Realtime subscriptions for group activities, schedules and notifications.
3. Group log view (F10), invite link management (F3), delete group / transfer ownership (F2).
4. Profile editing (display name, avatar).
5. Server-side search if lists get large (F7).
6. Browsing past schedule entries on phones; drag-to-reschedule.
7. Recurring entries, push notifications (out of scope for v1 per `SPEC.md`).

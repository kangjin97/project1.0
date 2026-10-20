# Feature map

One section per feature: status, behaviour rules, where the code lives, how it's tested. Paths are relative to the repo root. Keep this file current when you change a feature.

Status legend: **Done** = DB + UI + tests. **DB only** = schema/RPCs/tests exist, no UI. **Not started**.

---

## F1. Accounts and auth — Done (Google sign-in #87; Facebook #88 to come)
- Email + password via Supabase Auth. Sign-up requires a unique username `^[a-z0-9_]{3,30}$` (checked with `username_available`, enforced by unique constraint). Optional display name (≤50; the database checks it).
- **Continue with Google** (#87) on the sign-in and sign-up pages (Supabase Auth's Google provider). Google sends the browser back to `<APP_URL>/?next=<path>`, so invite links survive it too.
  - First Google sign-in: Google gives no username, so the profile starts with a placeholder (`user_<hex>`) and `needs_username`; the router sends the person to **`/welcome`** before anything else. It suggests a username from their name or email (`usernameBase`, `usernameCandidates`, first free one), shows their Google name, and offers "Use your Google photo" (ticked; copied once into the avatars bucket, only when they have no picture). Continue saves the username (which clears the flag in the database), sets the device's time zone and copies the photo.
  - Owner's rules (2026-10-19): a Google account signs in with Google; registering with a used email says "already registered"; a Google account has no password until the person sets one with **Forgot password?**, after which email + password works too; an existing email-and-password account that uses Google with the same email becomes one account (Supabase links verified emails).
  - Sign-up says "This email is already registered…" for a used email (on the cloud Auth returns no error for it, so `signUp` checks for a user without identities), and asks the person to check their inbox when the account needs confirming. A wrong password points Google users to Google or Forgot password.
- Signed-out users are redirected to `/auth?next=<original>`; after sign-in they return there (keeps invite links working).
- Auth emails whose links return to the site root (`/?code=` sign-up confirmation, `/?message=` first step of a secure email change, `/?error_description=` expired link) go to My schedule (or sign-in); a `?message=` or `?error_description=` note is shown as a snackbar (`?code=` has none) (`authLinkNotice`, `rootMessengerKey` in `router.dart`). Tests: `app/test/router_test.dart`.
- UI: `app/lib/features/auth/auth_page.dart`, `welcome_page.dart` (`WelcomePage`, `usernameBase`, `usernameCandidates`); redirect in `app/lib/router.dart` (`safeNext`, `_AuthRefresh.needsUsername`). Data: `data/auth_repository.dart` (`signUp`, `signIn`, `signInWithGoogle`, `googlePhotoUrl`, `sendPasswordReset`, `setNewPassword`; `authRepositoryProvider`), `profile_repository.dart` (`needsUsername`, `copyAvatarFrom`).
- DB: `profiles` (`needs_username`), triggers `handle_new_user`, `profiles_username_chosen`; `username_available`.
- Setup: Google OAuth client in Google Cloud, the provider in the Supabase dashboard, and `supabase/.env` locally (`deployment.md` → Sign in with Google).
- Live since 2026-10-19; the owner checked on a phone that Continue with Google works end to end and that a used email gets "already registered" on the cloud.
- Tests: `core_rules.test.sql` (profile creation), `display_name_length.test.sql` (sign-up name), `google_sign_in.test.sql`; `app/test/username_suggestion_test.dart`, `router_test.dart` (`safeNext`).

## F2. Groups and membership — Done
- Create (creator = owner, starter types seeded), rename (owner), leave (anyone), remove member (owner).
- **Delete a group** (owner; ⋮ → Delete group): the dialog says what goes (upcoming plans and undated ideas, types, invite links; counts from `group_deletion_summary`), that activities stay with their owners and who'll be told; the owner types the group's name to confirm (checked again in the database). Members and anyone in its plans get a "Bob deleted Hikers" notification. Someone viewing the group when it's deleted sees "This group no longer exists" live.
- **Make another member the owner** (owner; Members tab → ⋮ next to a member → Make owner): immediate; the old owner becomes a member. The new owner is notified ("Ann made you the owner of Hikers", taps through to the group) and group history says "made @bob the owner".
- Owner-only actions (Rename, Delete, per-member menu) are hidden from other members; the database refuses them anyway.
- When the owner leaves (or deletes their account), ownership passes to the longest-standing member; a group left with no members is deleted (`hand_over_ownership` trigger).
- UI: `features/groups/groups_page.dart` (list, create, pending invitations), `group_page.dart` (tabs; ⋮ rename/history/leave/delete; `_DeleteGroupDialog`, `deletionWarning`; Members tab with Make owner / Remove; "no longer exists" state).
- Data: G `myGroups`, `group`, `createGroup`, `renameGroup`, `leaveGroup`, `members`, `removeMember`, `deletionSummary`, `deleteGroup`, `transferOwnership`; providers `myGroupsProvider`, `groupProvider(id)`, `membersProvider(id)`.
- DB: `groups`, `group_members`, `handle_new_group`, `hand_over_ownership`, `group_deletion_summary`, `delete_group`, `transfer_ownership`. Groups can only be deleted through `delete_group` (no delete policy).
- Tests: `core_rules.test.sql`, `delete_account.test.sql` (hand-over), `group_admin.test.sql` (summary, hand-over rules and history, delete rules and typed name, what's deleted and kept, who's notified, the last member leaving a group with planned activities); `app/test/group_delete_text_test.dart`, `group_history_text_test.dart`, `notifications_text_test.dart`.

## F3. Invites — Done
- Direct: search by username prefix or exact email → invitation → invitee accepts/declines on Groups page.
- Link: 7-day invite code/link (the database caps every link at 7 days) (`<APP_URL>/join/<token>`, built by `AppConfig.inviteLink`); "Join with code" accepts the bare code or a pasted link; preview shows group name and member count; joining is idempotent. On Android the link opens the installed app once App Links are verified (see `docs/deployment.md`).
- **Managing invites** (Members tab, any member; owner's choices):
  - **Active invite links** lists links that still work (not expired, used up or revoked): code, who made it, expiry, "N joined". Tap a link to copy it again.
  - **Revoke** asks for confirmation. Revoking is one-way: the database sets the time and refuses to undo it. People who already joined stay.
  - **Waiting for an answer** lists pending invitations sent from the group: who, invited by whom, when.
  - **Cancel** asks "Keep it / Cancel invitation". The invitee's card disappears, and their alert reads "Cancelled"; tapping it says the invitation was cancelled.
  - Both lists update live, and every create, revoke, invite and cancel shows in group history with who did it (F10).
- UI: `group_page.dart` (`_InviteSheet`, `_showInviteLinkDialog`, `_InviteLinksSection`, `_SentInvitationsSection`), `groups_page.dart` (invitations, "Join with code"), `join_page.dart`.
- Data: G `searchUsers`, `invite`, `pendingInvitations`, `respond`, `createInviteLink`, `previewLink`, `joinViaLink`, `inviteLinks`, `revokeInviteLink`, `sentInvitations`, `cancelInvitation`; providers `invitationsProvider`, `inviteLinksProvider(groupId)`, `sentInvitationsProvider(groupId)`; models `InviteLink` (`isActiveAt`), `SentInvitation`.
- DB: `group_invitations` (status `pending|accepted|declined|cancelled`), `group_invite_links`, `find_user_by_email`, `respond_to_invitation`, `cancel_invitation`, `preview_invite_link`, `join_group_via_link`, triggers `notify_invitee`, `group_invite_links_guard_revoke`, `group_invite_links_guard_insert` (7-day cap and server-picked token, #82).
- Tests: `core_rules.test.sql`; `invite_management.test.sql` (any member revokes, non-members can't, server sets the time, no un-revoking, revoked links refuse joins, any member cancels, invitee can't, only pending ones, cancelled can't be accepted, alert shows "cancelled", history lines without codes, live broadcasts); `invite_link_expiry.test.sql` (7-day link kept, missing → 7 days, longer capped, shorter kept, server-picked 64-hex token, server's use count / created / revoked, expiry can't be extended later).

## F4. Activities — Done
- Fields: name (required), description, location, price min/max + currency (max ≥ min; 0/0 shows "Free"), link (https:// added if missing), photos, personal label.
- Private to the owner until shared. Once shared, **one shared record**: owner and members of any group it's in can edit; edits show everywhere.
- Only the owner deletes (soft delete); the activity leaves all groups and its schedule entries become events.
- Detail page: photos, label (owner only), location → Google Maps ("Open in Google Maps" opens the exact place when one was picked, otherwise a search), link, groups it's in (change type / remove), history.
- UI: `features/activities/activities_page.dart`, `activity_form_page.dart` (`showActivityForm`), `activity_detail_page.dart` (`describeChange`), `activity_widgets.dart` (`ActivityCard`, `ActivityPhotoImage`).
- Data: A `myActivities`, `activity`, `create`, `update`, `delete`, `addPhoto`, `removePhoto`, `photoUrl`, `history`; providers `myActivitiesProvider`, `activityProvider(id)`, `activityHistoryProvider(id)`, `photoUrlProvider(path)`; helper `invalidateActivity`.
- DB: `activities`, `activity_photos`, storage bucket `activity-photos`, `delete_activity`, `can_access_activity`, `log_change`.
- Tests: `core_rules.test.sql` (visibility, member edits, owner-only delete, logging).
- **Google Maps locations** (#73):
  - Typing 3+ characters in Location suggests places from Google Maps (Places API (New) Autocomplete), after a 400 ms pause. Suggestions show name and area, with the required "Google Maps" attribution in the list.
  - Picking one fills "Name, area" and keeps the place ID (check mark, "Exact place from Google Maps"). Free text still works.
  - Editing the text after a pick drops the place, in the form and in the database (trigger), so a place never outlives its text.
  - Searches run in the `places` Edge Function, so the Google key never reaches the browser. Signed-in users only; 100 searches per person per day, counted in their time zone (`consume_api_quota`). Billed per search (no sessions or Place Details); see decisions.md.
  - UI: `features/activities/place_field.dart` (`PlaceField`), form and detail page. Data: `data/places_repository.dart` (`PlacesRepository.suggest`, `PlaceSuggestion`, `googleMapsUri`); `Activity.placeId`, `ActivityInput.placeId`. Function: `supabase/functions/places/index.ts`. DB: `activities.place_id`, trigger `activities_drop_stale_place`, `api_usage`, `consume_api_quota`.
  - Tests: `place_search.test.sql` (ID format, place needs text, editing text drops the place, other edits keep it, 100 a day then refused and not counted, per-person, time zone, unknown kinds, table locked, anon); `app/test/places_test.dart` (labels, maps links, input); `app/test/place_field_test.dart` (editing drops the pick, one search per pause, attribution, under 3 characters never searches). The function was tried against the real Places API locally; it has no automated test (it needs Google).
- **Fill from link (AI)** (#74; New activity only):
  - "Fill from link" at the top of New activity opens a sheet: paste a link, optionally add a screenshot and/or paste the caption, tap **Fill in**. The form fills in (name, description, location matched to a Google place, price range and currency, link, label) and the user reviews it; **nothing is saved until Save** (owner's choice).
  - **Official sources only** (owner's choice): TikTok and YouTube oEmbed; a normal page's own preview tags (Open Graph / title / description), one request with a 6 s timeout and 512 KB cap; Instagram, Facebook (`fb.watch` too) and Threads aren't fetched (no preview without Meta's API), so the sheet asks for a screenshot or caption. Private and local addresses are refused, including after redirects.
  - **Claude Haiku 5.5** (`claude-haiku-5-5`) reads the preview image, screenshot and text and returns schema-checked JSON (structured outputs, effort `low`). Called with the Anthropic SDK; currently through the reseller AIML API (`ANTHROPIC_BASE_URL`), direct to Anthropic when that's unset (`deployment.md` → Claude for "Fill from link"). It reuses one of the user's labels only when that label really describes the activity (not just the closest one, #79); otherwise it suggests a new one, shown as an **Add "X"** chip that creates it only if tapped.
  - The link's **preview image** is offered as the first photo, with "Use the link's preview image" ticked (owner's choice).
  - Filling replaces the name, description, location and link only where something was found, but always replaces both prices (empty when none were found). A suggested currency is applied only if it's one the form offers; otherwise the current one stays.
  - **30 fills per person per day** (`consume_api_quota('ai_fill')`). Matching the location uses one place search from the 100-a-day place quota. A link with nothing to read (and no screenshot or caption) stops early with a hint, without using a fill or calling Claude.
  - UI: `features/activities/fill_from_link_sheet.dart` (`showFillFromLinkSheet`), `activity_form_page.dart` (`_fillFromLink`, suggested label chip, preview-image checkbox). Data: `data/ai_fill_repository.dart` (`AiFillRepository.fill`, `AiFill`). Functions: `supabase/functions/fill-activity/index.ts`, shared `supabase/functions/_shared/` (`common.ts`: CORS, quota, Google search; `link_preview.ts`: official previews, address checks). DB: `consume_api_quota` kind `ai_fill`.
  - Tests: `place_search.test.sql` (30 a day, separate from place searches); `app/test/ai_fill_test.dart` (reading the reply). Tried locally on 2026-10-16: link reading against YouTube, a normal site, Instagram and blocked addresses (TikTok's oEmbed rate-limited this network, so TikTok is untested); end to end through AIML API with a website, a YouTube link and a caption alone, and in the app through to saving with the preview photo. No automated test for the function itself (it needs outside services).

## F5. Sharing into groups and per-group types — Done
- Share from an activity (pick group) or from a group (pick one of your activities, or create one inline).
- Every shared activity has a group type. With a label and no manual pick, it's filed automatically (F6); otherwise the sharer picks a type (can add a new type inline).
- Any member can change an activity's type in the group or remove it from the group.
- Types tab: add, rename, delete (blocked while in use), merge (F6). Shows activity counts.
- UI: `features/activities/share_activity_sheet.dart` (`showShareActivitySheet`), `features/groups/group_activities_tab.dart`, `features/groups/group_types_tab.dart`.
- Data: A `groupActivities`, `sharedIn`, `share`, `changeType`, `unshare`; G `types`, `addType`, `renameType`, `deleteType`; providers `groupActivitiesProvider(groupId)`, `sharedInProvider(activityId)`, `typesProvider(groupId)`.
- DB: `group_activities`, `activity_types`, triggers `group_activity_defaults`, `revert_entries_to_events`.
- Tests: `core_rules.test.sql` (sharing, member type changes, unshare turns plans into events), `labels_and_merges.test.sql` (filing by label).

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
- My activities: text search over name, description, location, label; filters label (multi), sharing (all/private/shared), max budget, has a link, has photos; sort newest/name/cheapest.
- Group activities: text search over name, description, location, group type; filters type (multi), max budget, added by, has a link, has photos; same sorts.
- Budget filter keeps activities whose range overlaps `[0, max]` or that have no price (`Activity.fitsBudget`).
- "Has link" / "Has photos" chips (#53) keep activities with a non-blank link (`Activity.hasLink`) or at least one photo (`Activity.hasPhotos`). All filters combine (AND); Clear resets them.
- **Near…** (#94) on My activities, the group Activities tab and the Add to schedule picker: activities within 1, 2, 5, 10 or 20 km (straight line) of **your location** (device permission; used on the device only, never sent or stored) or a **searched place** (the Location field's Google search). Lists show only those within reach, nearest first, with the distance on each card ("550 m", "4.3 km"); the picker keeps every activity but lists the nearby ones first with their distance. Activities without a picked Google place can't be measured: a note counts them ("2 activities have no map location") and opens a list to fix them. Owner's choices (2026-10-19): distance only (no opening hours or travel time); "a certain day" is just planning context.
  - Coordinates come from the `place-coordinates` Edge Function: Google Place Details (location only), cached by place ID for at most 30 days (Google's limit; a daily `pg_cron` job deletes older ones), 200 lookups per person per day (`place_coords` quota); a cached place costs nothing.
  - UI: `features/activities/near_filter.dart` (`NearFilterChip`, `showNearSheet`, `NearNote`), `ActivityCard.distanceKm`; `PlaceField` takes a `label`/`hint`. Data: `data/geo.dart` (`GeoPoint`, `distanceKm`, `formatDistance`, `NearFilter`, `applyNear`), `places_repository.dart` (`coordinates`, `currentPosition`, `placeCoordinatesProvider`, `placeKey`). Device location: `geolocator` (Android `ACCESS_COARSE_LOCATION`, iOS `NSLocationWhenInUseUsageDescription`).
  - Tests: `app/test/near_filter_test.dart` (distances, wording, filtering); `place_coordinates.test.sql` (no client access, place-ID format, expiry job, quota). Checked in the browser with a searched place and a simulated device location (the preview pane blocks real location; the "not allowed" message was checked too).
- Runs in memory on the loaded list. If groups grow large, move to server-side filtering (#16).
- UI: `activities_page.dart` (`_apply`), `group_activities_tab.dart` (`_apply`), `schedule/entry_editor.dart` (`_whatPicker`).
- Tests: `app/test/activity_filters_test.dart` (`hasLink`, including blank links; `hasPhotos`). The filter rows themselves were checked in the browser.

## F8. Schedules, clash detection, events — Done
- Entries belong to a group; either an activity or an event (title only). Timing: timed (may run past midnight), all-day, or "no date yet" (events only).
- Adding people adds them directly; if anyone is busy the planner sees a clash dialog listing who has what (all-day clashes with everything that day, in each person's time zone; other groups' entries show as "Busy"). Proceeding saves with `clash` status for those people, notifies them and logs it.
- **My schedule** (`/schedule`): entries the user is in, across groups, with a **List | Week | Month** switch on every screen size (phones default to List, ≥720 px to Week).
  - List: day-by-day agenda from today (4 weeks, "Show 4 more weeks"). **Show earlier** at the top adds 4 weeks before today each tap, so past plans can be browsed on phones.
  - Week: all-day row + hourly blocks, overlaps side by side, opens at 8am. Phones get single-letter days, a slim hour gutter and title-only blocks.
  - **Drag to reschedule** (#12, wide screens ≥720 px; phones use Change time): drag a timed plan's block to another time or day. It snaps to 15 minutes (`dropStart`, `dragSnapMinutes`) and keeps its length; the target column tints while hovering. Same clash check as Change time (`reschedule_entry`, `confirmClashes`); declining saves nothing and the block stays put. After a move, a "Moved … to …" snackbar offers **Undo** (moves it back, clash-checked again). All-day plans and the continuation of a plan from the day before don't drag.
  - Month: six-week grid with titles; on phones, coloured dots (primary = yours, red = clash).
  - Week/Month have ‹ › Today navigation; tapping a day opens that day's list with "Add". On phone calendars the add button is a small round FAB.
- **Group Schedule tab**: "Ideas · not scheduled yet" events first, then the next 8 weeks of the group's entries (all members' plans; the user's highlighted). **Show earlier** sits above the dated list, as in My schedule.
- **Past plans are muted** wherever plans are listed (`EntryTile`): an all-day plan once its day is behind you, a timed one once it has ended, even earlier today (`ScheduleEntry.isPastAt`). Past day headings are grey, and headings say "Yesterday" and show the year for other years. Past plans still open normally.
- **Entry detail sheet**: when, who (clash badges), change time (re-checks clashes), add people (checks new people), replace event with activity / swap activity, rename event, view activity, leave, remove for everyone, history. If the user has a clash: "Keep both" or "Leave this".
- **Add to schedule** from: My schedule FAB, group Schedule tab, and the activity detail page (per group).
- **Repeating plans** (#17): when adding a dated plan, **Repeat** (Doesn't repeat / Weekly / Every 2 weeks / Monthly) and **Until** (default 3 months, at most a year after the first date). Every date is an ordinary plan linked to a series (`series_id`), so clash checks, participants, history, live updates and drag work per date.
  - Dates repeat at the same wall-clock time in the planner's time zone (7pm stays 7pm across daylight saving). Monthly repeats on the same day of the month; the 31st falls back to a shorter month's last day. At least two dates.
  - Saving checks every date for clashes and lists them in one dialog; going ahead marks only the clashing dates. Each person gets **one** notification for the series ("alice added you to Game night", "Repeats weekly until 6 Nov · Crew · clashes 2 times").
  - A repeat icon on plan tiles; the detail sheet shows "Repeats weekly until 6 Nov" with **Extend** (a new end date, at most a year from today; new dates copy the last one and are clash-checked).
  - Change time, drag, add people, swap/replace activity, rename, leave and remove for everyone ask **This date only** or **This and later dates** (earlier dates stay as they are). Moving later dates shifts each by the same amount and sets the new length; Undo after a drag uses the same choice.
  - Group history shows one line per action across the series, with "· on N dates".
- Times, calendar days and "today" use the profile's time zone (see F11); all-day clash checks use each participant's zone.
- UI: `features/schedule/my_schedule_page.dart` (`_move`, `_reschedule`; both take an `EditScope`), `calendar_views.dart` (`WeekView` with `onMove`, `dropStart`, `MonthView`), `schedule_widgets.dart` (`EntryTile`, `AgendaList`, `ShowEarlierButton`, `agendaStepWeeks`, `confirmClashes`, `chooseScope`, time labels and `dayHeading`), `entry_editor.dart` (`showEntryEditor`, `showRescheduleEditor` with a scope; Repeat and Until fields), `entry_detail_sheet.dart` (`showEntryDetail`, `describeEntryChange`, repeat row with Extend); `features/groups/group_schedule_tab.dart`.
- Data: `data/schedule_models.dart` (`ScheduleEntry` with `seriesId`/`seriesFreq`/`seriesUntil`, `ScheduleParticipant`, `ScheduleClash`, `ScheduleResult`, `EntryTiming`, `RepeatFreq`, `EditScope`, `repeatLabel`, date helpers), `data/schedule_repository.dart` (`list`, `create`, `createSeries`, `extendSeries`, `reschedule`, `addParticipants`, `setActivity`, `rename`, `delete`, `leave` (the last six take `scope:`), `acknowledgeClash`, `history`; `queryAroundEntry` builds a schedule window around one plan so its detail sheet can be opened from elsewhere, used by notifications and group history); providers `scheduleProvider(ScheduleQuery)`, `entryHistoryProvider(id)`; helper `invalidateSchedule`.
- DB: `schedule_entries`, `schedule_participants`, `schedule_series`, `list_schedule`, `create_schedule_entry`, `reschedule_entry`, `add_entry_participants`, `find_clashes`, `apply_participants`, `entry_range`; for repeating plans `create_schedule_series`, `extend_series`, `reschedule_following`, `add_participants_following`, `rename_following`, `set_activity_following`, `delete_following`, `leave_following`.
- Tests: `core_rules.test.sql` (clash, force, acknowledge, reschedule, replace event, delete → event), `list_schedule.test.sql` (personal vs group view, windows, time zones, privacy).
- Tests: also `recurring_plans.test.sql` (limits, clashes and force, daylight saving, one notification, monthly clamp, every "this and later" action, extend, history grouping), `app/test/recurring_plans_test.dart` (labels, notification text, history suffix, the scope question), `app/test/past_plans_test.dart` (when a plan counts as past; day headings), `app/test/drag_reschedule_test.dart` (snapping and clamping; dragging down two hours and to the next day on a wide screen; a tiny drag does nothing; no dragging on phones).

## F14. Itinerary export and calendars — Done (#96, #97)
- Group page → Schedule tab → export icon (`Icons.ios_share`, "Export itinerary") opens a sheet: **days** (This weekend, Next 7 days, or Choose dates…, at most 62) and **format**. Plans with no date aren't included. Owner's choices (2026-10-19): a group's plans for a date range; these four formats (the calendar file came with #97); the PDF with days as columns.
  - **Excel itinerary** (.xlsx): a *Summary* sheet (plans and estimated cost per person per day and in total, by currency, from the activities' price ranges) and one sheet per day with plans: Time, Plan, Type, Location, Map (a `HYPERLINK` to Google Maps, the exact place when picked), Price, Who's going, Link, Description, Notes (empty, for the group).
  - **PDF timetable**: A4 landscape, up to 7 days per page as columns, hours down the side (at least 8 AM–8 PM, widened to fit), each plan a coloured block (one colour per activity, so it keeps its colour across days; events by title; no grey) with title, time and short place (lines that don't fit whole are left out, #99); all-day plans in a band at the top; overlapping plans side by side; bigger text when there are fewer days. Fixed print colours, not the app theme.
  - **Image** (.png): the same timetable as one picture (weeks stacked).
  - **Calendar file** (.ics, #97): the plans as iCalendar events for Google Calendar (Settings → Import on a computer), Apple Calendar or Outlook. Timed plans in UTC, all-day plans as date events; each plan's ID is its UID, so calendars that support it update instead of duplicating on re-import; a plan across midnight is one event. Notes: who's going, price, the activity's link and description, and a link to the group in EasyPlan.
  - **Text for a chat**: a day-by-day summary copied to the clipboard ("📅 Crew · Sat 24 – Sun 25 Oct 2026", then "*Sat 24 Oct*", "• 9:30 AM – 12:00 PM Gardens by the Bay — Marina Gardens Drive, Singapore (SGD 0–32)").
  - Places skip a first part that only repeats the plan's name (`ItineraryItem.placeDetail`, `shortPlace`; #99): "Gardens by the Bay — Marina Gardens Drive, Singapore", not "Gardens by the Bay — Gardens by the Bay, …". Excel and calendar files keep the full location.
  - Times are in the profile's time zone and worded like the schedule ("From 11:00 PM" / "Until 1:00 AM" across midnight). On the web files download; on phones they open the share sheet.
- Everything is built in the app from `list_schedule` and the group's activities; no new server parts or costs.
- UI: `features/groups/itinerary_export_sheet.dart` (`showItineraryExport`, `ItineraryFormat`, `comingWeekend`, `itineraryFileName`), `features/schedule/itinerary_timetable.dart` (`timetablePages`, `timetablePng`, `timetablePdf`; drawn with `dart:ui`, the PDF holds the page images), export icon in `group_schedule_tab.dart`. Data: `data/itinerary.dart` (`Itinerary.build`, `chatText`, `toExcel`, `costOf`; `ItineraryItem.timeLabel`, `minutesOn`), `data/export/save_file.dart` (download on web via `package:web`, share sheet elsewhere via `share_plus`). Packages: `excel`, `pdf`, `share_plus`, `web`.
- Tests: `app/test/itinerary_test.dart` (days and order, multi-day plans, details, costs, chat text, Excel sheets and links read back, empty range, weekend preset, file names, place names that repeat the plan name (#99)). Checked in the browser with test plans: the PNG looked right (overlaps, all-day band), the PDF and Excel came out as valid files, the chat text was copied; the Excel file also passed a zip integrity check and was read back with Python.
- **Add to Google Calendar** (#97) on a plan's detail sheet (plans with a date): opens Google Calendar's new-event page with the title, time (UTC), location and the same notes filled in; the person saves it there. No Google permission; copies don't follow later changes (owner's choice: no live subscription or sync for now).
  - `data/calendar_export.dart` (`googleCalendarUri`, `toIcs`, `calendarNotes`, `planLink`); `ItineraryItem.from(entry, groupActivity)` builds a plan's details for both. `_addToGoogleCalendar` in `features/schedule/entry_detail_sheet.dart`.
  - Tests: `app/test/calendar_export_test.dart` (UTC times, all-day range, no link without a date, notes, .ics structure, one event per plan, escaping, 75-byte line folding). Checked in the browser: the button opened the right Google Calendar address, and the exported .ics had both events.
- Not yet: exporting your own schedule across groups or hand-picked plans; a live calendar subscription.

## F11. Profiles — Done
- **Own profile** (`/profile`, a navigation tab): picture (tap → choose photo / remove), display name, @username, bio ("Add a bio" when empty), stats (groups, activities, upcoming plans; each taps through), your groups, account (email with change → confirmation links to **both** the current and new address (Supabase secure email change; both must be opened; the snackbar, the tile's subtitle and the email itself say so; template `supabase/templates/email_change.html`; **Cancel change** while pending (`cancel_email_change`); the tile reads the user from the server and again on app resume, so a change confirmed from the mail app shows without signing in again), password change with current-password check, time zone with **Change**), **Sign out** (moved here from other screens).
- **Edit profile**: display name (≤50, checked by the database), username with live "Available / That username is taken / invalid" check (same rules as sign-up), bio (≤160).
- **Other people** (`/people/:id`): picture, name, @username, bio, "Groups you share". Opened by tapping someone in a group's Members tab or a plan's "Going" list. Stats are only shown on your own profile.
- **Avatars everywhere people are listed**: members, invite search, plan participants (`UserAvatar`, initial-letter fallback).
- Username changes don't break history: logs store user ids and resolve names when shown.
- UI: `features/profile/profile_page.dart` (`ProfilePage`, `PersonPage`, `_ChangePasswordDialog`, `_TimezoneTile`), `edit_profile_page.dart` (`showEditProfile`), `timezone_picker.dart` (`showTimezonePicker`), `widgets/user_avatar.dart`.
- Clock: `data/app_clock.dart` — `AppClock` (display zone; `now`, `today`, `inZone`, `at`, `offsetLabel`, `differsFromDevice`), `formatOffset`, `TimezoneController`/`timezoneProvider`, `timezoneOptionsProvider`, `localTimezone()`. Uses `package:timezone` with the full data set (`latest_all`, includes aliases such as Asia/Kuala_Lumpur). Unit tests: `app/test/app_clock_test.dart`.
- Data: `data/profile_repository.dart` (`profile`, `update`, `usernameAvailable`, `setAvatar`, `removeAvatar`, `avatarUrl`, `sharedGroups`, `myStats`, `myTimezone`, `setTimezone`, `timezones`, `changeEmail`, `account`, `cancelEmailChange`, `changePassword`); providers `profileProvider(id)`, `accountProvider` (server copy of the signed-in user; the email tile re-reads it on app resume), `sharedGroupsProvider(id)`, `myStatsProvider`, `avatarUrlProvider(path)`. `Profile` now has `avatarPath`, `bio`, `timezone` and a `columns` select string.
- DB: `profiles.bio`, bucket `avatars`, `shared_groups`, `my_profile_stats`; `list_schedule` participants include `avatar_path`.
- Tests: `timezones.test.sql` (sign-up zone, validation, picker list); `cancel_email_change.test.sql` (own change cleared incl. tokens, others untouched, anon refused); `profiles.test.sql` (own edits, taken/invalid username, bio limit, can't edit others, shared groups, stats, avatar folder rules); `display_name_length.test.sql` (long sign-up name cut to 50, blank → null, trimmed; 50 multi-byte characters saved, 51 refused with 23514).
- **Time zone**: set at sign-up from the device; changeable on the profile via a searchable picker (city · region · current UTC offset, search by name or offset like "+8"; "Use this device's time zone" shortcut). The whole app shows times in this zone (`AppClock`, `timezoneProvider`); My schedule shows a note when it differs from the device.
- Gaps: avatar picking untested in automation (file picker); email change confirmation goes to Mailpit locally (http://127.0.0.1:54324).

## F12. Account lifecycle and release readiness — Done
- **Forgot password**: sign-in screen → email → `resetPasswordForEmail(redirectTo: <APP_URL>/reset-password)` → link opens `ResetPasswordPage` (waits for the PKCE code exchange, then "Choose a new password"; "link expired" after 10 s). The router sends any `passwordRecovery` session to `/reset-password`.
- **Change password** (Profile → Password): asks for the current password; a **"No password yet, or forgot it? Email me a link"** button sends the same reset link to the account's own email, which is how a Google account (#87) sets its first password.
- **Delete account**: Profile → Delete account (type username) → removes storage files (`my_storage_files`) → `delete_my_account` → local sign-out. DB: activities deleted (unshared first so plans become events), auth user deleted (cascades), groups handed over by `hand_over_ownership` trigger (also on normal "leave"), "who did it" columns `on delete set null`.
- **Privacy policy**: `app/web/privacy.html` (last updated 20 October 2026; contact easyplanhehe@gmail.com; names Supabase (Singapore), Netlify, Resend (Japan), Google Maps Platform (location search), Google sign-in (what Google shares; photo copied only if agreed) and AIML API / Anthropic (Fill from link)), linked from sign-up and the profile (`AppConfig.privacyPolicyUrl`).
- **Auth emails** (sign-up confirmation, password reset, email change): Supabase custom SMTP through Resend, from `no-reply@easyplanhehe.online`; set up in the Supabase dashboard, not in the repo (`docs/deployment.md` §1). EasyPlan wording from `supabase/templates/` (`confirmation.html`, `recovery.html`, `email_change.html`; cloud copies pasted by hand). Locally they still go to Mailpit.
- **Identity**: EasyPlan, `com.kangjin.easyplan` (Android namespace/applicationId, iOS bundle ID), web manifest/title, placeholder icon (`app/assets/icon/generate_icon.py` → `flutter_launcher_icons`).
- **Config**: `AppConfig` reads `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`, `APP_URL` (`--dart-define-from-file=env/prod.json`); release builds against the local backend show a "no server configured" screen. Path URL strategy; invite links `AppConfig.inviteLink(token)` = `<APP_URL>/join/<token>`.
- **Build/deploy**: `deploy-web` job in `.github/workflows/ci.yml` (manual run on `main` only, after CI; settings from GitHub secrets/variables), `scripts/build.sh web|android|ios`, `netlify.toml`, `app/web/_redirects`, Android release signing from `key.properties`, Android App Links intent filter (`appLinkHost` placeholder from `APP_URL`), `.well-known` templates in `app/deploy/well-known/`. Guide: `docs/deployment.md`.
- UI: `features/auth/auth_page.dart` (`_forgotPassword`, privacy link), `features/auth/reset_password_page.dart`, `features/profile/profile_page.dart` (`_DeleteAccountDialog`, privacy link). Data: `ProfileRepository.deleteAccount`.
- Tests: `delete_account.test.sql` (hand-over on leave, deletion cascade, events kept, others untouched, history kept). Forgot-password and deletion were exercised end to end in the browser with a throwaway local account.
- **Deployed:** the web app is live at https://easyplan-hehe.netlify.app against the Supabase cloud project. Merging to `main` doesn't deploy; the owner asks for a deploy, which runs CI manually on `main` (`deploy-web` job; `docs/deployment.md` → Deploying the web app).
- Not done yet: store builds (#13 Android, #14 iOS) and a designed icon (#15). iOS Associated Domains must be added in Xcode; `.well-known` files need the Play signing SHA-256 and Apple Team ID; store listings are manual.

## F9. Notifications — Done (screen, live badge; push #18 to come)
- Kinds written by the database: `group_invitation` (on invite), `added_to_entry` and `schedule_clash` (when a planner adds you; clash when you were busy), `added_to_series` (added to a repeating plan, or its dates extended: one per series, not per date; moving later dates sends at most one `schedule_clash` per person), `group_deleted` (to members and people in its plans) and `ownership_transferred` (to the new owner; taps through to the group).
- **Alerts tab** (`/notifications`, 4th of five tabs; the page is titled "Notifications"): newest first, unread highlighted with a dot. Text per kind: "alice invited you to Hikers" (+ pending/joined/declined/cancelled; tapping a cancelled one says so instead of opening Groups), "alice added you to Dinner" (group · when), "Dinner clashes with 1 of your plans" (who added you anyway · when). Deleted users read as "Someone"; plans or groups you can no longer see read as "a plan" / "a group".
- Tap: invitation → Groups (respond there); plan → its detail sheet (Keep both / Leave for clashes), opened on a schedule window around the plan; "You're no longer in this plan" if it's hidden.
- Opening the page marks everything read and clears the badge. Items that were unread when the visit saw them stay highlighted until you leave the page, even though marking read makes the list refetch live (#58); ones arriving while it's open are highlighted and marked read too. Pull to refresh.
- **Badge** on the Alerts tab (bottom bar and rail): unread count, "99+" cap. Live: goes up within a second or two of a new notification (F13); nothing pops up (owner's choice). Also re-counted on every navigation, when the app returns to the foreground, and on refresh, as a safety net.
- UI: `features/notifications/notifications_page.dart` (`NotificationsPage`, `describeNotification`, `planWhen`, `timeAgo`), `features/home/home_shell.dart` (tab + `Badge`).
- Data: `data/notifications_repository.dart` (`list`, `unreadCount`, `markAllRead`; `notificationsProvider`, `unreadCountProvider`); model `AppNotification` in `data/models.dart`.
- DB: `notifications`, `list_notifications` (resolves names and plan details; hides plan/group details the caller can no longer see).
- Tests: `notifications.test.sql` (own only, names and order, clash count, current invitation status, limit, mark read own only, details hidden after leaving, anon refused); `app/test/notifications_page_test.dart` (highlights survive the refetch after marking read; new arrivals; marks once), `app/test/notifications_text_test.dart` (wording, time ago).

## F13. Live updates (realtime) — Done
- Other people's changes show up on open screens within a second or two, silently (no banners; owner's choice): group Activities, Schedule, Members and Types tabs, group history, My schedule, My activities, activity pages, plan sheets, the Groups list and invitations, the Alerts list and badge, profile stats.
- **How:** database triggers send a "changed" message naming only the table to private Realtime channels. The app re-fetches through RLS, so a message reveals nothing.
  - **Topics:** `group:<id>` for anything inside a group; `user:<id>` for one person's notifications, invitations, plans, group memberships and own activities.
  - **Who can listen** is a `realtime.messages` policy: members for group topics, the user for their own topic. Nobody can send; only the triggers publish.
- One listener for the whole signed-in session (`liveUpdatesProvider`, watched by `HomeShell`). It joins `user:<me>` plus one channel per group, and joins or leaves group channels as the group list changes. It closes everything on sign-out.
- **No fetch storms:**
  - The database sends one message per topic and table per transaction (e.g. a plan with five people is one message per topic).
  - The app collects messages for 400 ms and invalidates each affected provider once.
  - Only providers that are on screen actually re-fetch.
- **After a dropped connection:** when a channel rejoins, everything for that topic is re-fetched, since messages sent meanwhile are lost.
- Group history: a live update resets to the first page, so older pages loaded before don't leave a gap.
- Plan changes also go to each participant's own topic, so someone who left the group but is still on one of its plans keeps getting updates about it.
- Your own changes come back as messages too, and cause one extra re-fetch. That's on purpose: skipping them would stop your other devices and tabs from updating.
- Data: `data/realtime_repository.dart` (`RealtimeRepository.listen`, `liveUpdatesProvider`, `providersAffectedBy` maps topic + table to providers, `liveUpdateDelay`).
- DB: `broadcast_change` trigger on `groups`, `group_members`, `group_invitations`, `group_invite_links`, `group_activities`, `activities`, `activity_photos`, `activity_types`, `type_merges`, `schedule_entries`, `schedule_participants`, `notifications`; policy `easyplan_listen` on `realtime.messages`.
- Tests: `realtime.test.sql` (who gets which message, payload has no row data, one message per transaction, members/self only can listen, nobody can send, anon and former members can't listen); `app/test/realtime_refresh_test.dart` (which providers refresh).
- **When adding a table a screen shows:** add a `broadcast_change` trigger for it and a case in `providersAffectedBy`, or that screen won't update live.

## F10. Change log — Done
- Every insert/update/delete on core tables is logged by trigger with actor and before/after.
- Shown on the activity detail page, the schedule entry sheet, and the group's **History** page.
- **Group history** (`/groups/:id/history`, group page ⋮ → History): who did what in the group, newest first, under day headings ("Today", "Yesterday", dates), 50 at a time with **Show older**; pull to refresh. Lists:
  - shares, removals and type changes;
  - types added, renamed and deleted; merges (including existing rules re-pointed by a later merge, #52) and undone merges;
  - plans planned, retimed, renamed, removed or swapped (one line for the same action on several dates of a repeating plan, "· on N dates"); events replaced (named as they were) or turned back into events; people added to or leaving plans; clash overrides and clashes cleared;
  - members joining (or creating the group), leaving or being removed;
  - invite links created and revoked; people invited, invitations declined or cancelled (accepting shows as "joined"; link codes are never shown);
  - edits and photo changes to an activity **made while it was shared in the group**, worked out from the log's own share and removal lines, so they stay listed after the activity leaves the group. Edits from before it was shared (or while it was out of the group) stay private, and the owner's label never shows.
- **Tap a line** to open what it's about (chevron shown): activity lines open the activity while you can still see it; plan and participant lines open the plan's detail sheet while the plan exists; member lines open the person's profile. Type, merge, invite-link and invitation lines don't open anything.
- Members see the group's whole history, including from before they joined. Former members and outsiders see nothing.
- Names follow visibility: a deleted activity reads "an activity", a plan with no name left reads "a plan", a deleted account reads "a deleted user". Joining or leaving by yourself vs. being added or removed is told apart by id, so it still reads right after an account is deleted.
- Left out on purpose (bookkeeping, not a person's action): edits that only changed the owner's label, a label being cleared from a share, and participants being marked as clashing (the clash override line covers it).
- UI: `features/groups/group_history_page.dart` (`GroupHistoryPage`, `describeGroupChange`, `historyDayHeading`); menu item in `group_page.dart`; route in `router.dart`. Plans open through `queryAroundEntry` (`schedule_repository.dart`), shared with the notifications page.
- Data: G `history(groupId, {beforeId, limit})`, `historyPageSize`; provider `groupHistoryProvider(groupId)` (first page; later pages are kept by the page). `ChangeEntry.fromGroupHistory` in `models.dart`.
- DB: `list_group_history`.
- Tests: `type_merge_history.test.sql` (a re-pointed merge rule is logged with old and new target and shows as "merged X into Y"; a no-op re-merge logs nothing); `group_history.test.sql` (whole history for members incl. before joining, names, edits only while shared, including out-and-back-in and after removal, label never shown, merges, plan id and timing, paging, outsiders and former members see nothing, deleted activity names hidden); `app/test/group_history_text_test.dart` (wording).
- Note: plan lines use the plan's current name (like the rest of the app), except "planned the event" and "replaced the event", which name the event as it was.

---

## Backlog

The backlog lives in **GitHub Issues**: https://github.com/kangjin97/project1.0/issues, shown on the **EasyPlan project board** (https://github.com/users/kangjin97/projects/3; Todo → In Progress → Done) (labels `bug`, `feature`, `chore`, `documentation`, `priority:high`). This file describes what's built; issues track what's next. When a feature ships, update its section here and close the issue from the PR ("Closes #n").

Open at the time of writing:

| Issue | Feature | Label |
|---|---|---|
| #5 Smoke-test the live web app on a phone | F12 | chore, priority:high |
| #13 Android: update the toolchain and publish a Play internal test build | F12 | chore |
| #14 iOS: update the toolchain and publish a TestFlight build | F12 | chore |
| #15 Replace the placeholder app icon | F12 | chore |
| #16 Server-side search and filters for large groups | F7 | feature |
| #18 Push notifications on phones | F9 | feature (v2) |
| #49 Test live updates on two phones against the live site | F13 | chore |
| #88 Sign in with Facebook | F1 | feature |

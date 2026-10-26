# Endpoints reference

Every backend call the app makes, plus the RPCs the database exposes but the app doesn't use yet. All calls go through supabase-dart; "REST" means PostgREST on `/rest/v1/<table>`. RLS applies to every call as the signed-in user.

**Conventions**
- "Who" is enforced by the database (RLS, grants or the RPC body), not by the app.
- `P0001 "<msg>"` means the RPC raises that message; the app shows it via `friendlyError`.
- Dart methods are in `app/lib/data/groups_repository.dart` (G), `activities_repository.dart` (A), `schedule_repository.dart` (S), `profile_repository.dart` (P), `auth_repository.dart` (Au), `notifications_repository.dart` (N) and `realtime_repository.dart` (R), `places_repository.dart` (Pl) and `ai_fill_repository.dart` (AI); `friendlyError` is in `groups_repository.dart`.
- `<Profile.columns>` is `id, username, display_name, avatar_path` (`data/models.dart`); embedded profiles use it.
- Each repository file ends with its Riverpod providers (`FutureProvider` / `.family`, keyed by id) and invalidation helpers (`invalidateActivity`, `invalidateLabels`, `invalidateSchedule`). Providers are named after the method, e.g. `myGroupsProvider`, `membersProvider(groupId)`, `scheduleProvider(query)`; only ones that differ are listed below.

---

## Auth

| Dart | Call | Notes |
|---|---|---|
| `AuthPage._submit` (sign up): P `usernameAvailable`, then Au `signUp(email, password, username, displayName, timezone)` | `rpc username_available(p_username text) → bool`, then `auth.signUp(email, password, data: {username, display_name, timezone})` | Callable signed-out. Trigger creates `profiles` row; username lower-cased; display name trimmed, blank → null, cut to 50 characters (the sign-up field also stops at 50). Duplicate username at insert → sign-up fails. Returns true when the account must be confirmed by email (no session). A used email throws `AuthException(alreadyRegisteredMessage)`: locally Auth answers 422 `user_already_exists`; on the cloud (confirmation on) it answers with a user whose `identities` is empty. |
| `AuthPage._submit` (sign in): Au `signIn(login, password)` with an email (`isEmailLogin`: has an @) | `auth.signInWithPassword(email, password)` | Email trimmed. 400 `invalid_credentials` → `wrongPasswordMessage` (mentions Google and Forgot password). |
| `AuthPage._submit` (sign in with a username): Au `signIn(login, password)` | `functions.invoke('username-sign-in', body: {username, password})` → `{refresh_token}`, then `auth.setSession(refresh_token)` | **#107.** Callable signed-out (`verify_jwt = false`). The function lower-cases and trims the username; anything not matching `^[a-z0-9_]{3,30}$` or an empty password → **400** `invalid_credentials`. It calls `email_for_username` (service role): **429** `too_many_tries` "Too many tries. Wait 15 minutes, or sign in with your email." after 10 failures in 15 minutes; no such user → `record_username_sign_in_failure`, **400** `invalid_credentials`. Then Auth's password grant with the found email: success → `clear_username_sign_in_failures`, **200** `{refresh_token}` (no email, no other user data); wrong password → failure recorded, **400** `invalid_credentials`; unconfirmed email → **400** `email_not_confirmed` "Confirm your email first…"; Auth rate limit → **429** `rate_limited`; anything else → **502**. The app maps `invalid_credentials` to `wrongPasswordMessage` and shows the other messages as they are. **405** not a POST. |
| `AuthPage._google`: Au `signInWithGoogle({returnTo})` | `auth.signInWithOAuth(OAuthProvider.google, redirectTo: '<APP_URL>/?next=<returnTo>')` | Leaves for Google; comes back to the root with `code` and `next` (allowed by `<APP_URL>/**`). The router follows `next` only if it's a path in the app (`safeNext`). First sign-in creates the profile with a placeholder username and `needs_username = true`. |
| Au `googlePhotoUrl` | `auth.currentUser.userMetadata['avatar_url' / 'picture']` | Google's picture URL at 256 px, or null. |
| Router `_AuthRefresh.needsUsername`: P `needsUsername()` | REST `GET profiles?select=needs_username&id=eq.<me>` | True until a Google user has picked a username; read once per user. |
| `WelcomePage._load`: P `profile(me)`, P `usernameAvailable` per candidate | as for profiles | Fills the first free suggestion from `usernameCandidates(usernameBase(displayName, email))`; offers Au `googlePhotoUrl` only when `avatar_path` is null. |
| `WelcomePage._continue`: P `usernameAvailable`, `update`, `TimezoneController.change(deviceZone)`, P `copyAvatarFrom(url)` | as for Edit profile; `copyAvatarFrom` downloads the picture (Google allows cross-origin downloads) and calls `setAvatar` | Writing `username` clears `needs_username` (trigger `profiles_username_chosen`); clients can't write the flag (42501). A failed photo copy only shows a note. |
| `ProfilePage` | `auth.signOut()` | |

## User search

| Dart | Call | Who | Notes |
|---|---|---|---|
| G `searchUsers(q)` (no `@`) | REST `GET profiles?select=<Profile.columns>&username=ilike.<prefix>*&id=neq.<me>&limit=10` | signed in | Query stripped to `[a-z0-9_]`, `_` escaped. Trimmed query under 2 characters (checked before stripping, for both rows) returns `[]` without a call. |
| G `searchUsers(q)` (has `@`) | `rpc find_user_by_email(p_email text) → setof profiles` | signed in | Exact, case-insensitive. Under 2 characters returns `[]` without a call. |

## Groups

| Dart | Call | Who | Errors / side effects |
|---|---|---|---|
| G `myGroups()` | REST `GET group_members?select=group_id&user_id=eq.<me>` then `GET groups?select=id,name,group_members(count)&id=in.(...)&order=created_at.asc` | members | |
| G `group(id)` | REST `GET groups?select=id,name,group_members(count)&id=eq.<id>` (single) | members, pending invitee, or its creator | |
| G `createGroup(name)` | REST `POST groups {name}` → `id` | signed in | Trigger: creator → owner; seeds types Food/Outdoors/Entertainment/Other. |
| G `renameGroup(id, name)` | REST `PATCH groups?id=eq {name}` | owner | Other members' updates match no rows (RLS), so nothing changes and no error is raised. Hidden in the menu for other members. |
| G `leaveGroup(id)` | REST `DELETE group_members?group_id&user_id=<me>` | self | If you were the owner, the longest-standing member becomes owner; an empty group is deleted. |
| G `members(groupId)` | REST `GET group_members?select=role,profiles(<Profile.columns>)&group_id=eq&order=joined_at.asc` | members | |
| G `removeMember(groupId, userId)` | REST `DELETE group_members?...` | owner | |
| G `deletionSummary(groupId)` | `rpc group_deletion_summary(p_group uuid) → [{members, upcoming_plans, ideas}]` | owner | 42501 otherwise. Upcoming = ends after now, or all-day from today in the caller's zone; ideas = no date. |
| G `deleteGroup(groupId, typedName)` | `rpc delete_group(p_group uuid, p_confirm_name text)` | owner | 42501 otherwise; P0001 "type the group's name to confirm" unless the name matches (case and outer spaces ignored). Notifies members and people in its plans (`group_deleted`), then deletes the group with its plans, types, invites. Activities stay. Clients can't `DELETE groups` directly. |
| G `transferOwnership(groupId, userId)` | `rpc transfer_ownership(p_group uuid, p_new_owner uuid)` | owner | 42501 otherwise; P0001 "you already own this group" / "they're not a member of this group". Swaps roles, logs `group_member` `updated` `{role: owner}` in the change log, notifies the new owner (`ownership_transferred`). |
| G `createInviteLink` → `AppConfig.inviteLink(token)` | — | — | Shared link is `<APP_URL>/join/<token>`. |

## Invites

| Dart | Call | Who | Errors / side effects |
|---|---|---|---|
| G `invite(groupId, userId)` | REST `POST group_invitations {group_id, invitee_id}` | members; invitee must not be a member | 23505 if a pending invite exists. Trigger: `group_invitation` notification. |
| G `pendingInvitations()` → `invitationsProvider` | REST `GET group_invitations?select=id,groups(name),inviter:profiles!group_invitations_invited_by_fkey(username)&invitee_id=eq.<me>&status=eq.pending&order=created_at.asc` | invitee | |
| G `respond(id, accept)` | `rpc respond_to_invitation(p_invitation uuid, p_accept bool) → void` | invitee | P0001 "invitation not found". Accept → membership. |
| G `createInviteLink(groupId, {validFor = 7 days})` | REST `POST group_invite_links {group_id, expires_at: now + validFor}` → `token` | members | The server caps `expires_at` at 7 days (a longer or missing one becomes 7 days) and picks the token, ignoring any sent (#82). |
| G `previewLink(token)` | `rpc preview_invite_link(p_token text) → [{group_id, group_name, member_count}]` | signed in | Empty when invalid/expired/revoked/used up. |
| G `joinViaLink(token)` | `rpc join_group_via_link(p_token text) → uuid group_id` | signed in | P0001 "invite link is invalid or expired". Idempotent for existing members. |
| G `inviteLinks(groupId)` → `inviteLinksProvider(groupId)` | REST `GET group_invite_links?select=<InviteLink.columns>&group_id=eq&revoked_at=is.null&order=created_at.desc` | members | `InviteLink.columns` = `id, token, created_at, expires_at, max_uses, use_count, creator:profiles!group_invite_links_created_by_fkey(username)`. Expired and used-up links are filtered out on screen (`InviteLink.isActiveAt`). |
| G `revokeInviteLink(id)` | REST `PATCH group_invite_links?id=eq {revoked_at}` | members | The `group_invite_links_guard_revoke` trigger sets `revoked_at` to the server's `now()`. Changing it again raises P0001 "this invite link is already revoked". Logged and broadcast to the group. |
| G `sentInvitations(groupId)` → `sentInvitationsProvider(groupId)` | REST `GET group_invitations?select=<SentInvitation.columns>&group_id=eq&status=eq.pending&order=created_at.asc` | members | `SentInvitation.columns` = `id, created_at, invitee:profiles!group_invitations_invitee_id_fkey(<Profile.columns>), inviter:profiles!group_invitations_invited_by_fkey(username)`. |
| G `cancelInvitation(id)` | `rpc cancel_invitation(p_invitation uuid) → void` | members of the invitation's group | P0001 "invitation not found" (not pending, not a member, or unknown). Sets status `cancelled` and `responded_at`; the invitee's `group_invitation` notification then shows `invitation_status = 'cancelled'`. Logged; broadcast to the invitee and the group. |

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
| A `previewType(groupId, label)` → `typePreviewProvider((groupId, label))` | `rpc preview_group_type(p_group uuid, p_name text) → [{type_id, type_name, merged, is_new}]` | members | Read-only. `type_id` null when `is_new`. P0001 "not a member of this group". |

## Activities

Select string `Activity.columns` (in `models.dart`):
`id, owner_id, name, description, location, place_id, price_min, price_max, currency, url, created_at, updated_at, personal_type_id, activity_photos(id, storage_path, position), personal_type:personal_types!activities_personal_type_fk(name)`

| Dart | Call | Who | Errors / effects |
|---|---|---|---|
| A `myActivities()` | REST `GET activities?select=<columns>,group_activities(group_id)&owner_id=eq.<me>&deleted_at=is.null&order=created_at.desc` | owner | `group_activities` length → `sharedGroupCount` (only groups the user is in). |
| A `activity(id)` | REST `GET activities?select=<columns>&id=eq` (maybeSingle) | owner or member of a sharing group | null if deleted / not visible. `personal_type` is null for non-owners (RLS). |
| A `create(input)` | REST `POST activities <ActivityInput.toJson()>` → `id` | signed in | `owner_id` defaults to caller. 23503 if `personal_type_id` isn't the caller's label. |
| A `createMany(inputs)` | REST `POST activities [<ActivityInput.toJson()>, …]`, 100 rows per request → count | signed in | Spreadsheet import (#111). Same rules as `create` for every row; a failing request stops the import (earlier batches stay). |
| A `update(id, input)` | REST `PATCH activities?id=eq <fields>` | owner or sharing-group member | Columns granted: name, description, location, place_id, price_min, price_max, currency, url, personal_type_id. Changing `location` without a new `place_id` clears the place (trigger). `personal_type_id` only sent when `setLabel` (owner); non-owner change → 42501. Label change re-files in all groups. |
| A `delete(id)` | `rpc delete_activity(p_activity uuid) → void` | owner | P0001 "only the owner can delete this activity". Unshares everywhere (entries → events), sets `deleted_at`. |

`ActivityInput.toJson()` keys: `name, description, location, place_id, price_min, price_max, currency, url` (`place_id` only with location text, else null) (+ `personal_type_id` when `setLabel`). Name is trimmed; blank description, location and url become null; currency is trimmed and upper-cased (default `SGD`).

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
| A `labelIdsFor(names)` | REST `GET personal_types`, then `POST personal_types {name}` for each missing one | owner | For imports (#111): lower-cased name → id; creates the labels it doesn't find. |

## Photos (Storage)

| Dart | Call | Who | Notes |
|---|---|---|---|
| A `addPhoto(activityId, bytes, {required extension, position = 0})` | `storage.from('activity-photos').uploadBinary('<activityId>/<random>.<ext>')` then REST `POST activity_photos {activity_id, storage_path, position}` | can access activity | Content type png or jpeg. |
| A `removePhoto(photo)` | REST `DELETE activity_photos?id=eq` then `storage.remove([path])` | can access activity | |
| A `photoUrl(path)` | `storage.createSignedUrl(path, 3600)` | can access activity | Cached per path by `photoUrlProvider`. |

## Place search (Edge Function)

Dart: `app/lib/data/places_repository.dart` (Pl). Functions: `supabase/functions/places/index.ts` (suggestions) and `supabase/functions/place-coordinates/index.ts` (coordinates for "Near…"); shared code in `supabase/functions/_shared/`.

| Dart | Call | Who | Notes |
|---|---|---|---|
| Pl `suggest(input)` | `functions.invoke('places', body: {input, languageCode: 'en'})` → `{suggestions: [{placeId, text, mainText, secondaryText}]}` | signed in (`verify_jwt = true`) | Trimmed input under 3 characters returns `[]` without a call; the function also returns `[]` for under 3 or over 200 characters without spending a search. After the key check, each real search calls `consume_api_quota('places')` as the caller (100 a day). Errors come back as `{error}`, which the app shows: **429** "You've used today's place searches…", **503** key not set, **502** Google unavailable, **401** not signed in (also any non-429 error from the quota check), **400** bad JSON, **405** not a POST. Behind it: `POST https://places.googleapis.com/v1/places:autocomplete` with `X-Goog-Api-Key` (secret `GOOGLE_MAPS_API_KEY`) and a field mask of `placeId`, `text`, `structuredFormat`; no session token, no Place Details. |
| — | `rpc consume_api_quota(p_kind text) → void` | signed in | Counts one call of `p_kind` for the caller today (their profile time zone) and raises **PT429** (HTTP 429) "daily limit reached; try again tomorrow" past the limit (`places`: 100, `ai_fill`: 30, `place_coords`: 200). P0001 "unknown quota" for other kinds; 42501 when signed out. The refused call isn't counted. Called by Edge Functions, not by the app. |
| `googleMapsUri(location, placeId:)` | — | — | `https://www.google.com/maps/search/?api=1&query=<location>[&query_place_id=<id>]`: a Maps URL, no key, no cost. |
| Pl `coordinates(placeIds)` → `placeCoordinatesProvider(placeKey(ids))` | `functions.invoke('place-coordinates', body: {placeIds})` (50 per call) → `{coordinates: {<placeId>: {lat, lng}}, error?}` | signed in (`verify_jwt = true`) | **#94.** Invalid IDs are ignored; more than 50 → **400**. Answers from `place_coordinates` when fetched in the last 30 days; otherwise, per missing place, `consume_api_quota('place_coords')` (200 a day) then Google `GET places.googleapis.com/v1/places/<id>` with field mask `location` (same `GOOGLE_MAPS_API_KEY`), cached with the service role. Past the quota it stops and returns what it has with `error` "You've used today's distance lookups…"; without the key, `error` "Distances aren't set up yet."; a place Google can't find is left out. Duplicate IDs are merged. **401** not signed in (also any non-429 error from the quota check), **400** bad JSON, **502** cache unreadable, **405** not a POST. The app doesn't throw: a `FunctionException`'s `{error}` (or "Distances are unavailable right now.") becomes `PlaceCoordinates.error`, which `NearNote` shows. |
| Pl `currentPosition()` | `Geolocator.getCurrentPosition` (low accuracy, 15 s) | device | "Use my location". Asks permission; throws `LocationException` when location is off or not allowed. Never sent anywhere. |

## Itinerary export (no server calls of its own)

`features/groups/itinerary_export_sheet.dart` reads the group with G `group(id)`, the plans with S `list((from, to, groupId, includeUnscheduled: false))` (`list_schedule`) and the details with `groupActivitiesProvider(groupId)`, then builds everything in the app (`data/itinerary.dart`, `data/calendar_export.dart`, `features/schedule/itinerary_timetable.dart`). Nothing is uploaded or saved on the server. "Add to Google Calendar" on a plan reads `groupActivitiesProvider(groupId)` for the details and opens `https://calendar.google.com/calendar/render?action=TEMPLATE&text=…&dates=<UTC start>/<UTC end>&details=…&location=…` (all-day: `YYYYMMDD/YYYYMMDD+1`).

## Fill from link (Edge Function)

Dart: `app/lib/data/ai_fill_repository.dart` (AI). Function: `supabase/functions/fill-activity/index.ts` (shared code in `supabase/functions/_shared/`).

| Dart | Call | Who | Notes |
|---|---|---|---|
| AI `fill({url, caption, screenshot, screenshotType})` | `functions.invoke('fill-activity', body: {url?, caption?, image?: {data: <base64>, mediaType}})` → `{source, fields: {name, description, location, placeId, priceMin, priceMax, currency, url, label: {name, isNew} \| null}, photo: {data, mediaType} \| null}` | signed in (`verify_jwt = true`) | **Order:** <ol><li>Needs a link, caption or screenshot (**400** otherwise, or for bad JSON; a screenshot whose `mediaType` isn't JPEG/PNG/GIF/WebP is ignored).</li><li>**503** "isn't set up yet" when `ANTHROPIC_API_KEY` is missing.</li><li>Reads the link's official preview (`source` `tiktok`/`youtube`/`web`/`meta`/`none`). With nothing usable and no screenshot or caption, returns **422** with a hint, before counting or calling Claude.</li><li>`consume_api_quota('ai_fill')` (30 a day; **429** past it).</li><li>Reads the caller's label names (RLS).</li><li>Calls Claude Haiku 5.5 with structured outputs (secret `ANTHROPIC_API_KEY`; optional `ANTHROPIC_BASE_URL`, now `https://api.aimlapi.com`, the reseller the owner buys credits from); **422** on refusal, no fields, or nothing to do (`found` false and no name).</li><li>Matches `location` with one Google place search (counted as `places`). Skipped, keeping Claude's text, when the location is under 3 characters, `GOOGLE_MAPS_API_KEY` is missing, that quota is used up or can't be checked, or Google fails. When a place matches, `location` becomes Google's "name, area" and `placeId` is set.</li></ol>**The fill is counted before Claude is called**, so a failed Claude call still uses one of the 30. **Other errors:** **503** Claude busy (rate-limited), **502** Claude unavailable (including a wrong key or no credit), **413** screenshot over ~4.5 MB, **401** not signed in (also any non-429 error from the quota check), **405** not a POST. Output is trimmed: name 120, label 40, location 200 characters. **Limits:** caption cut to 4000 characters, link to 2000. `label.isNew` is set by the server: false only when the name matches one of the caller's labels (ignoring case and leading or trailing spaces); the prompt reuses a label only when it truly fits (#79). `photo` is the link's preview image (JPEG/PNG/GIF/WebP ≤ 4 MB), base64. Nothing is saved. |

## History

| Dart | Call | Who |
|---|---|---|
| A `history(activityId)` → `activityHistoryProvider(id)` | REST `GET change_log?select=entity_type,action,actor_id,before,after,created_at&entity_id=eq&entity_type=in.(activity,activity_photo,group_activity)&order=created_at.desc&limit=50`, then `GET profiles?select=id,username&id=in.(actors)` | actor, group members, or activity accessors |

Rendered by `describeChange()` in `activity_detail_page.dart`.

| Dart | Call | Who | Notes |
|---|---|---|---|
| G `history(groupId, {beforeId, limit = 50})` → `groupHistoryProvider(groupId)` (first page) | `rpc list_group_history(p_group uuid, p_before bigint = null, p_limit int = 50) → [{id, created_at, entity_type, entity_id, action, before, after, actor_id, actor_username, subject_name, person_username, from_type_name, to_type_name, event_title, entry_id, entry_all_day, entry_date, entry_start_at, entry_end_at, repeat_count}]` | group members | Newest first (by `id`); limit clamped to 1–200; next page: `p_before` = smallest `id` so far. Empty for non-members. Rows: everything logged with this `group_id`, plus `activity`/`activity_photo` rows made while the activity was shared in the group (the latest `group_activity` `created` row for this group before the edit has no `deleted` row between them, by log `id`; so they stay after it leaves the group). `entry_*` = the plan's id and current timing while it exists (null once removed), so the app can open it. `personal_type_id` is stripped from activity snapshots and `token` from invite-link snapshots. These are left out: label-only edits, `group_activity` `updated` rows, participants marked `clash`, invite-link updates other than revoking (use counts), and accepted invitations (the join is listed). `subject_name` = activity name (only while the caller can access it), plan name, type name or merged label; `person_username` = the member, participant or invitee; `from_type_name`/`to_type_name` = types in this group (null once deleted); `event_title` = the plan's own title. The same action by the same person at the same moment on several dates of one repeating plan (same series, kind, action and person) is one row; `repeat_count` says how many dates (1 otherwise), and the row is the first of them. Rendered by `describeGroupChange()` in `group_history_page.dart`. |

## Profiles

Dart: `app/lib/data/profile_repository.dart` (P). `Profile.columns` = `id, username, display_name, avatar_path`.

| Dart | Call | Who | Notes |
|---|---|---|---|
| P `profile(id)` | REST `GET profiles?select=<columns>,bio,timezone&id=eq` (single) | signed in | Any profile is readable; the UI only links to people you share a group with. |
| P `update(username, displayName, bio)` | REST `PATCH profiles?id=eq.<me> {username, display_name, bio}` | self | Username trimmed and lower-cased; blank display name or bio → null. Display name over 50 characters → 23514 (check; the field stops at 50). 23505 taken username; 23514 invalid username or bio > 160. |
| P `usernameAvailable(name)` | `rpc username_available(p_username)` | anyone | Same RPC as sign-up. |
| P `setAvatar(bytes, {required extension, previousPath})` | `storage.from('avatars').uploadBinary('<me>/<ts>.<ext>')`, `PATCH profiles {avatar_path}`, remove previous file | self | Writes only allowed in your own folder. |
| P `removeAvatar(path)` | `PATCH profiles {avatar_path: null}`, `storage.remove([path])` | self | |
| P `avatarUrl(path)` | `storage.from('avatars').createSignedUrl(path, 3600)` | signed in | Cached per path by `avatarUrlProvider`. |
| P `sharedGroups(userId)` | `rpc shared_groups(p_user uuid) → [{group_id, group_name, member_count}]` | signed in | Groups both you and they are in (all yours when `p_user` = you). |
| P `myStats()` | `rpc my_profile_stats() → [{groups, activities, upcoming_plans}]` | self | Upcoming = participant in an entry ending in the future (all-day: today or later in your time zone). |
| P `changeEmail(email)` | `auth.updateUser(email)` | self | Secure email change: links go to the current and the new address; `newEmail` is set until both are opened. |
| P `account()` | `auth.refreshSession()` → `user` | self | The user as the server has it now (the session's copy dates from sign-in). `accountProvider`; the profile's email tile re-reads it on app resume. |
| P `cancelEmailChange()` | `rpc cancel_email_change()`, then `auth.refreshSession()` | self | Clears the pending change and its tokens; the links already sent stop working. |
| P `deleteAccount()` | `rpc my_storage_files() → [{bucket, path}]`, `storage.remove` per bucket, `rpc delete_my_account()`, `auth.signOut(local)` | self | See F12 for what is deleted or handed over. |
| Au `sendPasswordReset(email)` (`AuthPage._forgotPassword`) | `auth.resetPasswordForEmail(email, redirectTo: <APP_URL>/reset-password)` | anyone | Same message whether or not the email exists. |
| Au `setNewPassword(password)` (`ResetPasswordPage`) | `auth.updateUser(password)` | recovery session | Opened from the email link (PKCE `?code=`). |
| P `changePassword(current, next)` | `auth.signInWithPassword(email, current)` then `auth.updateUser(password)` | self | Re-checks the current password first. A Google account has none: the dialog's "Email me a link" calls Au `sendPasswordReset(<own email>)` instead. |

## Schedules

Dart: `app/lib/data/schedule_repository.dart` (S). Times are sent as UTC ISO strings; dates as `YYYY-MM-DD`.

| Dart | Call | Who | Notes |
|---|---|---|---|
| S `list(query)` | `rpc list_schedule(p_from date, p_to date, p_tz text = 'UTC', p_group uuid = null, p_include_unscheduled bool = false)` | signed in | No group → caller's own entries; with group → whole group (members only), plus "no date yet" events when asked. Returns rows `{id, group_id, group_name, activity_id, activity_name, title, all_day, date, start_at, end_at, created_by, my_status, participants:[{user_id, username, display_name, avatar_path, status}], series_id, series_freq, series_until}` (series fields null for plans that don't repeat). `p_tz` is the app's display zone (the profile zone); dates are inclusive days in that zone. |
| S `create(...)` | `rpc create_schedule_entry` (below) | members | First call without force; on `{status:'clash'}` the UI asks, then retries with `p_force: true`. |
| S `createSeries(...)` | `rpc create_schedule_series` (below) | members | A repeating plan. Same clash flow. |
| S `extendSeries(id, until, {force})` | `rpc extend_series` (below) | members | Same clash flow. |
| S `reschedule(id, timing, {force, scope})` | `rpc reschedule_entry`; `scope: following` → `rpc reschedule_following` | members | Same clash flow. |
| S `addParticipants(id, userIds, {force, scope})` | `rpc add_entry_participants`; following → `rpc add_participants_following` | members | Same clash flow. |
| S `setActivity(id, activityId, {scope})` | REST `PATCH schedule_entries?id=eq {activity_id}`; following → `rpc set_activity_following(p_entry, p_activity_id) → int` | members | Replace event / swap activity; activity must be shared in the group (FK). |
| S `rename(id, title, {scope})` | REST `PATCH schedule_entries?id=eq {title}`; following → `rpc rename_following(p_entry, p_title) → int` | members | |
| S `delete(id, {scope})` | REST `DELETE schedule_entries?id=eq`; following → `rpc delete_following(p_entry) → int` | members | Removes for everyone. |
| S `leave(id, {scope})` | REST `DELETE schedule_participants?entry_id&user_id=<me>`; following → `rpc leave_following(p_entry) → int` | self | `leave_following`: P0001 "you're not in this plan". |
| S `acknowledgeClash(id)` | REST `PATCH schedule_participants?entry_id&user_id=<me> {status:'added'}` | self | |
| S `history(id)` → `entryHistoryProvider(id)` | REST `GET change_log?select=entity_type,action,actor_id,before,after,created_at&entity_id=eq&entity_type=in.(schedule_entry,schedule_participant)&order=created_at.desc&limit=50` + profiles | group members | Rendered by `describeEntryChange()`. |
| P `myTimezone()`, called by `TimezoneController` on sign-in / restored session | REST `GET profiles?select=timezone&id=eq.<me>` (single) | self | Sets the display zone (`timezoneProvider`). |
| P `setTimezone(name)`, via `TimezoneController.change(name)` | REST `PATCH profiles?id=eq.<me> {timezone}` | self | 22023 for unknown zones. Switches the app's display zone and refetches schedules. |
| P `timezones()` → `timezoneOptionsProvider` | `rpc list_timezones() → [{name, region, city, offset_minutes}]` | signed in | Picker list. `timezoneOptionsProvider`, `TimezoneController` and `timezoneProvider` are in `data/app_clock.dart`. |
| Sign-up (`AuthPage`) | `auth.signUp(data: {..., timezone: <device zone>})` | anyone | The trigger stores it on the profile (UTC if unknown). |

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

### Repeating plans (#17)
"Following" means the given date and every later date of its series (by local start in the series' zone); for a plan that doesn't repeat it's just that plan. The `*_following` functions that return `int` return how many plans they changed. All of them except `leave_following` raise P0001 "not a member of this group" for non-members (`leave_following` raises "you're not in this plan").

```
create_schedule_series(
  p_group_id uuid, p_activity_id uuid, p_title text, p_all_day boolean, p_date date,
  p_start_at timestamptz, p_end_at timestamptz,    -- the first date
  p_participant_ids uuid[],
  p_freq text,                                     -- 'weekly' | 'biweekly' | 'monthly'
  p_until date,                                    -- last possible date, <= first date + 1 year
  p_force boolean = false
) → jsonb
```
Returns `{status:'clash', clashes}` (nothing saved; clashes from every date) or `{status:'created', entry_id (first date), series_id, count, clashes}`. Dates repeat at the same wall-clock time in the caller's profile zone; monthly on the 29th–31st falls back to a shorter month's last day. Errors (P0001): "not a member of this group", "choose how often it repeats", "a repeating plan needs a date", "repeats can end at most a year after the first date", "a repeating plan needs at least two dates before it ends", "all participants must be members of the group". Effects: participants per date (`clash` only on the dates that clash), one `added_to_series` notification per person, `clash_override` logs when forced.

`extend_series(p_entry uuid, p_until date, p_force boolean = false) → jsonb` — moves the series' end to `p_until` (later than its current end, at most today + 1 year in the series' zone; P0001 "choose a later end date", "repeats can end at most a year from today") and adds dates copying the last one (title, activity, length, participants). Returns `{status:'clash', clashes}` or `{status:'updated', entry_id (first new date), count, clashes}`; notifies the participants once (`added_to_series`).

`reschedule_following(p_entry, p_all_day, p_date, p_start_at, p_end_at, p_force = false) → jsonb` — the given date gets the new timing; each later date moves by the same wall-clock shift and gets the new length. Clashes with the series' own dates are ignored. Returns `{status:'clash', clashes}` or `{status:'updated', entry_id, count, clashes}`; at most one `schedule_clash` notification per person. P0001 "choose a date" when the new timing is missing.

`add_participants_following(p_entry, p_user_ids uuid[], p_force = false) → jsonb` — adds people to this and later dates (skipping dates they're already on); clash-checks only the new people; one `added_to_series` notification per person. P0001 "all participants must be members of the group".

`rename_following(p_entry, p_title)`, `set_activity_following(p_entry, p_activity_id)`, `delete_following(p_entry)`, `leave_following(p_entry)` → `int`.

### `find_clashes`
`find_clashes(p_user_ids uuid[], p_all_day boolean, p_date date, p_start_at timestamptz, p_end_at timestamptz, p_exclude_entry uuid = null) → table(...)` — only for the caller and users sharing a group with them.

## Notifications

| Dart | Call | Who | Notes |
|---|---|---|---|
| N `list({limit = 50})` → `notificationsProvider` | `rpc list_notifications(p_limit int = 50) → [{id, kind, created_at, read_at, actor_id, actor_name, group_id, group_name, invitation_status, entry_id, entry_title, entry_all_day, entry_date, entry_start_at, entry_end_at, clash_count, series_freq, series_until}]` | self | Newest first; limit clamped to 1–200. `actor_name` is display name or username (null for deleted users). Plan fields are null unless you're still in the plan or its group; `group_name` null unless you're a member or the invitee, except for `group_deleted`, where it is the name saved at deletion (`group_id` is null then). `clash_count` = plans it clashed with. `series_freq`/`series_until` are set for notifications about a repeating plan (while its plan fields are visible). |
| N `unreadCount()` | REST `GET notifications?select=id&user_id=eq.<me>&read_at=is.null` with `Prefer: count=exact` (`.count()`; the ids come back too) | self | `unreadCountProvider`, the nav badge. |
| N `markAllRead()` | REST `PATCH notifications?user_id=eq.<me>&read_at=is.null {read_at: now}` | self | Only `read_at` is writable (column grant); RLS limits it to your rows. |

## Realtime

Dart: `app/lib/data/realtime_repository.dart` (R).

| Dart | Call | Who | Notes |
|---|---|---|---|
| R `listen(topic, {onChange, onRejoin})` → used by `liveUpdatesProvider` | `channel(topic, private: true).onBroadcast(event: 'changed').subscribe()`; leave with `removeChannel` | `user:<me>`: self; `group:<id>`: members (`easyplan_listen` policy on `realtime.messages`) | Payload `{table, id}`, where `id` is a message id. Clients can't send. On rejoin after a drop, everything for the topic is re-fetched. |

The database sends on writes to `groups` (update and delete only), `group_members`, `group_invitations`, `group_invite_links`, `group_activities`, `activities`, `activity_photos`, `activity_types`, `type_merges`, `schedule_entries`, `schedule_participants` and `notifications` (`broadcast_change` trigger; topics in `docs/database.md` → Realtime). `providersAffectedBy(topic, table)` lists what each message refreshes.

### Not yet used by the app
- `find_clashes` directly (the RPCs above call it).
- The policy helpers `is_group_member`, `is_group_owner`, `shares_group_with`, `is_activity_shared_with_me`, `can_access_activity`, `entry_group`, `is_entry_participant`, `try_uuid` and `is_valid_timezone`. Signed-in users can call them. The `is_*`/`shares_*`/`can_*` ones only answer about the caller; `entry_group` returns any plan's group id, and `try_uuid`/`is_valid_timezone` are pure checks. They exist for RLS and triggers, not the app.
- The `supabase_realtime` publication ("Postgres Changes"); the app uses the broadcasts above instead.

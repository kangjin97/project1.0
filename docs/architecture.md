# Architecture

## Overview

```mermaid
flowchart LR
  subgraph App["Flutter app (web / iOS / Android)"]
    UI["features/* screens"] --> P["Riverpod providers"]
    P --> R["Repositories (data/*)"]
  end
  R -- "PostgREST (tables, RPCs)" --> DB[(Postgres + RLS)]
  R -- "Auth (email/password)" --> AUTH[Supabase Auth]
  R -- "Storage (signed URLs)" --> ST[Storage: activity-photos, avatars]
  DB -- "triggers broadcast 'changed'" --> RT[Realtime: private channels]
  RT -- "group:id / user:id" --> R
  AUTH -- "trigger: create profile" --> DB
  ST -- "policies call can_access_activity()" --> DB
  R -- "functions.invoke (user token)" --> EF[Edge Functions: places, fill-activity]
  EF -- "consume_api_quota (as the user)" --> DB
  EF -- "secret key" --> GP[Google Places API]
  EF -- "secret key" --> CL["Claude API (via AIML API)"]
  EF -- "official previews" --> WEB[TikTok / YouTube oEmbed, page preview tags]
```

There is no custom server of our own. The Flutter app talks to Supabase directly. The one exception is Supabase **Edge Functions** (`supabase/functions/`) for calls that need a secret key: Google place search (`places`, #73) and "Fill from link" (`fill-activity`, #74: official link previews + Claude, currently bought through the reseller AIML API). They run as the signed-in user, check their daily quota in the database, and keep the keys out of the browser. Otherwise, **every rule is enforced in Postgres** through Row Level Security, column-level grants, triggers, and `security definer` functions (RPCs). The app does no access control of its own; at most it hides buttons that the database would reject anyway.

## Flutter app

### Layers

| Layer | Location | Responsibility |
|---|---|---|
| Entry | `main.dart` | Path URL strategy, release-config guard, `Supabase.initialize`, `AppClock.init`, `ProviderScope`, Material 3 theme |
| Config | `config.dart` | `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`, `APP_URL` (defaults to the page's origin on web, `http://127.0.0.1:3000` elsewhere; `--dart-define-from-file=env/prod.json` for releases); invite and privacy links |
| Routing | `router.dart` | `go_router` routes, auth redirect, `ShellRoute` with the navigation shell |
| Data | `data/models.dart`, `data/schedule_models.dart` | Plain immutable models with `fromJson`, plus select-column strings; schedule entries, timing and date helpers |
| Data | `data/*_repository.dart` | Every Supabase call (`auth_repository.dart` for sign-up, sign-in and password resets), plus `FutureProvider`s exposing them. `friendlyError` lives in `groups_repository.dart`. Elsewhere the app only reads local session state (`currentUser`, `onAuthStateChange`) and calls `signOut` |
| Data | `data/app_clock.dart` | `AppClock` (display time zone) and `TimezoneController`, which loads and saves the profile's zone through `ProfileRepository` |
| Features | `features/<area>/` | Screens, sheets and widgets for one area |
| Shared UI | `widgets/` | `AsyncBody`, `EmptyState` (`async_body.dart`); prompt and confirm dialogs, `showMessage`, `showError` (`dialogs.dart`); `UserAvatar` (`user_avatar.dart`) |

### Routing

| Path | Screen | Notes |
|---|---|---|
| `/` | (none) | Redirects to `/schedule`. Auth emails land here with `?code=`, `?message=` or `?error_description=`; the message is shown as a snackbar. |
| `/reset-password` | `ResetPasswordPage` | Opened from a password-reset email; any `passwordRecovery` session is redirected here. |
| `/auth?next=` | `AuthPage` | Sign in or sign up. Signed-out users are redirected here with `next`, so invite links survive sign-in. |
| `/join/:token` | `JoinPage` | Previews and joins a group from an invite link. Outside the shell. |
| `/schedule` | `MySchedulePage` | List / Week / Month switch on all sizes; phones default to List, wide screens to Week. |
| `/groups` | `GroupsPage` | Groups list and pending invitations. |
| `/groups/:id` | `GroupPage` | Tabs: Activities, Schedule, Members, Types. The ⋮ menu has History and Leave, plus Rename and Delete for the owner. |
| `/groups/:id/history` | `GroupHistoryPage` | Who did what in the group, newest first; opened with `context.push` from the group's menu. Lines open the activity (`context.push`), the plan's detail sheet (`showEntryDetail` with `queryAroundEntry`) or the member's profile. |
| `/activities` | `ActivitiesPage` | My activities. |
| `/notifications` | `NotificationsPage` | The "Alerts" tab: notifications, newest first; opening marks them read. |
| `/profile` | `ProfilePage` | Own profile, stats, account settings, sign out. |
| `/people/:id` | `PersonPage` | Someone else's profile; opened with `context.push` from members / "Going" lists. |
| `/activities/:id` | `ActivityDetailPage` | Any activity the user can see. Opened with `context.push` so Back returns to where you came from. |

`HomeShell` shows a bottom `NavigationBar` below 720 px wide and a `NavigationRail` above. It reads the current location from `GoRouter.routerDelegate`, so the highlighted tab follows the URL. Pages outside the five tabs (Schedule, Groups, Activities, Alerts, Profile; e.g. `/people/:id`) highlight Schedule. The Alerts tab carries an unread badge (`unreadCountProvider`), re-counted on each navigation and when the app resumes.

Full-screen forms (`showActivityForm`) and bottom sheets are pushed on the **root** navigator, so they cover the navigation bar.

### Time zones

All times are stored in UTC (`timestamptz`) or as calendar dates. The app shows them in the user's **profile** time zone, not the device's: `AppClock` (in `data/app_clock.dart`) holds the display zone, converts server instants with `inZone`, builds user-picked times with `at`, and gives `today()`. `TimezoneController` loads the zone from the profile after sign-in and switches it when the user changes it; `scheduleProvider` watches `timezoneProvider`, so schedules refetch in the new zone. Sign-up sends the device zone in metadata; it is never overwritten automatically afterwards.

### State and refresh

- Reads are `FutureProvider` or `FutureProvider.family`, keyed by id (for example `groupActivitiesProvider(groupId)`).
- After a mutation, the code that made it **invalidates** the affected providers. Three helpers cover the common cases:
  - `invalidateActivity(ref, activityId, {groupId})`: my activities, that activity, where it's shared, its history, and group activity lists.
  - `invalidateLabels(ref)`: everything a label change can affect, including group types, because labels can create types.
  - `invalidateSchedule(ref)`: every schedule view and plan history.
- **Other people's changes arrive live** (#7). Database triggers broadcast "table X changed" to private Realtime channels (`group:<id>`, `user:<id>`); RLS on `realtime.messages` decides who may listen. `liveUpdatesProvider` (`data/realtime_repository.dart`, watched by `HomeShell`) joins the user's channel and one per group. It waits 400 ms to batch messages, then invalidates the providers `providersAffectedBy(topic, table)` names; only the ones on screen re-fetch. Pull-to-refresh still works as a manual fallback.

### Errors

Repositories throw `PostgrestException`, `AuthException` or `StorageException`. Screens catch them and call `showError`, which maps them through `friendlyError` (`data/groups_repository.dart`):

| Postgres code | Shown as |
|---|---|
| 23505 unique violation | "That already exists." |
| 23503 foreign key | "It's still in use, so it can't be removed yet." |
| 42501 insufficient privilege (RLS, grants, guard triggers) | "You don't have permission to do that." |
| Any other Postgres code, e.g. P0001 `raise exception` in RPCs | The error's message, e.g. "only the owner can delete this activity" |
| `AuthException` | Its message (from Supabase Auth) |
| Anything else, including `StorageException` | "Something went wrong. Please try again." |

Edge Function calls are different: `PlacesRepository` and `AiFillRepository` turn a `FunctionException` into `PlaceSearchException` / `AiFillException` carrying the function's `{error}` text, and the place field and the Fill-from-link sheet show that text directly.

## Backend security model

1. **RLS on every table.** Policies are written with `security definer` helpers, so they don't recurse through other tables' policies:
   - `is_group_member(group)` and `is_group_owner(group)`
   - `can_access_activity(activity)`: the owner, or a member of a group it's shared into
   - `shares_group_with(user)`, `entry_group(entry)`, `is_entry_participant(entry)`
2. **Column grants.** `update` is revoked on tables and granted only on editable columns. Clients can't change ownership, ids or bookkeeping columns, and can't move a schedule entry's time except through `reschedule_entry` or `reschedule_following`, which check for clashes.
3. **Insert-only through RPCs.** `group_members`, `schedule_entries`, `schedule_participants`, `notifications`, `change_log`, `type_merges` and `schedule_series` can't be inserted directly; the RPCs or triggers do it.
4. **Triggers do the bookkeeping.**
   - Profile creation on sign-up, group owner membership and starter types.
   - `updated_at` / `updated_by`, and the change log.
   - Reverting entries to events when an activity leaves a group.
   - Label filing and re-filing.
5. **Storage.** The private `activity-photos` bucket stores files at `<activity_id>/<file>`. Its policies call `can_access_activity` on the first path segment, and the app reads photos through 1-hour signed URLs. The private `avatars` bucket stores profile pictures at `<user_id>/<file>`: any signed-in user can read them, and you can only write in your own folder. They are also read through 1-hour signed URLs.

Emails live only in `auth.users`. `profiles` is readable by all signed-in users but holds no email. Lookup by email (`find_user_by_email`) is exact-match only, so addresses can't be enumerated.

## Key data flows

### Sharing an activity into a group

```mermaid
sequenceDiagram
  participant UI as Share sheet
  participant DB as Postgres
  UI->>DB: rpc preview_group_type(group, label)   (only if the activity has a label)
  DB-->>UI: {type_name, merged, is_new}
  UI->>DB: insert group_activities(group_id, activity_id[, type_id])
  Note over DB: BEFORE INSERT group_activity_defaults:<br/>no type_id → resolve_group_type(group, label)<br/>(merge rule → same-name type → create type)
  Note over DB: AFTER INSERT log_change('group_activity')
```

### Changing or renaming a label

When `activities.personal_type_id` or `personal_types.name` changes, a trigger runs `resolve_group_type` for every group the activity is in. It sets `source_type_name` and `type_id`, which overrides any type a member chose by hand. When the label is removed, only `source_type_name` is cleared; the group types stay.

### Merging types

`merge_types(group, sources[], target_id | target_name)` does the following:
1. Creates the target if it's given by name.
2. Removes any rule that would redirect the target's own name.
3. For each source: upserts a rule `source.name → target`, re-points rules that targeted the source, moves the source's activities, and deletes the source type.

`remove_type_merge(rule)` deletes the rule and re-resolves the activities whose `source_type_name` matched it.

### Scheduling with clash checks

`create_schedule_entry(..., p_force)` first calls `find_clashes` for the chosen people.
- **Clashes and `p_force = false`:** it returns `{status: 'clash', clashes}` and saves nothing.
- **Otherwise:** it inserts the entry, marks clashing participants `status = 'clash'`, notifies them, and logs a `clash_override`.

All-day entries cover the whole day in each participant's `profiles.timezone`. Titles of entries in groups the caller isn't in come back as "Busy".

In the app, `EntryEditorPage` calls without force first; on a clash it shows `confirmClashes` and, if the planner proceeds, calls again with `p_force: true`. Lists come from `list_schedule`; the entry sheet watches the same `scheduleProvider(query)` as the list it was opened from, so it updates in place after each action.

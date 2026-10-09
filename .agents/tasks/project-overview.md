# Group Planner — Project Overview

## Summary

Group Planner is a cross-platform (web, iOS, Android) Flutter app backed by Supabase. It lets groups of friends collect activity ideas, share them into shared groups, and schedule them — with automatic clash detection, a tamper-proof change log, and real-time updates. The database layer is production-ready and comprehensive; the Flutter frontend has auth and group management working but the three core feature areas (Activities, Schedule, Events) are still unimplemented placeholders.

---

## 1. What the App Does

Users create or join **groups**, then:
- Add **activities** (a restaurant, a hike, a venue) privately, then share them into groups with a label called an **activity type**.
- Schedule activities — or ad-hoc **events** (named placeholders) — for a date/time, choosing which group members participate.
- The app checks every selected member's calendar for **clashes** before saving. If there are overlaps, the planner sees a summary and can proceed or cancel.
- Any group member can later swap a placeholder event for a real activity.
- Every write is recorded in a **change log** via database triggers — immutable history of who planned what.
- Members receive **notifications** for invitations, being added to an entry, and clash alerts.

---

## 2. Tech Stack

| Layer | Technology |
|---|---|
| Frontend | Flutter 3.x (targets web, iOS, Android) |
| Backend / DB | Supabase — Postgres 17, Auth, Storage, Row Level Security, Realtime |
| State management | `flutter_riverpod ^3.3.2` |
| Routing | `go_router ^18.0.2` |
| Date/number formatting | `intl ^0.20.3` |
| Icons | Material 3 + `cupertino_icons ^2.0.0` |

No Firebase is used. Supabase handles auth, database, file storage, and realtime subscriptions.

The Supabase local stack runs on `http://127.0.0.1:54321`. Android emulator connectivity is handled transparently in `app/lib/config.dart` by rewriting `127.0.0.1` → `10.0.2.2`.

---

## 3. Project Structure

```
group-planner/
├── SPEC.md                          Full product specification
├── app/                             Flutter application
│   ├── pubspec.yaml                 Dependencies (supabase_flutter, go_router, riverpod, intl)
│   └── lib/
│       ├── main.dart                Supabase init, ProviderScope, MaterialApp.router
│       ├── router.dart              GoRouter: auth redirect, shell route, /auth /join/:token
│       ├── config.dart              SUPABASE_URL / SUPABASE_PUBLISHABLE_KEY (dart-defines)
│       ├── data/
│       │   ├── models.dart          Profile, Group, Member, ActivityType, Invitation
│       │   └── groups_repository.dart  All Supabase calls; Riverpod providers
│       ├── features/
│       │   ├── auth/auth_page.dart  Sign-up (with username) and sign-in
│       │   ├── home/
│       │   │   ├── home_shell.dart  Responsive nav: BottomNavigationBar (<720px) / NavigationRail
│       │   │   └── placeholder_page.dart  Stub for unimplemented screens
│       │   └── groups/
│       │       ├── groups_page.dart Groups list, invitation accept/decline, create/join
│       │       ├── group_page.dart  4-tab page: Activities*, Schedule*, Members, Types
│       │       └── join_page.dart   Preview and join via invite link token
│       └── widgets/
│           ├── async_body.dart      AsyncValue → loading/error/data widget
│           └── dialogs.dart         promptText, confirm, showError, showMessage
└── supabase/
    ├── config.toml                  Local Supabase settings (port 54321/54322/54323)
    ├── migrations/
    │   └── 20261002000000_init.sql  Complete schema, functions, triggers, RLS, storage
    └── seed.sql                     Two dev accounts (alice@dev.test, bob@dev.test / devpass123)
```

`*` = tab exists in the UI but shows an empty-state placeholder; no real implementation.

---

## 4. Database Layer (Supabase)

The single migration file is the most complete part of the project. It implements the entire SPEC data model.

### Tables (14)
`profiles`, `groups`, `group_members`, `group_invite_links`, `group_invitations`, `activities`, `activity_photos`, `activity_types`, `group_activities`, `schedule_entries`, `schedule_participants`, `change_log`, `notifications`

### Key design points
- **Soft delete on activities** (`deleted_at`): history survives; schedule entries that reference a deleted activity automatically revert to named events via a `BEFORE DELETE` trigger on `group_activities`.
- **Change log via triggers**: the `log_change()` trigger fires on insert/update/delete for every important table, computing field-level `before`/`after` diffs. Clients cannot bypass it.
- **Clash detection**: `find_clashes(user_ids, ...)` is a SQL function that computes `tstzrange` overlaps in the user's local timezone. Three RPCs (`create_schedule_entry`, `reschedule_entry`, `add_entry_participants`) call it and return `{status: 'clash', clashes: [...]}` unless `p_force = true`.
- **RLS on every table**: helper functions (`is_group_member`, `is_group_owner`, `can_access_activity`, etc.) are `SECURITY DEFINER` to prevent RLS recursion. Column-level UPDATE grants lock down ownership/bookkeeping columns.
- **Realtime**: `schedule_entries`, `schedule_participants`, `notifications`, `group_activities` are added to the Supabase Realtime publication.
- **Storage**: `activity-photos` bucket with RLS policies using `try_uuid(foldername(name)[1])` to infer the activity from the path.

---

## 5. Flutter App — What's Implemented

### Working
- **Auth page** (`auth_page.dart`): email + password sign-up (with unique username check via RPC `username_available`), sign-in, friendly error messages. Routes back to original URL after sign-in (invite link deep links work through auth).
- **Groups list** (`groups_page.dart`): displays groups and pending invitations; create group, join via code/link, accept/decline invitations.
- **Group page** (`group_page.dart`):
  - **Members tab**: lists members with roles; invite by username/email search (`_InviteSheet` with 300ms debounce); create shareable invite link (7-day expiry); owner can remove members.
  - **Types tab**: full CRUD for activity types (add, rename, delete).
- **Join page** (`join_page.dart`): previews group name/member count before joining; calls `join_group_via_link` RPC.
- **Responsive nav shell** (`home_shell.dart`): bottom nav bar on phones, side NavigationRail on screens ≥ 720 px; sign-out button in rail.

### Placeholder / Not Implemented
| Screen | Status |
|---|---|
| My Schedule (`/schedule`) | Placeholder — "Your plans across all groups will show up here." |
| My Activities (`/activities`) | Placeholder — "Activities you create will show up here." |
| Group → Activities tab | EmptyState only |
| Group → Schedule tab | EmptyState only |
| Activities CRUD + photos | Not started |
| Sharing an activity into a group | Not started |
| Schedule entry creation + clash UI | Not started |
| Events (placeholder entries) | Not started |
| Clash resolution (resolve/leave) | Not started |
| Change log views | Not started |
| Notifications screen | Not started |

This maps to build steps 4–8 in SPEC §6; only steps 1–3 are done.

---

## 6. Notable Implementation Details

- **`GroupsRepository`** (`data/groups_repository.dart`) is a plain Dart class (no `StateNotifier`). All providers are `FutureProvider` / `FutureProvider.family`. Refreshing is done by calling `ref.invalidate(...)`.
- **`friendlyError`** translates Postgres error codes (23505 = duplicate, 23503 = FK violation, 42501 = permission) into human-readable messages; used in both the repository and the dialog helpers.
- **`AsyncBody<T>`** is a concise wrapper that maps `AsyncValue` to a loading spinner, error state, or data widget — used consistently across all pages.
- **No test files exist** in the Flutter app (`flutter_test` is a dev dependency but no test files were found under `app/`).

---

## 7. Completeness Assessment

| Area | State |
|---|---|
| Product spec (SPEC.md) | Complete and detailed |
| Database schema + RLS | Complete and production-quality |
| DB triggers (change log) | Complete |
| DB RPCs (clash, invite, schedule) | Complete |
| Flutter: auth | Complete |
| Flutter: groups + membership | Complete |
| Flutter: activities | Not started |
| Flutter: schedule | Not started |
| Flutter: events | Not started |
| Flutter: change log UI | Not started |
| Flutter: notifications | Not started |
| Flutter: tests | Not started |

Roughly 30–35% of the Flutter work described in the spec has been built. The hardest backend work (schema, clash detection, RLS, triggers) is done. The remaining Flutter work is substantial but has a solid and well-designed foundation to build on.

---

## 8. Recommendations

1. **Activities feature next** (SPEC §2.2, build step 4): the DB and repository plumbing for groups is already there; activities are the natural next layer. Add `ActivitiesRepository`, the My Activities screen, and the Activity detail/edit page.

2. **Add tests before the app grows further**: the project has zero Flutter tests. At minimum, unit-test `GroupsRepository` error paths and `friendlyError`, and widget-test the `AsyncBody` edge cases. The Supabase local stack can drive integration tests.

3. **Schedule entry creation** will need a bottom sheet that mirrors the spec's §2.5 flow (pick activity or name event → pick time → pick members → clash dialog). The RPC `create_schedule_entry` already handles the backend logic; the Flutter side just needs to drive it.

4. **Realtime subscriptions** are enabled on the Supabase side but no `StreamProvider` or `supabase.stream(...)` calls exist in the Flutter app yet. Wiring this up for schedule and notification updates will require changes to the provider layer.

5. **Currency** defaults to `'SGD'` in the DB but the spec shows a `currency` field on activities. The UI will need a currency picker or at minimum a way to set it per-user.

6. **`SPEC §7` open points** to decide before implementing schedules: confirm that any member can unshare an activity (code allows it via RLS), and decide on in-app-only vs. push notifications for v1.

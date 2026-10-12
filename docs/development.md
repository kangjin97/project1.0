# Development guide

## Prerequisites

| Tool | Version used | Notes |
|---|---|---|
| Flutter | 3.47.x stable (Dart 3.13) | `pubspec.yaml` requires Dart `^3.10.9`. Current Dart needs **macOS 14+**; on macOS 13 the newest usable Flutter is 3.38.x. |
| Docker | any recent | Runs the local Supabase stack. |
| Supabase CLI | 2.119+ | `brew install supabase/tap/supabase`, or the release binary from github.com/supabase/cli. |
| Xcode | 26.x | Only for iOS/macOS builds. Accept the license once: `sudo xcodebuild -license accept`. |
| Android Studio | any recent | Only for Android builds. |

## First-time setup

```bash
git clone <repo> group-planner && cd group-planner
supabase start                 # pulls images on first run, applies migrations and seed.sql
cd app && flutter pub get
```

`supabase start` prints local URLs and keys. The app already defaults to the local stack (see [`app/lib/config.dart`](../app/lib/config.dart)), so nothing needs copying.

| Service | URL |
|---|---|
| API (REST, Auth, Storage) | http://127.0.0.1:54321 |
| Postgres | postgresql://postgres:postgres@127.0.0.1:54322/postgres |
| Studio (DB browser) | http://127.0.0.1:54323 |
| Mailpit (auth emails) | http://127.0.0.1:54324 |

Email confirmation is off locally, so sign-ups are signed in immediately.

## Running the app

```bash
cd app
flutter run -d chrome                                                  # web, opens Chrome
flutter run -d web-server --web-hostname 127.0.0.1 --web-port 3000    # web, any browser
flutter run -d <ios-simulator-or-android-device>
```

- **Android emulator:** `config.dart` rewrites `127.0.0.1` to `10.0.2.2` automatically.
- **Physical devices:** point at your machine's LAN IP:
  `flutter run --dart-define=SUPABASE_URL=http://192.168.x.x:54321`
- **Production builds:** use `./scripts/build.sh` with `app/env/prod.json`; see [`deployment.md`](deployment.md).
- **Hosted Supabase project:**
  `flutter run --dart-define=SUPABASE_URL=https://<ref>.supabase.co --dart-define=SUPABASE_PUBLISHABLE_KEY=<key>`

URLs are clean paths (`http://127.0.0.1:3000/groups/...`), not `#/...`. Password-reset emails land in Mailpit; their links redirect to `/reset-password` (allowed in `supabase/config.toml` → `additional_redirect_urls`).

Test accounts (from [`supabase/seed.sql`](../supabase/seed.sql)): `alice@dev.test` (`dev_alice`) and `bob@dev.test` (`dev_bob`).

## Database workflow

The migrations in `supabase/migrations/` are the source of truth for the schema. Never change the schema through Studio without writing a migration.

| Task | Command |
|---|---|
| Create a migration | `supabase migration new <name>`, then edit the file |
| Apply new migrations, **keeping data** | `supabase migration up` |
| Run database tests | `supabase test db` |
| Rebuild the DB from scratch (**deletes all local data**) | `supabase db reset` |
| Stop / start the stack | `supabase stop` / `supabase start` (data is kept) |

> **Warning:** `supabase db reset` wipes every account, activity and photo in the local database, including anything you created by hand while testing. Use `supabase migration up` to apply new migrations.

Never edit a migration that has already been applied anywhere other than your machine; add a new one instead.

### Writing database tests

Tests are pgTAP files in `supabase/tests/database/`. Each runs in a transaction that is rolled back, so they never touch real data. The pattern:

```sql
begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
insert into auth.users (...) values (...);              -- test users; profiles are created by trigger
create function pg_temp.act_as(p uuid) ...;             -- sets request.jwt.claims
set local role authenticated;
select pg_temp.act_as('<user uuid>');                   -- now queries run through RLS as that user
select is(..., ..., 'description');
select * from finish();
rollback;
```

## Adding a feature: checklist

1. **Schema:** a new migration with tables, RLS policies, column grants and any RPCs. Revoke `execute` on new functions from `public, anon` (and from `authenticated` for internal helpers).
2. **Tests:** a pgTAP file covering the rules, run as real users through RLS.
3. **Models:** add to `app/lib/data/models.dart`, including a `columns` select string if it embeds relations.
4. **Repository:** methods in `app/lib/data/*_repository.dart`, plus `FutureProvider`s.
5. **UI:** screens in `app/lib/features/<area>/`. After a mutation, invalidate every provider that shows the changed data (see `invalidateActivity` and `invalidateLabels`).
6. **Routes:** register in `app/lib/router.dart`.
7. **Docs:** update `docs/ai/features.md`, `docs/ai/endpoints.md`, `docs/database.md` and `SPEC.md` as needed.
8. **Checks:** `flutter analyze` (must be clean), `flutter test`, then `supabase test db`.

## Git workflow

Work is tracked in **GitHub Issues** (https://github.com/kangjin97/project1.0/issues).

1. **Raise an issue.** Use the **Bug** or **Feature or change** form (`.github/ISSUE_TEMPLATE/`), or a blank issue for chores. Labels: `bug`, `feature`, `chore`, optionally `priority:high`.
2. **Branch from `main`**, named after the issue: `fix/<n>-short-name`, `feature/<n>-short-name`, `chore/<n>-short-name`.
3. **Open a pull request** into `main` (`gh pr create --base main`). The template starts with `Closes #<n>`, so merging closes the issue.
4. **CI must be green.** `.github/workflows/ci.yml` runs on every PR and push to `main`:
   - **App:** `flutter analyze` and `flutter test` (Flutter 3.47.6).
   - **Database:** `supabase start` without the UI services, then `supabase test db`.
5. **Review, merge,** then delete the branch locally and on GitHub.

Never commit `app/env/prod.json`, `app/android/key.properties` or keystores (`*.jks`); they're git-ignored.

## Code conventions

- All Supabase access lives in repositories under `app/lib/data/`; widgets never call `Supabase.instance.client` directly. The exceptions are `auth.signOut()` and reading `currentUser` for the current user's id.
- Data loading uses Riverpod `FutureProvider` / `FutureProvider.family`, shown with `AsyncBody`.
- Show errors with `showError(context, e)`; it runs them through `friendlyError`.
- Bottom sheets use `useRootNavigator: true` so they appear above the navigation bar.
- Never use `DateTime.now()` / `.toLocal()` for anything shown to the user; use `AppClock.today()`, `AppClock.now()`, `AppClock.inZone(...)` and `AppClock.at(...)` so times follow the profile's time zone.
- `supabase-dart`'s `.order()` sorts **descending by default**. Always pass `ascending:` explicitly.
- PostgREST `ilike` patterns use `*` as the wildcard, not `%`.
- Comments explain *why*, not what. Match the density of the surrounding code.

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| `VM initialization failed: Current Mac OS X version 13.0 is lower than minimum supported version 14.0` | Current Dart needs macOS 14+. Upgrade macOS, or pin Flutter: `cd <flutter> && git checkout 3.38.10`. |
| Homebrew: `You have not agreed to the Xcode license` / `Your Xcode is too outdated` | Run `sudo xcodebuild -license accept`; update Xcode or run `xcode-select --install`. |
| Claude desktop preview: `flutter: Operation not permitted` | macOS privacy (TCC) blocks the preview launcher from reading `~/Documents`. Start the server from a terminal; `.claude/launch.json` then attaches to `http://127.0.0.1:3000`. Or grant the app access in System Settings → Privacy & Security → Files and Folders. |
| `Assertion failed: The targeted input element must be the active input element` in the web console | Debug-only Flutter web engine assertion, seen with automated or synthetic clicks. Harmless. |
| App shows "You don't have permission to do that." | An RLS policy or column grant rejected the request (Postgres code 42501). See [`database.md`](database.md) for who can do what. |
| Empty lists right after `supabase db reset` | Expected: the reset deleted all data. Sign up again or use the seed accounts. |

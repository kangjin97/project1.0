# Development guide

## Setting up a computer

EasyPlan is developed on both a **Mac** and a **Windows PC**. Set up each computer once:

- **Mac:** [`setup-mac.md`](setup-mac.md)
- **Windows:** [`setup-windows.md`](setup-windows.md) (includes WSL 2 and Docker)

Both install the same versions CI uses, so results match everywhere:

| Tool | Version | Pinned in |
|---|---|---|
| Flutter | 3.47.6 (Dart 3.13) | `.github/workflows/ci.yml` → `flutter-version` |
| Supabase CLI | 2.119.0 | `.github/workflows/ci.yml` → `supabase/setup-cli` `version` |
| Docker | any recent | Runs the local Supabase stack |
| Xcode | 26.x | Mac only; iOS builds |
| Android Studio | any recent | Either computer; Android builds |

When CI's versions change, update both computers.

## First run

The same on both computers (on Windows, use Command Prompt, or run each line separately in PowerShell):

```bash
git clone https://github.com/kangjin97/project1.0.git && cd project1.0
supabase start                 # first run downloads the images, then applies migrations and seed.sql
supabase test db               # should end with "Result: PASS"
cd app && flutter pub get
flutter analyze                # "No issues found!"
flutter test
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
- **Edge Functions** (`supabase/functions/`: `places` for Google place search, `fill-activity` for "Fill from link", `place-coordinates` for the "Near…" filter): put the keys (`GOOGLE_MAPS_API_KEY`, `ANTHROPIC_API_KEY`, `ANTHROPIC_BASE_URL`) in `supabase/functions/.env` (git-ignored; see `deployment.md` → Edge Functions and Google Maps, and → Claude for "Fill from link"), then run
  `supabase functions serve --env-file supabase/functions/.env`
  alongside the stack; the app reaches them at `:54321/functions/v1/<name>`. Without a key, that feature answers "isn't set up yet" and the form still works by hand.
- **Two people at once** (for anything shared, e.g. live updates or invitations): tabs on one address share a sign-in, and the debug server only runs the app in one tab. So start a second server as a profile build on another port:
  `flutter run --profile -d web-server --web-hostname 127.0.0.1 --web-port 3001`
  Sign in as `dev_alice` on :3000 and `dev_bob` on :3001. Release builds refuse the local backend; profile builds don't. Neither server hot-reloads when an agent starts it in the background: restart after Dart changes.

URLs are clean paths (`http://127.0.0.1:3000/groups/...`), not `#/...`. Password-reset emails land in Mailpit; their links redirect to `/reset-password` (allowed in `supabase/config.toml` → `additional_redirect_urls`). Continue with Google returns to `http://127.0.0.1:3000/?next=…`, also allowed there; the :3001 profile build isn't listed, so Google sign-in there lands on :3000 instead.

Test accounts (from [`supabase/seed.sql`](../supabase/seed.sql)): `alice@dev.test` (`dev_alice`) and `bob@dev.test` (`dev_bob`).

## Working on both computers

GitHub is the single source of truth. Neither computer is special; either one can do everything except iOS builds (Mac only).

- **Pull before you start; push your branch before switching computers.** Code, issues, the board, CI, deploy settings and deploys all live on GitHub. Nothing else syncs.
- **Each computer has its own local database.** Accounts and test data made on one aren't on the other. Shared test data belongs in `supabase/seed.sql`. The rules are the same on both: `supabase migration up`, and `supabase db reset` only when you mean to wipe that computer's data.
- **A few git-ignored files exist only where they're needed.** You normally don't need them at all:

  | File | Needed for | Notes |
  |---|---|---|
  | `app/env/prod.json` | Manual release builds (`scripts/build.sh`) | CI builds web releases from GitHub secrets, so web deploys don't need it |
  | `app/android/key.properties` + upload keystore (`*.jks`) | Android release builds | Copy by hand (USB drive, password manager), never through git or chat |
  | `supabase/.env` | Continue with Google locally (`config.toml` → `[auth.external.google]`) | Google OAuth client ID and secret, typed in on each computer ([`deployment.md`](deployment.md#sign-in-with-google-87)); restart the stack after changing it |
  | `supabase/functions/.env` | Place search and Fill from link locally (`supabase functions serve`) | Type the keys in on each computer ([`setup-mac.md`](setup-mac.md#optional-place-search-and-fill-from-link)); never through git or chat |
  | `supabase/.temp` (from `supabase link`) | `supabase db push`, `supabase functions deploy`, `supabase migration list --linked` | Run `supabase login` and `supabase link --project-ref <ref>` once on whichever computer does those |

- **Scripts:** `./scripts/*.sh` are bash. On Windows, run them in Git Bash ([`setup-windows.md`](setup-windows.md#which-terminal)).
- Git converts line endings on Windows automatically (`core.autocrlf`), so commits from either computer look the same.

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

1. **Schema:** a new migration with tables, RLS policies, column grants and any RPCs. Revoke `execute` on new functions from `public, anon` (and from `authenticated` for internal helpers). If a screen shows the new table, add a `broadcast_change` trigger on it so other people's changes arrive live (see `docs/database.md` → Realtime).
2. **Tests:** a pgTAP file covering the rules, run as real users through RLS.
3. **Models:** add to `app/lib/data/models.dart`, including a `columns` select string if it embeds relations.
4. **Repository:** methods in `app/lib/data/*_repository.dart`, plus `FutureProvider`s.
5. **UI:** screens in `app/lib/features/<area>/`. After a mutation, invalidate every provider that shows the changed data (see `invalidateActivity` and `invalidateLabels`). For live updates, add the table's providers to `providersAffectedBy` in `data/realtime_repository.dart`.
6. **Routes:** register in `app/lib/router.dart`.
7. **Docs:** update `docs/ai/features.md`, `docs/ai/endpoints.md`, `docs/database.md` and `SPEC.md` as needed.
8. **Checks:** `flutter analyze` (must be clean), `flutter test`, then `supabase test db`. Then try it in the app locally; for anything two people see, test with two sessions (`docs/ai/handover.md` → Pitfalls → Testing with two people).

## Git workflow

Work is tracked in **GitHub Issues** (https://github.com/kangjin97/project1.0/issues) and on the **EasyPlan project board** (https://github.com/users/kangjin97/projects/3), with columns **Todo → In Progress → Done**.

1. **Raise an issue.** Use the **Bug** or **Feature or change** form (`.github/ISSUE_TEMPLATE/`), or a blank issue for chores. Labels: `bug`, `feature`, `chore`, optionally `priority:high`. GitHub numbers it automatically, and the card appears in **Todo**.
2. **Start work:** move the card to **In Progress** with `./scripts/board.sh <n> progress`, or drag it on the board. Then **branch from `main`**, named after the issue: `fix/<n>-short-name`, `feature/<n>-short-name`, `chore/<n>-short-name`.
3. **Open a pull request** into `main` (`gh pr create --base main`). The template starts with `Closes #<n>`, so merging closes the issue.
4. **CI must be green.** `.github/workflows/ci.yml` runs on every PR and push to `main`:
   - **App:** `flutter analyze` and `flutter test` (Flutter 3.47.6).
   - **Database:** `supabase start` without the UI services, then `supabase test db`.
5. **Test locally, review, merge,** then delete the branch locally (`git branch -D <branch>`; GitHub deletes its copy automatically on merge). Merging closes the issue and the board moves its card to **Done**. Merging does **not** deploy: the live site stays as it is until the owner asks for a deploy, usually at the end of the day ([`deployment.md`](deployment.md#deploying-the-web-app)). If merged PRs add migrations, run `supabase db push` on the cloud project **before** that deploy.

Never commit `app/env/prod.json`, `app/android/key.properties` or keystores (`*.jks`); they're git-ignored.

### Project board

- **Board:** https://github.com/users/kangjin97/projects/3. It's linked to the repo, so it also shows under the repo's **Projects** tab.
- **Moving cards:** `./scripts/board.sh <issue> todo|progress|done`. It adds the issue to the board if it's missing. Needs `gh` with the `project` scope; if that's missing, run `gh auth refresh -h github.com -s project`.
- **Board automations** (board → **⋯** → **Workflows**). These can only be set on the website:
  - **Auto-add to project:** repository `project1.0`, filter `is:issue is:open`. New issues land in Todo.
  - **Item closed** and **Pull request merged** → **Done**.

## Code conventions

- All Supabase access lives in repositories under `app/lib/data/`; widgets never call `Supabase.instance.client` directly. Auth calls (sign-up, sign-in, password reset) are in `auth_repository.dart`. The only direct uses allowed elsewhere are local session state: `currentUser` / `currentSession`, `onAuthStateChange`, and `auth.signOut()`.
- Data loading uses Riverpod `FutureProvider` / `FutureProvider.family`, shown with `AsyncBody`.
- Show errors with `showError(context, e)`; it runs them through `friendlyError`.
- Bottom sheets use `useRootNavigator: true` so they appear above the navigation bar.
- Never use `DateTime.now()` / `.toLocal()` for anything shown to the user; use `AppClock.today()`, `AppClock.now()`, `AppClock.inZone(...)` and `AppClock.at(...)` so times follow the profile's time zone.
- `supabase-dart`'s `.order()` sorts **descending by default**. Always pass `ascending:` explicitly.
- PostgREST `ilike` patterns use `*` as the wildcard, not `%`.
- Comments explain *why*, not what. Match the density of the surrounding code.

## Troubleshooting

Computer-specific problems are in [`setup-mac.md`](setup-mac.md#mac-only-notes-and-troubleshooting) and [`setup-windows.md`](setup-windows.md#troubleshooting).

| Symptom | Cause and fix |
|---|---|
| `Assertion failed: The targeted input element must be the active input element` in the web console | Debug-only Flutter web engine assertion, seen with automated or synthetic clicks. Harmless. |
| App shows "You don't have permission to do that." | An RLS policy or column grant rejected the request (Postgres code 42501). See [`database.md`](database.md) for who can do what. |
| Empty lists right after `supabase db reset` | Expected: the reset deleted all data. Sign up again or use the seed accounts. |

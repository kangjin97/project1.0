# CLAUDE.md — steering for AI agents

EasyPlan (repo `group-planner`; Dart package `group_planner`): Flutter app (`app/`) + Supabase backend (`supabase/`) for friends planning activities together. Read this file first, then the doc that matches your task. **New to the project, or no memory of earlier sessions?** Read [`docs/ai/handover.md`](docs/ai/handover.md) right after this file: services and accounts, current state, working agreements with the owner, pitfalls.

## Where to look

| Need | File |
|---|---|
| Handover: accounts, current state, how the owner works | `docs/ai/handover.md` |
| What the product must do | `SPEC.md` |
| What's built, where it lives, backlog | `docs/ai/features.md` |
| Every table op / RPC: params, returns, who, errors | `docs/ai/endpoints.md` |
| Why things are this way (incl. owner's answers) | `docs/ai/decisions.md` |
| Schema, triggers, policies | `docs/database.md`, `supabase/migrations/` |
| App structure, data flows | `docs/architecture.md` |
| Setup, commands, troubleshooting | `docs/development.md` |
| Setting up the Mac or the Windows PC | `docs/setup-mac.md`, `docs/setup-windows.md` |
| Releasing (Supabase cloud, Netlify, stores) | `docs/deployment.md` |
| What to work on next | GitHub Issues (`gh issue list`) and the **EasyPlan** board: https://github.com/users/kangjin97/projects/3 |

## Commands

```bash
supabase start                      # local stack (Docker); API :54321, Studio :54323
supabase migration up               # apply new migrations, KEEPS data
supabase test db                    # pgTAP tests (rolled back; safe)
cd app && flutter analyze           # must report "No issues found!"
cd app && flutter test              # Dart unit tests (e.g. AppClock)
./scripts/board.sh <issue> progress # move an issue's card on the project board (todo|progress|done)
cd app && flutter run -d web-server --web-hostname 127.0.0.1 --web-port 3000
cd app && flutter run --profile -d web-server --web-hostname 127.0.0.1 --web-port 3001  # second person (own session)
supabase migration list --linked    # which migrations the cloud has (read-only)
gh workflow run ci.yml --ref main   # deploy the web app: ONLY when the owner asks, after their `supabase db push`
supabase functions serve --env-file supabase/functions/.env  # Edge Functions locally (places, fill-activity); keys in the git-ignored .env
```

The Supabase CLI may be at `~/.local/bin/supabase` rather than on `PATH`. The owner works on both a Mac and a Windows PC (`docs/development.md` → Working on both computers). On Windows, run `scripts/*.sh` in Git Bash, and remember Windows PowerShell has no `&&`.

## Hard rules

1. **Never run `supabase db reset`, or any other command that wipes the database, without asking the owner first.** They test by hand, and a reset once destroyed their account and data. Use `supabase migration up`.
2. **Rules belong in the database.** Access control and invariants go in RLS policies, column grants, triggers or `security definer` RPCs, with pgTAP tests. The app may hide UI, but must not be the only guard.
3. **Never edit an applied migration.** Add a new file under `supabase/migrations/` (`supabase migration new <name>`).
4. **New functions:** `security definer set search_path = ''`, fully qualified names (`public.x`). `revoke execute ... from public, anon`; also from `authenticated` for internal helpers and trigger functions. Invoker functions still set `search_path = ''`. `function_privileges.test.sql` fails if a function skips `search_path` or `anon` gets something new.
5. **Supabase access only in `app/lib/data/*_repository.dart`.** Widgets use providers and repository methods; auth calls are in `auth_repository.dart`. Only local session state may be used directly: `auth.currentUser`, `auth.currentSession`, `auth.onAuthStateChange`, and `auth.signOut()`.
6. **After every mutation, invalidate the affected providers** (`invalidateActivity`, `invalidateLabels`, or specific `ref.invalidate(...)`). Otherwise screens show stale data. Other people's changes arrive through Realtime: a new table that a screen shows needs a `broadcast_change` trigger and a case in `providersAffectedBy` (`data/realtime_repository.dart`), or it won't update live.
7. Before finishing: `flutter analyze` must be clean and `supabase test db` must pass. If you changed behaviour, update `docs/ai/features.md`, `docs/ai/endpoints.md` and, where relevant, `docs/database.md`, `SPEC.md` and `docs/ai/decisions.md`.
8. Don't commit or push unless asked.
9. **Never commit secrets or signing material:** `app/env/prod.json`, `app/android/key.properties`, `*.jks` and `supabase/functions/.env` (API keys for Edge Functions) are git-ignored; keep it that way. Never ask for or print an API key; the owner types keys into `.env` or `supabase secrets set` themselves. Never change the app ID `com.kangjin.easyplan`.
10. New migrations reach production only via `supabase db push` (owner runs it). **Merging to `main` does not deploy**; the web app deploys only when the owner asks (`docs/deployment.md` → Deploying the web app). Migrations must be pushed to the cloud *before* the deploy that needs them; say so in the PR.

## Gotchas (each has bitten this project)

- supabase-dart `.order(col)` is **descending by default**. Always pass `ascending:`.
- PostgREST `ilike` uses `*` as the wildcard; `%` didn't work through the client.
- `showModalBottomSheet` must use `useRootNavigator: true`, or the sheet sits under the bottom nav bar.
- Don't dispose a `TextEditingController` in `showDialog(...).whenComplete`; the closing animation still uses it (`_dependents.isEmpty` assertion). Let a `StatefulWidget` own it (see `_PromptDialog` in `widgets/dialogs.dart`).
- In policies, qualify outer columns in subqueries (`groups.id`, not `id`); unqualified names bind to the inner table.
- Inside `STABLE` SQL functions, rows inserted earlier in the same statement aren't visible. Write `insert ... returning` select policies inline (e.g. `owner_id = auth.uid()`), not through a helper.
- User-facing times must go through `AppClock` (profile time zone), never `DateTime.now()` / `.toLocal()`.
- `package:timezone` must load `latest_all`; the smaller data sets drop aliases like `Asia/Kuala_Lumpur`, which browsers report.
- DB tests must not assume tables or buckets are empty; the local DB holds the owner's real test data.
- On Flutter web, `1 << 32` is 0. Keep `Random().nextInt` bounds ≤ `1 << 30`.
- Flutter web in the Claude preview pane:
  - Screenshots can show a stale frame. Hover, wait, and re-screenshot before concluding.
  - While the pane is hidden or the window is behind another, Flutter doesn't draw: screenshots and clicks time out. Check behaviour through the local API instead, or ask the owner to bring the window forward.
  - Typing straight after a click can land in the previously focused field. Wait ~0.5–1 s after clicking.
  - Engine assertions about "targeted input element" come from synthetic clicks; ignore them.
- The app uses **path URLs** (`usePathUrlStrategy`), not `#/`. Hosting must serve `index.html` for unknown paths (`app/web/_redirects`). Links: `AppConfig.inviteLink`, `AppConfig.appUrl`; never build URLs from `Uri.base` directly.
- Deleting a user sets "who did it" columns to null; models must treat `createdBy`, `sharedById`, actor names as nullable ("a deleted user").
- `touch_updated` only stamps `updated_by` for users that still exist (needed during account deletion).
- Supabase auth emails link back to the site root with query parameters (`/?code=`, `/?message=`, `/?error_description=`); the router redirects `/` and shows the message (`authLinkNotice`). Keep that redirect.
- Email templates in `supabase/templates/` only apply to the local stack (`config.toml`). The cloud copy is pasted by hand in the dashboard (`docs/deployment.md` §1); say so in the PR whenever a template changes. Don't use `supabase config push`: it would also push local-only settings such as `site_url`.
- Mac: current Dart needs macOS ≥ 14.
- Each computer (Mac, Windows) has its own local database; data made on one isn't on the other.
- Windows: Docker Desktop needs WSL 2; the `supabase_vector` container restart-loops there, which is harmless.
- `supabase start` may stop the `edge_runtime` container (it did on Windows), so Edge Functions aren't served by the stack. Run `supabase functions serve <name> --env-file supabase/functions/.env` instead; it serves on the usual `:54321/functions/v1/<name>`.
- Windows: tools installed during a session (`gh`, `flutter`, `supabase`, `docker`) aren't on the agent's PATH until the owner quits the Claude app from the system tray and reopens it. Until then, call them by full path (e.g. `$env:USERPROFILE\dev\flutter\bin`, `$env:USERPROFILE\.local\bin`, `$env:ProgramFiles\Docker\Docker\resources\bin`).
- Mac: the preview launcher can't read `~/Documents` (macOS TCC). Start the dev server via Bash; `.claude/launch.json` attaches to `http://127.0.0.1:3000`.

## Production

- Live web app: **https://easyplan-hehe.netlify.app** (Netlify project `easyplan-hehe`), backed by a Supabase cloud project linked from this repo. Current state and steps: `docs/deployment.md`.
- The cloud database is separate from the local one; nothing local (accounts, seed data) is in it.
- **Deploys are on request only** (each Netlify deploy costs credits). The owner develops and tests locally, merges to `main` as often as they like, and says when to deploy, usually at the end of the day. The `deploy-web` job in `.github/workflows/ci.yml` runs only on a manual run on `main` (`gh workflow run ci.yml --ref main`), after the app and database checks pass. Settings come from GitHub secrets/variables (`docs/deployment.md` → Deploying the web app). Rollback: Netlify → Deploys → Publish an earlier deploy.
- **Edge Functions** (`supabase/functions/`: `places` for Google place search, #73; `fill-activity` for "Fill from link" with Claude, #74, bought through the reseller AIML API via `ANTHROPIC_BASE_URL` until its credits run out, then direct from Anthropic (`docs/deployment.md`); shared code in `_shared/`) reach the cloud only via `supabase functions deploy <name>` and their keys via `supabase secrets set`, both run by the owner, before the web deploy that needs them; say so in the PR. Outside APIs that cost money are capped per user per day in the database (`consume_api_quota`).
- Agents start a deploy only when the owner asks for one in chat. Before starting it, check whether anything merged since the last deploy adds migrations; if so, remind the owner to run `supabase db push` first. Agents don't deploy by any other route, don't merge without the owner's go-ahead, don't run `supabase db push`, and don't sign up/sign in on the live site. Test locally.

## Local test data

- Seed accounts: `alice@dev.test` / `dev_alice`, `bob@dev.test` / `dev_bob`; the password is in `supabase/seed.sql`. Don't print it in chat.
- The local DB may hold the owner's own data. Check before any destructive change:
  `docker exec supabase_db_group-planner psql -U postgres -tAc "select username from profiles"`
- Each computer's local data is different and changes all the time. **Don't describe it in the docs** (no lists of test groups or accounts beyond the seed); query it when you need to know.

## Conventions

- Dart: Riverpod `FutureProvider` / `.family`; `AsyncBody` for loading and error states; `showError` and `friendlyError` for errors; `promptText` and `confirm` dialogs; Material 3. Models in `data/models.dart` with `fromJson` and a `columns` select string when they embed relations.
- SQL: snake_case; `timestamptz`; soft delete only for activities; composite FKs to keep rows inside one group (`(type_id, group_id)`, `(group_id, activity_id)`) or owned by one user (`(personal_type_id, owner_id)`).
- Comments explain *why*. Match the surrounding density.
- Git: `main` tracks `origin` (github.com/kangjin97/project1.0). Work is tracked in **GitHub Issues** and on the **EasyPlan project board** (https://github.com/users/kangjin97/projects/3; Todo → In Progress → Done): read one with `gh issue view <n>`, move its card with `./scripts/board.sh <n> progress` when you start, branch from `main` as `fix|feature|chore/<n>-short-name`, open a PR into `main` whose body starts `Closes #<n>` (template: `.github/pull_request_template.md`), and wait for **CI** (`.github/workflows/ci.yml`: analyze, Dart tests, pgTAP) to pass. Merge only when the owner says so; merging closes the issue and the board moves it to Done. Then delete the branch locally (GitHub deletes its copy on merge). `gh` is installed and signed in as kangjin97. New work you notice but don't do: raise an issue (with labels) rather than adding it to docs; it lands in Todo. Commit as `Ng Kang Jin <kangjin_97@hotmail.com>`: the repo config's `user.name` is "Kang Jin", so pass it explicitly (`git -c user.name="Ng Kang Jin" -c user.email=kangjin_97@hotmail.com commit ...`). Commit messages end with a `Co-Authored-By` line when an agent writes them; PR descriptions end with the Claude Code footer.

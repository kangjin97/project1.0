# EasyPlan

EasyPlan (repo: group-planner) is a web and mobile app for friends to plan things to do together. People collect activity ideas, share them into groups, label and organise them, and put them on each other's schedules.

- **App:** Flutter (web, iOS, Android) in [`app/`](app/)
- **Backend:** Supabase (Postgres, Auth, Storage, Row Level Security) in [`supabase/`](supabase/)
- **Product spec:** [`SPEC.md`](SPEC.md)
- **Live web app:** https://easyplan-hehe.netlify.app

## Status

| Area | State |
|---|---|
| Sign up / sign in (email + password, unique username) | Done |
| Groups: create, rename, leave, members, remove member | Done |
| Invites: by username/email search, by invite link or code | Done |
| Activities: create/edit/delete, price range, link, photos, history | Done |
| Sharing activities into groups, per-group activity types | Done |
| Personal labels and group type merging | Done |
| Search and filters (My activities, group activities) | Done |
| Schedules: my schedule (agenda / week / month), group schedule, clash warnings, events | Done |
| Profiles: picture, username, display name, bio, others' profiles, stats, email/password, changeable time zone | Done |
| Account deletion, forgot password, privacy policy page | Done |
| Release setup: app ID `com.kangjin.easyplan`, icon, Android signing, Netlify, build script | Done; see [`docs/deployment.md`](docs/deployment.md) |
| Web app deployed (Netlify + Supabase cloud) | Live at https://easyplan-hehe.netlify.app |
| Android / iOS store apps | Not yet built; see [`docs/deployment.md`](docs/deployment.md) |
| Notifications | **Database done, no UI yet** |
| Realtime updates | Publication configured, not used by the app yet |

See [`docs/ai/features.md`](docs/ai/features.md) for the detailed feature map. The backlog and bugs live in [GitHub Issues](https://github.com/kangjin97/project1.0/issues); see [`docs/development.md`](docs/development.md#git-workflow) for the issue → branch → pull request workflow.

## Quick start

Requires Flutter (stable, Dart ≥ 3.10), Docker, and the Supabase CLI. Full setup, including macOS-specific gotchas, is in [`docs/development.md`](docs/development.md).

```bash
supabase start              # local Postgres, Auth, Storage on :54321 (first run pulls Docker images)
cd app && flutter pub get
flutter run -d chrome       # or: flutter run -d web-server --web-port 3000
```

Sign in with a seeded test account (`alice@dev.test` or `bob@dev.test`; the password is in [`supabase/seed.sql`](supabase/seed.sql)), or create a new account.

Run the database tests:

```bash
supabase test db
```

## Repository layout

```text
SPEC.md                         Product rules and decisions
CLAUDE.md, AGENTS.md            Steering notes for AI coding agents
.github/                        Issue forms, PR template, CI workflow (analyze, tests, pgTAP)
netlify.toml                    Web hosting config (publishes app/build/web)
scripts/build.sh                Release builds (web / android / ios) from app/env/prod.json
docs/
  development.md                Setup, workflows, troubleshooting
  deployment.md                 Supabase cloud, Netlify, Google Play, App Store
  architecture.md               How the app and backend fit together
  database.md                   Tables, triggers, functions, policies
  ai/                           Machine-friendly references (endpoints, feature map, decisions)
app/                            Flutter app
  lib/main.dart                 Entry point (Supabase init, ProviderScope)
  lib/config.dart               Supabase URL/key (dart-define overridable)
  lib/router.dart               go_router routes and auth redirect
  lib/data/                     Models and repositories (all Supabase access)
  lib/features/<area>/          Screens and widgets per feature
  lib/widgets/                  Shared widgets and dialogs
supabase/
  config.toml                   Local stack config
  migrations/                   Schema, RLS, triggers, RPCs (source of truth)
  seed.sql                      Local test accounts
  tests/database/               pgTAP tests
```

## Documentation

| For | Read |
|---|---|
| Getting the project running | [`docs/development.md`](docs/development.md) |
| Deploying to the web and app stores | [`docs/deployment.md`](docs/deployment.md) |
| Understanding the design | [`docs/architecture.md`](docs/architecture.md) |
| Working on the database | [`docs/database.md`](docs/database.md) |
| What each feature does and where it lives | [`docs/ai/features.md`](docs/ai/features.md) |
| Every table operation and RPC the app uses | [`docs/ai/endpoints.md`](docs/ai/endpoints.md) |
| Why things are the way they are | [`docs/ai/decisions.md`](docs/ai/decisions.md) |

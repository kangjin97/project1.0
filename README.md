# EasyPlan

EasyPlan (repo: group-planner) is a web and mobile app for friends to plan things to do together. People collect activity ideas, share them into groups, label and organise them, and put them on each other's schedules.

- **App:** Flutter (web, iOS, Android) in [`app/`](app/)
- **Backend:** Supabase (Postgres, Auth, Storage, Row Level Security) in [`supabase/`](supabase/)
- **Product spec:** [`SPEC.md`](SPEC.md)
- **Live web app:** https://easyplan-hehe.netlify.app
- **Work tracking:** [Issues](https://github.com/kangjin97/project1.0/issues) and the [EasyPlan project board](https://github.com/users/kangjin97/projects/3)

## Status

| Area | State |
|---|---|
| Sign up / sign in (email + password, unique username) | Done |
| Groups: create, rename, leave, members, remove member, delete group, hand over ownership | Done |
| Invites: by username/email search, by invite link or code; members can see and revoke links and cancel pending invitations | Done |
| Activities: create/edit/delete, price range, link, photos, history; locations picked from Google Maps | Done |
| Sharing activities into groups, per-group activity types | Done |
| Personal labels and group type merging | Done |
| Search and filters (My activities, group activities): text, label/type, sharing, budget, added by, has a link, has photos | Done |
| Schedules: my schedule (agenda / week / month, earlier weeks, past plans muted, drag to reschedule on wide screens), group schedule, clash warnings, events | Done |
| Profiles: picture, username, display name, bio, others' profiles, stats, email/password, changeable time zone | Done |
| Account deletion, forgot password, privacy policy page | Done |
| Release setup: app ID `com.kangjin.easyplan`, icon, Android signing, Netlify, build script | Done; see [`docs/deployment.md`](docs/deployment.md) |
| Web app deployed (Netlify + Supabase cloud) | Live at https://easyplan-hehe.netlify.app; deployed from `main` on request ([`docs/deployment.md`](docs/deployment.md#deploying-the-web-app)) |
| Android / iOS store apps | Not yet built; see [`docs/deployment.md`](docs/deployment.md) |
| Notifications | Done: Alerts tab with a live unread badge |
| Group history: who did what in a group, with links to the activity, plan or person | Done |
| Live updates: other people's changes appear without refreshing | Done (Supabase Realtime broadcasts) |

See [`docs/ai/features.md`](docs/ai/features.md) for the detailed feature map. The backlog and bugs live in [GitHub Issues](https://github.com/kangjin97/project1.0/issues); see [`docs/development.md`](docs/development.md#git-workflow) for the issue → branch → pull request workflow.

## Quick start

Requires Flutter 3.47.6, Docker and Supabase CLI 2.119.0 (the versions CI uses). Set up a computer with [`docs/setup-mac.md`](docs/setup-mac.md) or [`docs/setup-windows.md`](docs/setup-windows.md); then see [`docs/development.md`](docs/development.md).

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
CLAUDE.md, AGENTS.md            Steering notes for AI coding agents (start of docs/ai/handover.md)
.claude/launch.json             Preview config for the Claude desktop app (attaches to :3000)
.github/                        Issue forms, PR template, CI workflow (analyze, tests, pgTAP)
netlify.toml                    Web hosting config (publishes app/build/web)
scripts/build.sh                Release builds (web / android / ios) from app/env/prod.json
scripts/board.sh                Move an issue's card on the project board (todo / progress / done)
docs/
  development.md                Setup, workflows, troubleshooting
  deployment.md                 Supabase cloud, Netlify, Google Play, App Store
  setup-mac.md                  Setting up a Mac (pinned Flutter + Supabase CLI, Docker)
  setup-windows.md              Setting up a Windows PC (also WSL 2), terminals, deploying from Windows
  architecture.md               How the app and backend fit together
  database.md                   Tables, triggers, functions, policies
  ai/                           Machine-friendly references (handover, endpoints, feature map, decisions)
app/                            Flutter app
  lib/main.dart                 Entry point (Supabase init, ProviderScope)
  lib/config.dart               Supabase URL/key and APP_URL (dart-define overridable); invite and privacy links
  lib/router.dart               go_router routes and auth redirect
  lib/data/                     Models, repositories (Supabase access), AppClock
  lib/features/<area>/          Screens and widgets per feature
  lib/widgets/                  Shared widgets and dialogs
  test/                         Dart unit tests
  web/                          index.html, privacy.html, _redirects (all paths → app)
  env/prod.example.json         Template for the git-ignored release config
  deploy/well-known/            App Links / Universal Links templates
  assets/icon/                  App icon source
supabase/
  config.toml                   Local stack config
  migrations/                   Schema, RLS, triggers, RPCs (source of truth)
  functions/                    Edge Functions (Deno), e.g. places (Google place search); keys in a git-ignored .env
  seed.sql                      Local test accounts
  templates/                    Auth email templates (local; cloud copy pasted by hand)
  tests/database/               pgTAP tests
```

## Documentation

| For | Read |
|---|---|
| Picking the project up (new maintainer or AI) | [`docs/ai/handover.md`](docs/ai/handover.md) |
| Getting the project running | [`docs/development.md`](docs/development.md) |
| Deploying to the web and app stores | [`docs/deployment.md`](docs/deployment.md) |
| Understanding the design | [`docs/architecture.md`](docs/architecture.md) |
| Working on the database | [`docs/database.md`](docs/database.md) |
| What each feature does and where it lives | [`docs/ai/features.md`](docs/ai/features.md) |
| Every table operation and RPC the app uses | [`docs/ai/endpoints.md`](docs/ai/endpoints.md) |
| Why things are the way they are | [`docs/ai/decisions.md`](docs/ai/decisions.md) |

# Handover

Read this first if you're picking EasyPlan up without the history of earlier sessions: a new AI agent, a new account, or a new developer. It holds what used to live only in chat and in local agent memory. Then read [`CLAUDE.md`](../../CLAUDE.md) (rules and gotchas) and follow its "Where to look" table.

Last updated: 2026-10-16.

## The project in one paragraph

EasyPlan is a Flutter web/mobile app (`app/`) on Supabase (`supabase/`) for friends planning things together: activity ideas, groups, labels and type merging, shared schedules with clash checks. There is no custom server; every rule is in Postgres (RLS, grants, triggers, `security definer` RPCs) with pgTAP tests. The web app is live; it's deployed from `main` only when the owner asks (see "Working agreements"). Phone store apps are not built yet. The product spec is [`SPEC.md`](../../SPEC.md); what's built is [`features.md`](features.md).

## The owner

- **Ng Kang Jin**, GitHub `kangjin97`, based in Singapore. Commits are authored as `Ng Kang Jin <kangjin_97@hotmail.com>`.
- Works on **both a Mac and a Windows 11 PC**: [`setup-mac.md`](../setup-mac.md), [`setup-windows.md`](../setup-windows.md), [`development.md`](../development.md#working-on-both-computers).
- Tests by hand: locally against seed data, and on their phone against the live site.

## Services and accounts

All accounts belong to the owner. **No secrets are stored in the repo or in this file**; where a secret lives is noted instead. Never ask the owner to paste a password, key or token into chat.

| Service | What | Where secrets live |
|---|---|---|
| GitHub | Repo `kangjin97/project1.0`; Issues; board https://github.com/users/kangjin97/projects/3; Actions CI + deploy | Actions secrets `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`, `NETLIFY_AUTH_TOKEN`, `NETLIFY_SITE_ID`; variable `APP_URL` |
| Supabase (cloud) | Postgres, Auth, Storage. Region Singapore. Project URL `https://xxdbjszumfwbipniimbd.supabase.co` (public: it's in the web bundle) | Database password and dashboard login: owner |
| Netlify | Hosts the web app, project `easyplan-hehe` → https://easyplan-hehe.netlify.app | Owner's Netlify login; deploy token is a GitHub secret |
| Resend | Sends auth emails via Supabase custom SMTP, from `no-reply@easyplanhehe.online`; region Tokyo | API key is the SMTP password, entered only in Supabase |
| Namecheap | Domain `easyplanhehe.online` (DNS for Resend; email forwarding on). The web app does **not** use this domain yet | Owner's Namecheap login |
| Gmail | `easyplanhehe@gmail.com`: public contact in the privacy policy; Resend account email | Owner |
| Google Cloud | Project with **Places API (New)** for place search (#73); billing account and budget alert (owner, 2026-10-16) | API key (restricted to Places API (New)): `supabase/functions/.env` on each computer (git-ignored) and the Supabase secret `GOOGLE_MAPS_API_KEY` |
| Google Play / Apple | Not set up yet (#13, #14) | — |

Settings that exist only in dashboards, and how to redo them, are in [`deployment.md`](../deployment.md) §1 (Supabase auth URLs, SMTP, rate limits, email templates, DNS).

## Current state (2026-10-16)

**Where things are**
- **Live site:** deployed 2026-10-15 from `main` at `e2534a6` (the second on-request deploy; the first was `5fb615c`). Everything on `main` is live.
- **On `main` but not live yet:** recurring plans (#17, merged 2026-10-15 in `e085ba6`). Check with `git log --oneline e2534a6..origin/main`.
- **Cloud database** (checked 2026-10-15): has every migration through `20261015064456_log_type_merge_updates.sql`. **Waiting for `supabase db push`** (owner, before the next deploy): `20261015083758_recurring_plans.sql` and `20261015083759_recurring_history.sql` (#17). Check with `supabase migration list --linked` (both computers are linked).
- **In flight** (2026-10-16): the PR for #73 (Google Maps locations). Before the deploy that ships it, the owner must run `supabase db push` (`20261016044829_place_search.sql`), `supabase secrets set GOOGLE_MAPS_API_KEY=...` and `supabase functions deploy places` (`deployment.md` → Edge Functions and Google Maps). #74 (AI fill from a link) is next; its decisions are on the issue. Always check `gh pr list` and the board's In Progress column.
- **Deploys are on request only** (since 2026-10-15, #45): merging to `main` doesn't deploy. See "Working agreements" below.

**What's built** (details per feature in [`features.md`](features.md))
- Everything in SPEC §6 build order: accounts, groups and invites, activities with labels and type merging, search, schedules with clash checks, events, profiles, account deletion, notifications.
- Added on 2026-10-15:
  - **Group history** (#8): group page ⋮ → History. It includes activity edits made while the activity was shared there, and lines open what they're about. F10.
  - **Live updates** (#7): other people's changes appear on open screens silently, and the Alerts badge is live. It uses database broadcasts to private Realtime channels. F13. When adding a table that a screen shows, add a `broadcast_change` trigger and a `providersAffectedBy` case (CLAUDE.md rule 6).
  - **Past plans on phones** (#11): "Show earlier" on schedule lists, and plans that are over are muted. F8.
  - **Delete a group and hand over ownership** (#10): group ⋮ → Delete group (warning with counts, type the name; members notified); Members → ⋮ → Make owner (immediate, notified, in history). F2.
  - **Drag to reschedule** (#12) in the week view on wide screens: 15-minute snapping, same clash dialog, Undo. F8.
  - **"Has link" / "Has photos" filters** (#53) on My activities and the group Activities tab. F7.
  - **Repeating plans** (#17): weekly, every 2 weeks or monthly until a date (at most a year); "this date only" or "this and later dates" for every edit; Extend; one notification per series; one history line per series action. F8.
  - **Invite management** (#9): the Members tab lists active links (Revoke) and pending invitations (Cancel). Any member can do both; it's logged in group history and updates live. F3.
  - **Google Maps locations** (#73, PR open): the Location field suggests real places (through the `places` Edge Function, the first one; 100 searches per person per day); the picked place ID opens the exact pin in Google Maps. F4.
- **Auth emails** go through Resend, with EasyPlan templates from `supabase/templates/` (*Confirm signup*, *Reset password*, *Change email address*). The cloud copies are pasted by hand; if the dashboard and the files ever disagree, the files are the intended version.
- **Privacy policy:** live at `/privacy.html`.

**Not built yet** (`gh issue list`): AI fill from a link (#74, after #73), store apps (#13, #14), app icon (#15), server-side search (#16), push notifications (#18).

**Next priorities**
1. `priority:high`: #5 phone smoke test together with #49 (live updates on two phones, step by step) on the live site, covering everything deployed on 2026-10-15 (#7–#12, #52, #53, the #58 fix).
2. The backlog: #15 the app icon (needs the owner's direction), then the store apps (#13, #14) or v2 items (#16 server-side search, #18 push).

**Computers**
- Both the Mac and the Windows 11 PC are set up ([`setup-mac.md`](../setup-mac.md), [`setup-windows.md`](../setup-windows.md)).
- Each has its own local database. The only data you can count on is the seed accounts from `supabase/seed.sql` (`dev_alice`, `dev_bob`); anything else is test data made by hand on that computer, and it differs between computers and from day to day. Check what's there rather than assuming:
  - accounts and groups: `docker exec supabase_db_group-planner psql -U postgres -tA -c "select 'account: ' || username from profiles order by 1" -c "select 'group: ' || name from groups order by 1"`
  - migrations: `supabase migration list --local`. A computer's database can lag behind `main` when work was merged from the other computer; `supabase migration up` catches it up and keeps the data.

**Docs**
- Audited against the code on 2026-10-14. The code-level gaps it found became issues and are fixed: #19 (function grants and `search_path`, now guarded by `function_privileges.test.sql`) and #38 (all Supabase calls go through repositories).
- Audited again on 2026-10-15 after #44, #45, #8, #7, #11 and #9:
  - every reference doc checked line by line against the code, migrations and tests;
  - status checked against the open issues, PRs, migrations and the cloud;
  - every documented path and section link checked.
- Status sections re-checked on 2026-10-15 after #57, #10 and #58 (#61), again after #53, #52 and #12 (#66), and after #17 (#72): deploy state, cloud migrations (`supabase migration list --linked`), open issues and PRs.

## How to resume work

1. Set up the computer ([`setup-mac.md`](../setup-mac.md) or [`setup-windows.md`](../setup-windows.md)), then `supabase start`, `supabase test db`, `cd app && flutter analyze && flutter test`.
2. Check what's in progress: `gh pr list`, `gh issue list`, and the board.
3. For any task: issue → `./scripts/board.sh <n> progress` → branch `fix|feature|chore/<n>-name` from `main` → PR with `Closes #<n>` → CI green → **the owner merges** → delete the branch locally and on GitHub. Details: [`development.md`](../development.md#git-workflow). The live site updates only when the owner asks for a deploy.

## Working agreements with the owner

These come from the owner's instructions and from how sessions have gone. They are in addition to the hard rules in `CLAUDE.md`.

- **Develop and test locally.** The local stack is where features are built and checked; the live site is not a test environment.
- **The owner merges.** Agents open PRs and wait. Agents never run `supabase db push` and never sign up or sign in on the live site.
- **Deploys happen only when the owner asks** (since 2026-10-15; each Netlify deploy costs credits). Merging to `main` doesn't deploy. When the owner says to deploy, usually at the end of the day: check whether anything merged since the last deploy adds migrations (if so, the owner runs `supabase db push` first), then run `gh workflow run ci.yml --ref main`, watch it, and report the result. Never start one on your own. Steps: [`deployment.md`](../deployment.md#deploying-the-web-app).
- **Dashboard steps are the owner's.** When a change needs something in Supabase, Resend, Namecheap, Netlify, Google Cloud or GitHub settings (including `supabase secrets set` and `supabase functions deploy`), put the exact steps in the PR description and in `deployment.md`, and tell the owner. Examples: pasting an email template, `supabase db push` for a migration (before the next deploy), DNS records.
- **Every bug or follow-up gets an issue**, even small ones found while testing, before it's fixed. Don't park work in docs or chat.
- **Explain options with a recommendation**; the owner decides on cost, accounts and product questions (e.g. which email provider, buying a domain).
- **Verify before claiming.** Run the checks, test in the browser where possible, and say plainly what wasn't tested (often "on the phone, after deploy").
- **Fix gaps; don't just list them.** If a feature has a gap you can close in reach of the same PR, close it there. Don't ship it as a "known gap". If it's genuinely out of scope or needs a product decision, ask the owner first, and raise an issue if they want it later. (The owner pushed back on #8's first PR listing fixable gaps.)
- **Ask product questions before building.** When a choice changes what gets built (e.g. what a group may see, where a screen lives), ask with a recommended option at the start, not halfway through.
- **Don't record local database contents in the docs** (which groups, plans or test accounts exist on a computer). It changes every session and differs per computer, so it's wrong as soon as it's written. Document how to check instead. Production state (what's deployed, which migrations are pushed) is fine to record, with the date and a way to check it.
- **Keep docs current in the same PR** as the change: `features.md`, `endpoints.md`, `database.md`, `SPEC.md`, `decisions.md`, `deployment.md` as relevant.

## Pitfalls that already happened

- **Stacked PRs merged into the wrong branch** (#30). The repo's "Automatically delete head branches" setting was off then, so GitHub didn't retarget the PR above to `main`. It's on now (since 2026-10-15): merged branches are deleted on GitHub automatically, and GitHub retargets a stacked PR when its base branch goes. Still avoid stacking. After a merge, only the local branch needs deleting (`git branch -D <branch>`).
- **`supabase db reset` wiped the owner's data once.** Use `supabase migration up`.
- **Auth email links land on the site root** with `?code=`, `?message=` or `?error_description=`. The router's `/` redirect handles them; removing it brings back a "no routes for location" crash.
- **Email templates and dashboard settings don't deploy from git.** Changing `supabase/templates/*` or `config.toml` affects only the local stack.
- **A domain email needs DNS you control**: `*.netlify.app` can't be used for sending. Namecheap DNS: Host is the part before the domain; a CNAME and MX can't share a name.
- **Windows:** Docker Desktop doesn't start on its own after a reboot (start it, then `supabase start`); terminals opened before an install don't see new PATH entries; PowerShell 5.1 has no `&&`. The Claude preview pane doesn't draw Flutter web while it's hidden, so screenshots and clicks time out: use API checks against the local stack, or ask the owner to bring the window forward.
- **Windows: `supabase test db` says `docker: command not found`** in an agent shell started before Docker was installed. Prepend `$env:ProgramFiles\Docker\Docker\resources\bin` to PATH for that command (or have the owner restart the Claude app).
- **A dev server an agent starts in the background can't hot-reload** (nothing can type `r`/`R` into it). After Dart changes, stop whatever listens on port 3000 and run `flutter run -d web-server …` again; reloading the page alone keeps the old code.
- **Changing a migration that hasn't left this computer** (still in an open PR, not pushed to the cloud): edit the file, then drop what it created and forget the version, and re-apply: `docker exec supabase_db_group-planner psql -U postgres -c "drop function …" -c "delete from supabase_migrations.schema_migrations where version = '<version>'"`, then `supabase migration up`. Once a migration is merged or pushed, never edit it (CLAUDE.md rule 3); add a new one.
- **Testing with two people signed in at once:**
  - Tabs on the same address share one session, and the debug dev server only starts the app in one tab.
  - So run a second server as a **profile** build on another port: `flutter run --profile -d web-server --web-hostname 127.0.0.1 --web-port 3001`. Release builds refuse the local backend; profile builds don't.
  - Sign in as `dev_alice` on :3000 and `dev_bob` on :3001. Profile builds don't hot-reload either; restart after changes.
  - To simulate a dropped connection: `docker stop supabase_realtime_group-planner`, make a change, then `docker start` it. The open app should catch up once its channels rejoin.
  - You can also play the other person from the database, acting as them through RLS (`set role authenticated` + `set_config('request.jwt.claims', …)` in `psql` via `docker exec -i supabase_db_group-planner psql -U postgres`).
  - Either way, screens should change within about 2 s without a reload. In pgTAP, call `set_config('easyplan.broadcasts_sent', '', true)` between steps, because the whole test is one transaction and the trigger sends once per topic and table per transaction.
- **Dragging in the Claude preview pane** (e.g. testing #12's week view): the browser tool's drag is a single jump, which Flutter doesn't treat as a drag, and its clicks can miss small buttons when the viewport is scaled. Send pointer events from JavaScript instead, as a pointerdown, ~30 pointermoves 16 ms apart and a pointerup, on `document.querySelector('flutter-view')`. Multiply CSS coordinates by `devicePixelRatio`, since Flutter reads synthetic events in device pixels. Emulate a wide viewport no bigger than the pane (e.g. 900×650); larger ones get scaled down. Check the result in the database, not just the screen.
- **Rows in one transaction share `now()`**, so `created_at` can't order them (pgTAP tests run in one transaction). Order change-log rows by `change_log.id`, as `list_group_history` does.

## Open questions for the owner

From [`decisions.md`](decisions.md) ("Choices made on the owner's behalf") and [`SPEC.md`](../../SPEC.md) §7. Raise them when they become relevant rather than all at once. The ones most likely to come up next:
- Any member can remove an activity from a group (and its plans there become events). Should that stay open to every member?
- Labels match group types by exact name only (ignoring case and spaces), with no fuzzy "similar" matching.

# Handover

Read this first if you're picking EasyPlan up without the history of earlier sessions: a new AI agent, a new account, or a new developer. It holds what used to live only in chat and in local agent memory. Then read [`CLAUDE.md`](../../CLAUDE.md) (rules and gotchas) and follow its "Where to look" table.

Last updated: 2026-10-15.

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
| Google Play / Apple | Not set up yet (#13, #14) | — |

Settings that exist only in dashboards, and how to redo them, are in [`deployment.md`](../deployment.md) §1 (Supabase auth URLs, SMTP, rate limits, email templates, DNS).

## Current state (2026-10-15)

- **Live:** web app with all features in `features.md` marked Done. Cloud database is up to date with `supabase/migrations/` (last: `20261014085422_list_notifications.sql`; checked with `supabase migration list --linked` on 2026-10-15). Both computers are linked to the cloud project.
- **Deploys are on request only** (since 2026-10-15, #45): merging to `main` no longer deploys. See "Working agreements" below.
- **Both computers are set up:** the Windows 11 PC got Flutter 3.47.6, Supabase CLI 2.119.0, WSL 2 and Docker on 2026-10-15; its local database holds only the seed accounts.
- **Auth emails:** through Resend, with EasyPlan templates from `supabase/templates/` for *Confirm signup*, *Reset password* and *Change email address*. The cloud copies are pasted by hand; if the dashboard and the files ever disagree, the files are the intended version.
- **Privacy policy:** live at `/privacy.html`.
- **In flight at the time of writing:** the PR for #45 and #44 (on-request deploys; Windows setup fixes). Always check `gh pr list` and the board's In Progress column.
- **Docs were audited against the code on 2026-10-14** (endpoints, database, features, architecture, README, SPEC, setup and deployment guides) and fixed. Code-level gaps it found became issues and are fixed: #19 (function grants and `search_path`; now guarded by `function_privileges.test.sql`) and #38 (all Supabase calls go through repositories).
- **Notifications** (#6): Alerts tab with an unread badge; no realtime yet (#7).
- **Not built:** realtime (#7), group history view (#8), invite management (#9), store apps (#13, #14). Full list: `gh issue list`.
- **Next priorities (owner's labels):** `priority:high` issues first: #5 phone smoke test. Then features from the backlog (`gh issue list`), e.g. #7 realtime (would make the badge live) or #8 group history.

## How to resume work

1. Set up the computer ([`setup-mac.md`](../setup-mac.md) or [`setup-windows.md`](../setup-windows.md)), then `supabase start`, `supabase test db`, `cd app && flutter analyze && flutter test`.
2. Check what's in progress: `gh pr list`, `gh issue list`, and the board.
3. For any task: issue → `./scripts/board.sh <n> progress` → branch `fix|feature|chore/<n>-name` from `main` → PR with `Closes #<n>` → CI green → **the owner merges** → delete the branch locally and on GitHub. Details: [`development.md`](../development.md#git-workflow). The live site updates only when the owner asks for a deploy.

## Working agreements with the owner

These come from the owner's instructions and from how sessions have gone. They are in addition to the hard rules in `CLAUDE.md`.

- **Develop and test locally.** The local stack is where features are built and checked; the live site is not a test environment.
- **The owner merges.** Agents open PRs and wait. Agents never run `supabase db push` and never sign up or sign in on the live site.
- **Deploys happen only when the owner asks** (since 2026-10-15; each Netlify deploy costs credits). Merging to `main` doesn't deploy. When the owner says to deploy, usually at the end of the day: check whether anything merged since the last deploy adds migrations (if so, the owner runs `supabase db push` first), then run `gh workflow run ci.yml --ref main`, watch it, and report the result. Never start one on your own. Steps: [`deployment.md`](../deployment.md#deploying-the-web-app).
- **Dashboard steps are the owner's.** When a change needs something in Supabase, Resend, Namecheap, Netlify or GitHub settings, put the exact steps in the PR description and in `deployment.md`, and tell the owner. Examples: pasting an email template, `supabase db push` for a migration (before the next deploy), DNS records.
- **Every bug or follow-up gets an issue**, even small ones found while testing, before it's fixed. Don't park work in docs or chat.
- **Explain options with a recommendation**; the owner decides on cost, accounts and product questions (e.g. which email provider, buying a domain).
- **Verify before claiming.** Run the checks, test in the browser where possible, and say plainly what wasn't tested (often "on the phone, after deploy").
- **Keep docs current in the same PR** as the change: `features.md`, `endpoints.md`, `database.md`, `SPEC.md`, `decisions.md`, `deployment.md` as relevant.

## Pitfalls that already happened

- **Stacked PRs merged into the wrong branch.** The repo's "Automatically delete head branches" setting is off, so when a lower PR merges, GitHub does not retarget the PR above it to `main`; it merges into the stale branch. Avoid stacking; if you must, change the upper PR's base to `main` yourself after the lower one merges (or ask the owner to turn the setting on).
- **`supabase db reset` wiped the owner's data once.** Use `supabase migration up`.
- **Auth email links land on the site root** with `?code=`, `?message=` or `?error_description=`. The router's `/` redirect handles them; removing it brings back a "no routes for location" crash.
- **Email templates and dashboard settings don't deploy from git.** Changing `supabase/templates/*` or `config.toml` affects only the local stack.
- **A domain email needs DNS you control**: `*.netlify.app` can't be used for sending. Namecheap DNS: Host is the part before the domain; a CNAME and MX can't share a name.
- **Windows:** Docker Desktop doesn't start on its own after a reboot (start it, then `supabase start`); terminals opened before an install don't see new PATH entries; PowerShell 5.1 has no `&&`. The Claude preview pane doesn't draw Flutter web while it's hidden, so screenshots and clicks time out: use API checks against the local stack, or ask the owner to bring the window forward.

## Open questions for the owner

From [`decisions.md`](decisions.md) ("Choices made on the owner's behalf") and [`SPEC.md`](../../SPEC.md) §7. Raise them when they become relevant rather than all at once.

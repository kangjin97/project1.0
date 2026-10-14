# Decisions log

Product and technical decisions, with the reason. Newest last. When a decision changes, add a new entry rather than editing the old one.

## Product (from the project owner)

| Date | Decision |
|---|---|
| 2026-10-02 | When sharing, the sharer picks the activity's type; any member may change it afterwards. |
| 2026-10-02 | An activity is one shared record. The owner and members of any group it's in can edit it, and edits reach every group and the owner's copy ("corrections like price or address should reach everyone"). |
| 2026-10-02 | Adding people to a schedule entry adds them automatically. On a clash, both the planner and the clashing members are told, and the planner chooses whether to proceed. |
| 2026-10-02 | Entries have start and end times, or are all-day. An all-day entry clashes with everything that day. |
| 2026-10-02 | Prices are real amounts (min/max + currency), not $/$$ tiers. |
| 2026-10-02 | Events are ad-hoc placeholders ("eat some steak") created inside a group, like a schedule entry without an activity. Any member may replace an event with an activity, or one activity with another. Every change is logged so it's traceable who planned what. |
| 2026-10-02 | People join by invite link or by direct invite (search username or email). |
| 2026-10-02 | Only the owner can delete an activity. Members can remove activities from the group schedule. |
| 2026-10-09 | Activities get personal labels. When shared, the label becomes the group type. |
| 2026-10-09 | Groups can **merge** types (e.g. "yummy" + "goodfood" → "Food"); activities with those labels, existing and future, go to the merged type. |
| 2026-10-09 | If the owner changes the label later, the activity is re-filed in every group automatically (into a merged type where one applies). |

| 2026-10-09 | Schedule: My schedule offers List / Week / Month on every screen size (phones default to List). The group Schedule tab shows everyone's plans with the user's highlighted, and "no date yet" events as ideas at the top. |
| 2026-10-09 | Notifications UI is its own branch, not part of the schedule feature. |
| 2026-10-09 | Profiles: picture, username (if not taken), bio; plus viewing others' profiles, editable display name, account settings (email, password, sign out) and profile stats. |
| 2026-10-09 | Time zone is set at sign-up from the device and changeable on the profile from a list labelled with UTC offsets and regions (UTC rather than GMT). The whole app shows times in the profile's zone, not the device's. |

| 2026-10-12 | The app is named **EasyPlan**, app ID `com.kangjin.easyplan`; web hosting on **Netlify**. |
| 2026-10-12 | Web app published at **https://easyplan-hehe.netlify.app** (Netlify project `easyplan-hehe`; `easyplan` was taken). Deploys were manual drag-and-drop at first (superseded by continuous deployment, below). |
| 2026-10-12 | Deleting an account: groups pass to the longest-standing member (empty groups deleted); their activities and photos are deleted; plans that used them stay as events; history shows "deleted user". |
| 2026-10-13 | Privacy policy published: effective 13 October 2026, contact easyplanhehe@gmail.com (a dedicated Gmail; no custom domain yet), data in Supabase's Singapore region; it mentions hosting providers' server logs. |

## Choices made on the owner's behalf (confirm or revise)

| Date | Choice | Reason |
|---|---|---|
| 2026-10-02 | Deleting an activity turns its schedule entries back into events named after it. | Plans shouldn't silently disappear. |
| 2026-10-02 | Unsharing an activity from a group also turns that group's entries for it into events. | Same reason. |
| 2026-10-02 | Any member can remove an activity from a group. | Matches "members can remove activities". |
| 2026-10-02 | Clash-check results hide entry titles from groups the planner isn't in ("Busy"). | Privacy across groups. |
| 2026-10-02 | New groups get starter types Food, Outdoors, Entertainment, Other. | So sharing works immediately. |
| 2026-10-02 | Default currency SGD; invite links last 7 days. | The owner is in Singapore. |
| 2026-10-09 | Labels match group types and merge rules by name, ignoring case and surrounding spaces. No fuzzy "similar" matching. | Predictable. |
| 2026-10-09 | Merging is retroactive: existing activities move too. Undoing a merge sends activities that arrived with that label back to a same-name type. | Consistent with "merged category". |
| 2026-10-09 | A label change overrides a member's manual type change. | The owner said the group type follows the label "automatically". |
| 2026-10-09 | Deleting a label leaves activities' group types unchanged. | Avoids surprising moves. |
| 2026-10-09 | Labels are private to their owner; members see only the group type. | They're personal. |
| 2026-10-09 | Profile stats are visible only to the profile's owner; other people's profiles show picture, names, bio and the groups you share, and are reachable only from shared groups. | Privacy. |
| 2026-10-09 | Bio limit 160 characters; display name 50. | Fits a profile header. |
| 2026-10-09 | Avatars are in a private bucket readable by any signed-in user, writable only in your own folder. | Same visibility as profiles. |
| 2026-10-12 | Delete account is confirmed by typing your username. | Irreversible action. |
| 2026-10-12 | The same ownership hand-over applies when an owner simply leaves a group. | Groups were left ownerless before. |
| 2026-10-12 | Password-reset links open the web app (`APP_URL`), even for phone-app users. | Works without deep-link setup; users then sign in on the app. |
| 2026-10-12 | Placeholder icon (white calendar + check on blue) until a designed one exists. | Stores need an icon; easy to replace. |
| 2026-10-09 | The time zone picker lists all IANA zones (including aliases like Asia/Calcutta) with current offsets, searchable by name or offset. | A plain dropdown of ~490 zones is unusable. |
| 2026-10-14 | Supabase's **secure email change** stays on: links go to both the old and new address, and the change needs both. The app's message, the profile and the email itself say so. | Someone with brief access to an account can't move it to their own email. The owner asked whether two emails were intended. |
| 2026-10-14 | A pending email change can be cancelled from the profile; cancelling voids the links already sent. The profile re-reads the account from the server (and on app resume) instead of trusting the session from sign-in. | A change someone gave up on otherwise stayed pending forever, and a change confirmed from the mail app only showed after signing in again. |

## Technical

| Date | Decision | Reason |
|---|---|---|
| 2026-10-02 | Flutter + Supabase, no custom server. | One codebase for web and mobile; Postgres RLS gives per-group security without a backend. |
| 2026-10-02 | Every rule lives in the database (RLS, grants, triggers, `security definer` RPCs). | Clients can't bypass rules; one place to test (pgTAP). |
| 2026-10-02 | `change_log` is written by triggers and has no foreign keys. | Logging can't be skipped, and history survives deletes. |
| 2026-10-02 | Schedule times change only through RPCs (column grants). | Clash checks can't be bypassed. |
| 2026-10-02 | Emails live only in `auth.users`; lookup is exact-match only. | Avoids exposing or enumerating addresses. |
| 2026-10-02 | Private photo bucket with signed URLs; access follows `can_access_activity`. | Photos are as private as their activity. |
| 2026-10-09 | Riverpod `FutureProvider`s with explicit invalidation, no realtime yet. | Simple; realtime is a later step. |
| 2026-10-09 | Search and filters run client-side. | Friend-group sizes; revisit if lists grow. |
| 2026-10-09 | Apply local migrations with `supabase migration up`, never `db reset` without asking. | A reset wiped the owner's manual test data once. |
| 2026-10-09 | `list_schedule` RPC as the schedule read model. | Mixed date/timestamp windows and joined names don't fit plain table queries. |
| 2026-10-09 | `AppClock` + `package:timezone` (`latest_all`) for display-zone conversion; `TimezoneController` reloads the zone from the profile after sign-in. | Times must follow the profile zone everywhere; browsers report alias zone names. |
| 2026-10-12 | Path URL strategy instead of `#/` URLs; Netlify `_redirects` serves the app for every path. | Needed for App Links / Universal Links and nicer invite links. |
| 2026-10-12 | Production settings via `--dart-define-from-file=app/env/prod.json` (git-ignored) and `scripts/build.sh`; release builds refuse the local backend. | Keeps secrets and dev URLs out of releases. |
| 2026-10-09 | Work on `main`; short-lived feature branches (`feature/<name>`) merged back when accepted. | Owner's preference. |
| 2026-10-12 | Continuous deployment: every push to `main` deploys the web app to Netlify after CI passes; no PR preview deploys (they would share the live database); database migrations stay a manual `supabase db push` before merging. | Fast, safe releases without risking production data. |
| 2026-10-12 | GitHub Projects board **EasyPlan** (https://github.com/users/kangjin97/projects/3) with Todo → In Progress → Done; cards move to In Progress when work starts (`scripts/board.sh`) and to Done when the PR merges. | One visual view of what's next, in progress and finished. |
| 2026-10-12 | Backlog and bugs in GitHub Issues (labels `bug`, `feature`, `chore`, `priority:high`; issue forms); branches `fix\|feature\|chore/<n>-name`; PRs say `Closes #n`; CI runs analyze, Dart tests and pgTAP on every PR. | One place for work, linked to code; checks before merge. |
| 2026-10-13 | Development also happens on a Windows 11 PC. Its Flutter (3.47.6, a git clone of the tag) and Supabase CLI (2.119.0) are pinned to CI's versions; Docker Desktop runs on WSL 2. Same issue → branch → PR workflow; GitHub is the source of truth and each computer keeps its own local database; iOS builds stay on the Mac. Setup: `docs/setup-mac.md`, `docs/setup-windows.md`. | The owner works from both machines; matching CI's versions keeps results the same everywhere. |
| 2026-10-14 | Auth email templates are kept in `supabase/templates/` (used locally via `config.toml`) and pasted into the cloud dashboard by hand. | `supabase config push` would also push local-only settings; templates change rarely. |
| 2026-10-14 | `cancel_email_change()` writes `auth.users` directly (security definer, caller's row only). | Supabase Auth has no cancel API; `delete_my_account` already writes `auth.users` the same way. |

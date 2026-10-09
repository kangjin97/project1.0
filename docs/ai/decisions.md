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

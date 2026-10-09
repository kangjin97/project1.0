# CLAUDE.md — steering for AI agents

Group Planner: Flutter app (`app/`) + Supabase backend (`supabase/`) for friends planning activities together. Read this file first, then the doc that matches your task.

## Where to look

| Need | File |
|---|---|
| What the product must do | `SPEC.md` |
| What's built, where it lives, backlog | `docs/ai/features.md` |
| Every table op / RPC: params, returns, who, errors | `docs/ai/endpoints.md` |
| Why things are this way (incl. owner's answers) | `docs/ai/decisions.md` |
| Schema, triggers, policies | `docs/database.md`, `supabase/migrations/` |
| App structure, data flows | `docs/architecture.md` |
| Setup, commands, troubleshooting | `docs/development.md` |

## Commands

```bash
supabase start                      # local stack (Docker); API :54321, Studio :54323
supabase migration up               # apply new migrations, KEEPS data
supabase test db                    # pgTAP tests (rolled back; safe)
cd app && flutter analyze           # must report "No issues found!"
cd app && flutter run -d web-server --web-hostname 127.0.0.1 --web-port 3000
```

The Supabase CLI may be at `~/.local/bin/supabase` rather than on `PATH`.

## Hard rules

1. **Never run `supabase db reset`, or any other command that wipes the database, without asking the owner first.** They test by hand, and a reset once destroyed their account and data. Use `supabase migration up`.
2. **Rules belong in the database.** Access control and invariants go in RLS policies, column grants, triggers or `security definer` RPCs, with pgTAP tests. The app may hide UI, but must not be the only guard.
3. **Never edit an applied migration.** Add a new file under `supabase/migrations/` (`supabase migration new <name>`).
4. **New functions:** `security definer set search_path = ''`, fully qualified names (`public.x`). `revoke execute ... from public, anon`; also from `authenticated` for internal helpers.
5. **Supabase access only in `app/lib/data/*_repository.dart`.** Widgets use providers and repository methods.
6. **After every mutation, invalidate the affected providers** (`invalidateActivity`, `invalidateLabels`, or specific `ref.invalidate(...)`). Otherwise screens show stale data.
7. Before finishing: `flutter analyze` must be clean and `supabase test db` must pass. If you changed behaviour, update `docs/ai/features.md`, `docs/ai/endpoints.md` and, where relevant, `docs/database.md`, `SPEC.md` and `docs/ai/decisions.md`.
8. Don't commit or push unless asked.

## Gotchas (each has bitten this project)

- supabase-dart `.order(col)` is **descending by default**. Always pass `ascending:`.
- PostgREST `ilike` uses `*` as the wildcard; `%` didn't work through the client.
- `showModalBottomSheet` must use `useRootNavigator: true`, or the sheet sits under the bottom nav bar.
- Don't dispose a `TextEditingController` in `showDialog(...).whenComplete`; the closing animation still uses it (`_dependents.isEmpty` assertion). Let a `StatefulWidget` own it (see `_PromptDialog` in `widgets/dialogs.dart`).
- In policies, qualify outer columns in subqueries (`groups.id`, not `id`); unqualified names bind to the inner table.
- Inside `STABLE` SQL functions, rows inserted earlier in the same statement aren't visible. Write `insert ... returning` select policies inline (e.g. `owner_id = auth.uid()`), not through a helper.
- On Flutter web, `1 << 32` is 0. Keep `Random().nextInt` bounds ≤ `1 << 30`.
- Flutter web in the Claude preview pane:
  - Screenshots can show a stale frame. Hover, wait, and re-screenshot before concluding.
  - Typing straight after a click can land in the previously focused field. Wait ~0.5–1 s after clicking.
  - Engine assertions about "targeted input element" come from synthetic clicks; ignore them.
- Current Dart needs macOS ≥ 14.
- The preview launcher can't read `~/Documents` (macOS TCC). Start the dev server via Bash; `.claude/launch.json` attaches to `http://127.0.0.1:3000`.

## Local test data

- Seed accounts: `alice@dev.test` / `dev_alice`, `bob@dev.test` / `dev_bob`; the password is in `supabase/seed.sql`. Don't print it in chat.
- The local DB may hold the owner's own data. Check before any destructive change:
  `docker exec supabase_db_group-planner psql -U postgres -tAc "select username from profiles"`

## Conventions

- Dart: Riverpod `FutureProvider` / `.family`; `AsyncBody` for loading and error states; `showError` and `friendlyError` for errors; `promptText` and `confirm` dialogs; Material 3. Models in `data/models.dart` with `fromJson` and a `columns` select string when they embed relations.
- SQL: snake_case; `timestamptz`; soft delete only for activities; composite FKs to keep rows inside one group (`(type_id, group_id)`, `(group_id, activity_id)`) or owned by one user (`(personal_type_id, owner_id)`).
- Comments explain *why*. Match the surrounding density.
- Git: work on `main`, which tracks `origin` (github.com/kangjin97/project1.0). Use a short-lived branch only for risky or PR-reviewed work, and merge it back. Commit as `Ng Kang Jin <kangjin_97@hotmail.com>` (set in the repo config). Commit messages end with a `Co-Authored-By` line when an agent writes them.

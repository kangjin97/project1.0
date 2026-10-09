# Implementation Plan — Activities Feature

## Design decisions

- **`Activity.ownerId`** maps to the DB column `owner_id` (consistent with other model names like `Member.profile`).
- **`defaultActivityTypeId` is not stored in the DB.** The `activities` table has no such column. The field is accepted in `createActivity`/`updateActivity` signatures to match the spec, but it is silently dropped before the Supabase call. The create/edit sheet exposes only Name and Description — not a type dropdown — since there is nothing to persist.
- **`GroupActivity` has no UUID `id`.** The `group_activities` table uses a composite PK `(group_id, activity_id)`. The `unshareActivityFromGroup` method therefore takes `{required String groupId, required String activityId}` (not a single `groupActivityId` string). Call sites always have both values available via the `GroupActivity` object.
- **`deleteActivity` calls the DB RPC `delete_activity(p_activity)`.** The DB defines a security-definer function that removes the activity from all group_activities rows (triggering `revert_entries_to_events`) before soft-deleting it. A direct `UPDATE SET deleted_at = now()` would skip that cascade.
- **Group Activities tab uses a button inside the list, not a Scaffold FAB.** The Scaffold in `GroupPage` wraps all four tabs; adding a tab-specific FAB would require listening to the TabController. The existing `_TypesTab` and `_MembersTab` both put their primary action inside the ListView. The Activities tab follows the same pattern with a `FilledButton.icon` at the top of the list.
- **`friendlyError` is not redefined** in `activities_repository.dart`. It already lives in `groups_repository.dart` and is imported by all widgets that need it. The activities repo file imports it from there.

---

- [ ] 1. Extend `app/lib/data/models.dart` with `Activity` and `GroupActivity`.

      `Activity` fields: `id` (String), `ownerId` (String), `name` (String), `description` (String?), `createdAt` (DateTime), `photoUrls` (List<String>, hardcoded empty list — photos out of scope).
      `Activity.fromJson` parses: `id`, `owner_id` → ownerId, `name`, `description`, `created_at` → DateTime.parse.

      `GroupActivity` fields: `groupId` (String), `activityId` (String), `typeId` (String), `sharedById` (String), `sharedAt` (DateTime), `activity` (Activity), `typeName` (String?), `sharedByUsername` (String?).
      `GroupActivity.fromJson` parses: `group_id`, `activity_id`, `type_id`, `added_by` → sharedById, `added_at` → DateTime.parse, `activities` → Activity.fromJson, `activity_types` map → name, `sharer` map → username (the select alias used in the repository).

      Files: `app/lib/data/models.dart`
      Verify: `cd /Users/kangjin/Documents/group-planner/app && flutter build web --no-version-check` — exits 0, no errors.

- [ ] 2. Create `app/lib/data/activities_repository.dart` following `groups_repository.dart` exactly.

      Top of file: same `_db` / `_me` helpers. Import `models.dart` and `flutter_riverpod`.

      `ActivitiesRepository` methods:
      - `fetchMyActivities()` — select `id, owner_id, name, description, created_at` from `activities` where `owner_id = _me` and `deleted_at IS NULL`, order `created_at` descending. Return `List<Activity>`.
      - `createActivity({required String name, String? description, String? defaultActivityTypeId})` — insert `{name: name.trim(), description: trimmed-or-null}` into `activities`. Do NOT include defaultActivityTypeId.
      - `updateActivity({required String id, required String name, String? description, String? defaultActivityTypeId})` — update `activities` set `name`, `description` where `id = id`. Do NOT include defaultActivityTypeId.
      - `deleteActivity(String id)` — call `_db.rpc('delete_activity', params: {'p_activity': id})`.
      - `fetchGroupActivities(String groupId)` — select from `group_activities`:
        ```
        group_id, activity_id, type_id, added_by, added_at,
        activities(id, owner_id, name, description, created_at),
        activity_types(name),
        sharer:profiles!group_activities_added_by_fkey(username)
        ```
        filter `group_id = groupId`, order `added_at`. Return `List<GroupActivity>`.
      - `shareActivityToGroup({required String activityId, required String groupId, required String activityTypeId})` — insert `{group_id, activity_id, type_id: activityTypeId}` into `group_activities`.
      - `unshareActivityFromGroup({required String groupId, required String activityId})` — delete from `group_activities` where `group_id = groupId` AND `activity_id = activityId`.

      Providers at bottom of file:
      ```dart
      final activitiesRepositoryProvider = Provider((_) => ActivitiesRepository());
      final myActivitiesProvider = FutureProvider<List<Activity>>(
          (ref) => ref.watch(activitiesRepositoryProvider).fetchMyActivities());
      final groupActivitiesProvider = FutureProvider.family<List<GroupActivity>, String>(
          (ref, groupId) => ref.watch(activitiesRepositoryProvider).fetchGroupActivities(groupId));
      ```

      Note: `friendlyError` is defined in `groups_repository.dart` and imported wherever needed. Do NOT redeclare it here.

      Files: `app/lib/data/activities_repository.dart`
      Verify: `flutter build web --no-version-check` — exits 0.

- [ ] 3. Create `app/lib/features/activities/activities_page.dart`.

      All widgets live in one file (matching `group_page.dart` pattern). Imports needed:
      `groups_repository.dart` (for myGroupsProvider, typesProvider, groupsRepositoryProvider),
      `activities_repository.dart` (for activitiesRepositoryProvider, myActivitiesProvider),
      `models.dart`, `async_body.dart`, `dialogs.dart`, `flutter_riverpod`, `flutter/material.dart`.

      **`ActivitiesPage`** (ConsumerWidget):
      - Scaffold, AppBar title "My Activities".
      - FAB: `FloatingActionButton(onPressed: () => _openCreateSheet(context, ref), child: Icon(Icons.add))`.
      - Body: RefreshIndicator (onRefresh: invalidate + await myActivitiesProvider.future) wrapping `AsyncBody<List<Activity>>(value: ref.watch(myActivitiesProvider), builder: ...)`.
      - Empty state: `EmptyState(icon: Icons.local_activity_outlined, message: 'No activities yet. Tap + to add one.')`.
      - Non-empty: `ListView(padding: EdgeInsets.only(bottom: 96), children: [for (a in list) _ActivityTile(activity: a)])`.

      **`_ActivityTile`** (ConsumerWidget):
      - `ListTile` inside a `Card(margin: EdgeInsets.symmetric(horizontal: 16, vertical: 4))`.
      - Leading: `CircleAvatar(child: Text(a.name.characters.first.toUpperCase()))`.
      - Title: `Text(a.name)`.
      - Subtitle: `a.description?.isNotEmpty == true ? Text(a.description!) : null`.
      - Trailing: `PopupMenuButton<String>` with items: `('edit', 'Edit')`, `('delete', 'Delete')`, `('share', 'Share to group')`.
      - `onSelected`:
        - `edit` → opens `_ActivityFormSheet(activity: a)` in bottom sheet, then `ref.invalidate(myActivitiesProvider)`.
        - `delete` → `confirm(context, title: 'Delete ${a.name}?', message: 'This can't be undone.', action: 'Delete')`, if ok: `await repo.deleteActivity(a.id)`, `ref.invalidate(myActivitiesProvider)`. Wrap in try/catch → `showError`.
        - `share` → opens `_ShareToGroupSheet(activity: a)` in bottom sheet.

      **`_ActivityFormSheet`** (ConsumerStatefulWidget, accepts `Activity? activity`):
      - `showModalBottomSheet(isScrollControlled: true, showDragHandle: true, ...)`.
      - Two `TextEditingController`s: name (init from `activity?.name ?? ''`), description (init from `activity?.description ?? ''`).
      - Dispose controllers in `dispose()`.
      - `Padding(padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom, left: 16, right: 16, top: 8))`.
      - Column: title text (create or edit), name TextField (autofocus, required), description TextField (maxLines: 3, optional), FilledButton("Save" / "Create").
      - On submit: validate name non-empty, call `createActivity` or `updateActivity`, `Navigator.pop(context)`. Wrap in try/catch → `showError`.

      **`_ShareToGroupSheet`** (ConsumerStatefulWidget, accepts `Activity activity`):
      - State: `String? _selectedGroupId`, `String? _selectedTypeId`.
      - Loads `myGroupsProvider` for groups. When `_selectedGroupId` is not null, loads `typesProvider(_selectedGroupId!)` for types.
      - Two DropdownButtonFormField widgets: one for group, one for type (disabled until group selected).
      - On submit: validate both selected, call `repo.shareActivityToGroup(activityId: activity.id, groupId: _selectedGroupId!, activityTypeId: _selectedTypeId!)`, `ref.invalidate(groupActivitiesProvider(_selectedGroupId!))`, `Navigator.pop(context)`, `showMessage(context, 'Shared!')`. Wrap in try/catch → `showError`.

      Files: `app/lib/features/activities/activities_page.dart` (new file; create the `features/activities/` directory)
      Verify: `flutter build web --no-version-check` — exits 0.

- [ ] 4. Update the Activities tab in `app/lib/features/groups/group_page.dart`.

      Add import at the top: `import '../../data/activities_repository.dart';`

      Replace the **first** `EmptyState` placeholder (the Activities tab child in the `TabBarView`) with `_ActivitiesTab(groupId: groupId)`.

      Add these private widgets below the `_TypesTab` class:

      **`_ActivitiesTab`** (ConsumerWidget, `groupId: String`):
      - `AsyncBody<List<GroupActivity>>(value: ref.watch(groupActivitiesProvider(groupId)), builder: (list) => ...)`.
      - Builder returns a ListView with:
        - Padding child containing `FilledButton.icon(icon: Icon(Icons.add), label: Text('Share an activity'), onPressed: () => _openGroupShareSheet(context, ref, groupId))`.
        - If list is empty: `EmptyState(icon: Icons.local_activity_outlined, message: 'No activities shared yet.')`.
        - For each `ga` in list: `_GroupActivityTile(groupActivity: ga, groupId: groupId)`.
      - `_openGroupShareSheet` calls `showModalBottomSheet(isScrollControlled: true, showDragHandle: true, builder: (_) => _GroupShareSheet(groupId: groupId))`.

      **`_GroupActivityTile`** (ConsumerWidget, `groupActivity: GroupActivity`, `groupId: String`):
      - `ListTile`:
        - Leading: `CircleAvatar(child: Text(ga.activity.name.characters.first.toUpperCase()))`.
        - Title: `Text(ga.activity.name)`.
        - Subtitle: `Text('${ga.typeName ?? 'Unknown type'} · @${ga.sharedByUsername ?? '?'}')`.
        - Trailing: `PopupMenuButton<String>` with item `('unshare', 'Unshare')`.
        - On unshare: `confirm(context, title: 'Remove from group?', message: "The activity won't be deleted, only removed from this group.", action: 'Remove')`. If ok: `await repo.unshareActivityFromGroup(groupId: groupId, activityId: ga.activityId)`, `ref.invalidate(groupActivitiesProvider(groupId))`. Wrap in try/catch → `showError`.

      **`_GroupShareSheet`** (ConsumerStatefulWidget, `groupId: String`):
      - State: `String? _selectedActivityId`, `String? _selectedTypeId`.
      - Loads `myActivitiesProvider` and `groupActivitiesProvider(groupId)`.
      - Computes `alreadySharedIds = {ga.activityId for ga in groupActivities}`.
      - Filters: `available = myActivities.where((a) => !alreadySharedIds.contains(a.id)).toList()`.
      - Two DropdownButtonFormField: one for available activities, one for group types (from `typesProvider(groupId)`).
      - On submit: validate both selected, call `shareActivityToGroup(activityId: _selectedActivityId!, groupId: groupId, activityTypeId: _selectedTypeId!)`, `ref.invalidate(groupActivitiesProvider(groupId))`, `Navigator.pop(context)`, `showMessage(context, 'Activity shared!')`. Wrap in try/catch → `showError`.

      Files: `app/lib/features/groups/group_page.dart`
      Verify: `flutter build web --no-version-check` — exits 0.

- [ ] 5. Update `app/lib/router.dart` to wire `/activities` to `ActivitiesPage`.

      Add import: `import 'features/activities/activities_page.dart';`
      Replace the `GoRoute` builder for path `/activities` — change `PlaceholderPage(...)` to `const ActivitiesPage()`.
      Keep the `/schedule` PlaceholderPage unchanged (PlaceholderPage import still needed).

      Files: `app/lib/router.dart`
      Verify: `flutter build web --no-version-check` — exits 0. Navigate to `/activities` in the running app to see `ActivitiesPage`.

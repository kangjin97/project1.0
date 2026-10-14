import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/notifications_repository.dart';
import '../../data/realtime_repository.dart';

const _tabs = [
  (path: '/schedule', label: 'Schedule', icon: Icons.calendar_month_outlined, selected: Icons.calendar_month),
  (path: '/groups', label: 'Groups', icon: Icons.groups_outlined, selected: Icons.groups),
  (path: '/activities', label: 'Activities', icon: Icons.local_activity_outlined, selected: Icons.local_activity),
  // "Notifications" doesn't fit five tabs on a phone; the page itself is titled that.
  (path: '/notifications', label: 'Alerts', icon: Icons.notifications_outlined, selected: Icons.notifications),
  (path: '/profile', label: 'Profile', icon: Icons.account_circle_outlined, selected: Icons.account_circle),
];

/// Bottom navigation on phones, a side rail on wider screens.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  GoRouter? _router;

  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // Realtime keeps the badge live (liveUpdatesProvider); re-count on resume
    // as well, in case the connection was asleep while the app was hidden.
    _lifecycle = AppLifecycleListener(onResume: () => ref.invalidate(unreadCountProvider));
  }

  // Read the location from the router itself so the selected tab is never stale.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final router = GoRouter.of(context);
    if (router != _router) {
      _router?.routerDelegate.removeListener(_onRouteChanged);
      _router = router..routerDelegate.addListener(_onRouteChanged);
    }
  }

  @override
  void dispose() {
    _router?.routerDelegate.removeListener(_onRouteChanged);
    _lifecycle.dispose();
    super.dispose();
  }

  void _onRouteChanged() {
    if (!mounted) return;
    // Also re-count on every navigation: a cheap count, and a safety net if the
    // realtime connection is down.
    ref.invalidate(unreadCountProvider);
    setState(() {});
  }

  Widget _icon(int i, {required bool selected}) {
    final t = _tabs[i];
    final icon = Icon(selected ? t.selected : t.icon);
    if (t.path != '/notifications') return icon;
    final unread = ref.watch(unreadCountProvider).value ?? 0;
    return Badge(isLabelVisible: unread > 0, label: Text(unread > 99 ? '99+' : '$unread'), child: icon);
  }

  int get _index {
    final location = _router?.routerDelegate.currentConfiguration.uri.path ?? '';
    final i = _tabs.indexWhere((t) => location.startsWith(t.path));
    return i < 0 ? 0 : i;
  }

  void _go(BuildContext context, int i) => context.go(_tabs[i].path);

  @override
  Widget build(BuildContext context) {
    // Other people's changes re-fetch open screens while signed in (#7).
    ref.watch(liveUpdatesProvider);
    final child = widget.child;
    final wide = MediaQuery.sizeOf(context).width >= 720;
    if (!wide) {
      return Scaffold(
        body: child,
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) => _go(context, i),
          destinations: [
            for (var i = 0; i < _tabs.length; i++)
              NavigationDestination(
                icon: _icon(i, selected: false),
                selectedIcon: _icon(i, selected: true),
                label: _tabs[i].label,
              ),
          ],
        ),
      );
    }
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _index,
            onDestinationSelected: (i) => _go(context, i),
            labelType: NavigationRailLabelType.all,
            leading: const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Icon(Icons.groups_2_outlined, size: 32),
            ),
            destinations: [
              for (var i = 0; i < _tabs.length; i++)
                NavigationRailDestination(
                  icon: _icon(i, selected: false),
                  selectedIcon: _icon(i, selected: true),
                  label: Text(_tabs[i].label),
                ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: child),
        ],
      ),
    );
  }
}

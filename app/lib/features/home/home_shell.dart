import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

const _tabs = [
  (path: '/schedule', label: 'Schedule', icon: Icons.calendar_month_outlined, selected: Icons.calendar_month),
  (path: '/groups', label: 'Groups', icon: Icons.groups_outlined, selected: Icons.groups),
  (path: '/activities', label: 'Activities', icon: Icons.local_activity_outlined, selected: Icons.local_activity),
  (path: '/profile', label: 'Profile', icon: Icons.account_circle_outlined, selected: Icons.account_circle),
];

/// Bottom navigation on phones, a side rail on wider screens.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.child});

  final Widget child;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  GoRouter? _router;

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
    super.dispose();
  }

  void _onRouteChanged() {
    if (mounted) setState(() {});
  }

  int get _index {
    final location = _router?.routerDelegate.currentConfiguration.uri.path ?? '';
    final i = _tabs.indexWhere((t) => location.startsWith(t.path));
    return i < 0 ? 0 : i;
  }

  void _go(BuildContext context, int i) => context.go(_tabs[i].path);

  @override
  Widget build(BuildContext context) {
    final child = widget.child;
    final wide = MediaQuery.sizeOf(context).width >= 720;
    if (!wide) {
      return Scaffold(
        body: child,
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) => _go(context, i),
          destinations: [
            for (final t in _tabs)
              NavigationDestination(icon: Icon(t.icon), selectedIcon: Icon(t.selected), label: t.label),
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
              for (final t in _tabs)
                NavigationRailDestination(icon: Icon(t.icon), selectedIcon: Icon(t.selected), label: Text(t.label)),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: child),
        ],
      ),
    );
  }
}

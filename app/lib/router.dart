import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'features/activities/activities_page.dart';
import 'features/activities/activity_detail_page.dart';
import 'features/auth/auth_page.dart';
import 'features/groups/group_page.dart';
import 'features/groups/groups_page.dart';
import 'features/groups/join_page.dart';
import 'features/home/home_shell.dart';
import 'features/schedule/my_schedule_page.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final auth = Supabase.instance.client.auth;
  final refresh = _AuthRefresh(auth.onAuthStateChange);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/schedule',
    refreshListenable: refresh,
    redirect: (context, state) {
      final signedIn = auth.currentSession != null;
      final atAuth = state.matchedLocation == '/auth';
      if (!signedIn) {
        // Keep invite links working through sign-in.
        return atAuth ? null : '/auth?next=${Uri.encodeComponent(state.uri.toString())}';
      }
      if (atAuth) return state.uri.queryParameters['next'] ?? '/schedule';
      return null;
    },
    routes: [
      GoRoute(path: '/auth', builder: (_, _) => const AuthPage()),
      GoRoute(
        path: '/join/:token',
        builder: (_, state) => JoinPage(token: state.pathParameters['token']!),
      ),
      ShellRoute(
        builder: (_, _, child) => HomeShell(child: child),
        routes: [
          GoRoute(
            path: '/schedule',
            builder: (_, _) => const MySchedulePage(),
          ),
          GoRoute(
            path: '/groups',
            builder: (_, _) => const GroupsPage(),
            routes: [
              GoRoute(
                path: ':id',
                builder: (_, state) => GroupPage(groupId: state.pathParameters['id']!),
              ),
            ],
          ),
          GoRoute(
            path: '/activities',
            builder: (_, _) => const ActivitiesPage(),
            routes: [
              GoRoute(
                path: ':id',
                builder: (_, state) => ActivityDetailPage(activityId: state.pathParameters['id']!),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});

class _AuthRefresh extends ChangeNotifier {
  _AuthRefresh(Stream<AuthState> stream) {
    _sub = stream.listen((_) => notifyListeners());
  }

  late final StreamSubscription<AuthState> _sub;

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

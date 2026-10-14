import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'features/activities/activities_page.dart';
import 'features/activities/activity_detail_page.dart';
import 'features/auth/auth_page.dart';
import 'features/auth/reset_password_page.dart';
import 'features/groups/group_page.dart';
import 'features/groups/groups_page.dart';
import 'features/groups/join_page.dart';
import 'features/home/home_shell.dart';
import 'features/profile/profile_page.dart';
import 'features/schedule/my_schedule_page.dart';

/// Shows snackbars from outside any page, e.g. a note carried by an auth link.
final rootMessengerKey = GlobalKey<ScaffoldMessengerState>();

/// Supabase sends auth links back to the site root, sometimes with a note for
/// the user: `message` (an email change waiting for the other address's link)
/// or `error_description` (an expired or already-used link).
String? authLinkNotice(Uri uri) => uri.queryParameters['message'] ?? uri.queryParameters['error_description'];

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
      final atReset = state.matchedLocation == '/reset-password';
      // A password-reset link signs the user in temporarily; send them to set a new password.
      if (refresh.recovering && !atReset) return '/reset-password';
      // The root has no page. A bare "/" becomes initialLocation, but auth links
      // arrive as "/?..." and would otherwise hit "no routes for location".
      if (state.uri.path == '/' || state.uri.path.isEmpty) {
        final notice = authLinkNotice(state.uri);
        if (notice != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) => rootMessengerKey.currentState
              ?.showSnackBar(SnackBar(content: Text(notice), duration: const Duration(seconds: 10))));
        }
        return '/schedule';
      }
      // The reset page handles its own "link expired" state.
      if (atReset) return null;
      if (!signedIn) {
        // Keep invite links working through sign-in.
        return atAuth ? null : '/auth?next=${Uri.encodeComponent(state.uri.toString())}';
      }
      if (atAuth) return state.uri.queryParameters['next'] ?? '/schedule';
      return null;
    },
    routes: [
      GoRoute(path: '/auth', builder: (_, _) => const AuthPage()),
      GoRoute(path: '/reset-password', builder: (_, _) => ResetPasswordPage(onDone: refresh.endRecovery)),
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
          GoRoute(path: '/profile', builder: (_, _) => const ProfilePage()),
          GoRoute(
            path: '/people/:id',
            builder: (_, state) => PersonPage(userId: state.pathParameters['id']!),
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
    _sub = stream.listen((s) {
      if (s.event == AuthChangeEvent.passwordRecovery) recovering = true;
      if (s.event == AuthChangeEvent.signedOut) recovering = false;
      notifyListeners();
    });
  }

  late final StreamSubscription<AuthState> _sub;

  /// True between opening a password-reset link and setting the new password.
  bool recovering = false;

  void endRecovery() {
    recovering = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

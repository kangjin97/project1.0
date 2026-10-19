import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'features/activities/activities_page.dart';
import 'features/activities/activity_detail_page.dart';
import 'features/auth/auth_page.dart';
import 'features/auth/reset_password_page.dart';
import 'features/auth/welcome_page.dart';
import 'features/groups/group_history_page.dart';
import 'features/groups/group_page.dart';
import 'features/groups/groups_page.dart';
import 'features/groups/join_page.dart';
import 'features/home/home_shell.dart';
import 'features/notifications/notifications_page.dart';
import 'features/profile/profile_page.dart';
import 'features/schedule/my_schedule_page.dart';
import 'data/profile_repository.dart';

/// Shows snackbars from outside any page, e.g. a note carried by an auth link.
final rootMessengerKey = GlobalKey<ScaffoldMessengerState>();

/// Supabase sends auth links back to the site root, sometimes with a note for
/// the user: `message` (an email change waiting for the other address's link)
/// or `error_description` (an expired or already-used link).
String? authLinkNotice(Uri uri) => uri.queryParameters['message'] ?? uri.queryParameters['error_description'];

/// Where to go after signing in: a path inside this app, never another site.
String safeNext(String? next) =>
    (next != null && next.startsWith('/') && !next.startsWith('//')) ? next : '/schedule';

final routerProvider = Provider<GoRouter>((ref) {
  final auth = Supabase.instance.client.auth;
  final refresh = _AuthRefresh(auth.onAuthStateChange, ref.read(profileRepositoryProvider));
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/schedule',
    refreshListenable: refresh,
    redirect: (context, state) async {
      final signedIn = auth.currentSession != null;
      final atAuth = state.matchedLocation == '/auth';
      final atWelcome = state.matchedLocation == '/welcome';
      final atReset = state.matchedLocation == '/reset-password';
      // A password-reset link signs the user in temporarily; send them to set a new password.
      if (refresh.recovering && !atReset) return '/reset-password';
      // The root has no page. A bare "/" becomes initialLocation, but auth links
      // arrive as "/?..." and would otherwise hit "no routes for location".
      // Google sign-in comes back as "/?next=<path>&code=...".
      if (state.uri.path == '/' || state.uri.path.isEmpty) {
        final notice = authLinkNotice(state.uri);
        if (notice != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) => rootMessengerKey.currentState
              ?.showSnackBar(SnackBar(content: Text(notice), duration: const Duration(seconds: 10))));
        }
        return safeNext(state.uri.queryParameters['next']);
      }
      // The reset page handles its own "link expired" state.
      if (atReset) return null;
      if (!signedIn) {
        // Keep invite links working through sign-in.
        return atAuth ? null : '/auth?next=${Uri.encodeComponent(state.uri.toString())}';
      }
      // Signed up with Google and no username yet: pick one first (#87).
      if (await refresh.needsUsername() == true) {
        return atWelcome ? null : '/welcome?next=${Uri.encodeComponent(atAuth ? safeNext(state.uri.queryParameters['next']) : state.uri.toString())}';
      }
      if (atAuth || atWelcome) return safeNext(state.uri.queryParameters['next']);
      return null;
    },
    routes: [
      GoRoute(path: '/auth', builder: (_, _) => const AuthPage()),
      GoRoute(path: '/reset-password', builder: (_, _) => ResetPasswordPage(onDone: refresh.endRecovery)),
      GoRoute(path: '/welcome', builder: (_, _) => WelcomePage(onDone: refresh.usernameChosen)),
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
                routes: [
                  GoRoute(
                    path: 'history',
                    builder: (_, state) => GroupHistoryPage(groupId: state.pathParameters['id']!),
                  ),
                ],
              ),
            ],
          ),
          GoRoute(path: '/notifications', builder: (_, _) => const NotificationsPage()),
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
  _AuthRefresh(Stream<AuthState> stream, this._profiles) {
    _sub = stream.listen((s) {
      if (s.event == AuthChangeEvent.passwordRecovery) recovering = true;
      if (s.event == AuthChangeEvent.signedOut) recovering = false;
      // Another person may be signing in: read their flag again.
      if (s.session?.user.id != _flagFor) _needsUsername = null;
      notifyListeners();
    });
  }

  late final StreamSubscription<AuthState> _sub;
  final ProfileRepository _profiles;

  // Whether the signed-in user still has to pick a username, read once per user.
  bool? _needsUsername;
  String? _flagFor;

  Future<bool?> needsUsername() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return null;
    if (_flagFor != user.id || _needsUsername == null) {
      try {
        _needsUsername = await _profiles.needsUsername();
        _flagFor = user.id;
      } catch (_) {
        return null; // Can't tell right now; don't block the app.
      }
    }
    return _needsUsername;
  }

  /// Called by the username step once it's saved.
  void usernameChosen() {
    _needsUsername = false;
    notifyListeners();
  }

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

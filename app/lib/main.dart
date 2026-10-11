import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'data/app_clock.dart';
import 'router.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Clean web URLs (/join/abc instead of /#/join/abc), so links can also open
  // the phone apps. The host must serve index.html for every path (web/_redirects).
  usePathUrlStrategy();

  // A release build must be pointed at the hosted backend; refuse to run otherwise.
  if (kReleaseMode && AppConfig.isLocalBackend) {
    runApp(const _MisconfiguredApp());
    return;
  }

  await Supabase.initialize(url: AppConfig.supabaseUrl, publishableKey: AppConfig.publishableKey);
  await AppClock.init();
  runApp(const ProviderScope(child: GroupPlannerApp()));
}

class GroupPlannerApp extends ConsumerWidget {
  const GroupPlannerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    // Starts loading the profile's time zone and rebuilds dates when it changes.
    ref.watch(timezoneProvider);
    const seed = Color(0xFF3B6FE0);
    return MaterialApp.router(
      title: 'EasyPlan',
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      theme: ThemeData(colorSchemeSeed: seed, useMaterial3: true),
      darkTheme: ThemeData(colorSchemeSeed: seed, brightness: Brightness.dark, useMaterial3: true),
    );
  }
}

class _MisconfiguredApp extends StatelessWidget {
  const _MisconfiguredApp();

  @override
  Widget build(BuildContext context) => const MaterialApp(
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'This build has no server configured.\n'
                'Build with SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY (see scripts/).',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      );
}

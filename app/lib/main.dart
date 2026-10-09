import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'data/schedule_repository.dart';
import 'router.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: AppConfig.supabaseUrl, publishableKey: AppConfig.publishableKey);
  // Keep the profile's time zone current; all-day clash checks depend on it.
  Supabase.instance.client.auth.onAuthStateChange.listen((s) {
    if (s.session != null && (s.event == AuthChangeEvent.signedIn || s.event == AuthChangeEvent.initialSession)) {
      syncProfileTimezone().ignore();
    }
  });
  runApp(const ProviderScope(child: GroupPlannerApp()));
}

class GroupPlannerApp extends ConsumerWidget {
  const GroupPlannerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    const seed = Color(0xFF3B6FE0);
    return MaterialApp.router(
      title: 'Group Planner',
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      theme: ThemeData(colorSchemeSeed: seed, useMaterial3: true),
      darkTheme: ThemeData(colorSchemeSeed: seed, brightness: Brightness.dark, useMaterial3: true),
    );
  }
}

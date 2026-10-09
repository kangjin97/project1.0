import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'router.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: AppConfig.supabaseUrl, publishableKey: AppConfig.publishableKey);
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

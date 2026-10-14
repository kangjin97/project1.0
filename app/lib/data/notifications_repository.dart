import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'models.dart';

SupabaseClient get _db => Supabase.instance.client;
String get _me => _db.auth.currentUser!.id;

class NotificationsRepository {
  /// Newest first, with names and plan details resolved by the database.
  Future<List<AppNotification>> list({int limit = 50}) async {
    final rows = await _db.rpc('list_notifications', params: {'p_limit': limit}) as List;
    return [for (final r in rows.cast<Map<String, dynamic>>()) AppNotification.fromJson(r)];
  }

  Future<int> unreadCount() async {
    final res = await _db.from('notifications').select('id').eq('user_id', _me).isFilter('read_at', null).count(CountOption.exact);
    return res.count;
  }

  /// Only `read_at` is writable, and only on your own rows (RLS).
  Future<void> markAllRead() => _db
      .from('notifications')
      .update({'read_at': DateTime.now().toUtc().toIso8601String()})
      .eq('user_id', _me)
      .isFilter('read_at', null);
}

final notificationsRepositoryProvider = Provider((_) => NotificationsRepository());

final notificationsProvider =
    FutureProvider.autoDispose<List<AppNotification>>((ref) => ref.watch(notificationsRepositoryProvider).list());

/// Shown as a badge on the navigation. Refreshed when the route changes, when
/// the app returns to the foreground and after marking read (no realtime yet, #7).
final unreadCountProvider = FutureProvider<int>((ref) => ref.watch(notificationsRepositoryProvider).unreadCount());

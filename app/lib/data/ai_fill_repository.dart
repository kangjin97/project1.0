import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

SupabaseClient get _db => Supabase.instance.client;

/// What "Fill from link" suggests for the New activity form (#74). Nothing is
/// saved until the user saves the form.
class AiFill {
  AiFill({
    required this.name,
    this.description,
    this.location,
    this.placeId,
    this.priceMin,
    this.priceMax,
    this.currency,
    this.url,
    this.labelName,
    this.labelIsNew = false,
    this.photo,
    this.photoMediaType,
  });

  factory AiFill.fromJson(Map<String, dynamic> j) {
    final f = Map<String, dynamic>.from(j['fields'] as Map);
    final label = f['label'] as Map?;
    final photo = j['photo'] as Map?;
    return AiFill(
      name: (f['name'] as String?) ?? '',
      description: f['description'] as String?,
      location: f['location'] as String?,
      placeId: f['placeId'] as String?,
      priceMin: (f['priceMin'] as num?)?.toDouble(),
      priceMax: (f['priceMax'] as num?)?.toDouble(),
      currency: f['currency'] as String?,
      url: f['url'] as String?,
      labelName: label?['name'] as String?,
      labelIsNew: label?['isNew'] == true,
      photo: photo?['data'] is String ? base64Decode(photo!['data'] as String) : null,
      photoMediaType: photo?['mediaType'] as String?,
    );
  }

  final String name;
  final String? description;
  final String? location;

  /// The Google place matched for [location], if any (#73).
  final String? placeId;
  final double? priceMin;
  final double? priceMax;
  final String? currency;
  final String? url;

  /// One of the user's labels, or a new one Claude suggests ([labelIsNew]).
  final String? labelName;
  final bool labelIsNew;

  /// The link's preview image, offered as the first photo.
  final Uint8List? photo;
  final String? photoMediaType;

  /// File extension for [photo], for storage.
  String get photoExtension => switch (photoMediaType) {
        'image/png' => 'png',
        'image/webp' => 'webp',
        'image/gif' => 'gif',
        _ => 'jpg',
      };
}

/// Why a fill didn't work, in words for the user.
class AiFillException implements Exception {
  AiFillException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AiFillRepository {
  /// Asks the `fill-activity` Edge Function to read [url] (and/or a
  /// [screenshot] or [caption]) and suggest the activity's fields. Counted
  /// against the caller's 30 fills a day.
  Future<AiFill> fill({String? url, String? caption, Uint8List? screenshot, String? screenshotType}) async {
    try {
      final res = await _db.functions.invoke('fill-activity', body: {
        if (url != null && url.trim().isNotEmpty) 'url': url.trim(),
        if (caption != null && caption.trim().isNotEmpty) 'caption': caption.trim(),
        if (screenshot != null) 'image': {'data': base64Encode(screenshot), 'mediaType': screenshotType ?? 'image/jpeg'},
      });
      return AiFill.fromJson(Map<String, dynamic>.from(res.data as Map));
    } on FunctionException catch (e) {
      final details = e.details;
      final message = details is Map ? details['error'] as String? : null;
      throw AiFillException(message ?? 'Fill from link is unavailable right now.');
    }
  }
}

final aiFillRepositoryProvider = Provider((_) => AiFillRepository());

import 'dart:typed_data';

import 'save_file_io.dart' if (dart.library.js_interop) 'save_file_web.dart' as platform;

/// Hands an exported file to the person: a download in the browser, the share
/// sheet on phones (save to Files, send in a chat, open in another app).
Future<void> saveFile(Uint8List bytes, {required String name, required String mimeType}) =>
    platform.saveFile(bytes, name: name, mimeType: mimeType);

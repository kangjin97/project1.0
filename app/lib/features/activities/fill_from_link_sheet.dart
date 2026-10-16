import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../data/ai_fill_repository.dart';

/// "Fill from link" (#74): paste a link, optionally add a screenshot or the
/// caption, and get suggested fields for the New activity form. Returns null
/// when closed without filling.
Future<AiFill?> showFillFromLinkSheet(BuildContext context, {String? initialUrl}) {
  return showModalBottomSheet<AiFill>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _FillSheet(initialUrl: initialUrl),
  );
}

class _FillSheet extends ConsumerStatefulWidget {
  const _FillSheet({this.initialUrl});

  final String? initialUrl;

  @override
  ConsumerState<_FillSheet> createState() => _FillSheetState();
}

class _FillSheetState extends ConsumerState<_FillSheet> {
  // Owned here, not disposed in whenComplete (see CLAUDE.md gotchas).
  late final _url = TextEditingController(text: widget.initialUrl);
  final _caption = TextEditingController();
  Uint8List? _screenshot;
  String? _screenshotType;
  bool _filling = false;
  String? _error;

  @override
  void dispose() {
    _url.dispose();
    _caption.dispose();
    super.dispose();
  }

  bool get _isInstagram => RegExp(r'(instagram\.com|facebook\.com|fb\.watch|threads\.net)', caseSensitive: false)
      .hasMatch(_url.text);

  Future<void> _pickScreenshot() async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1600, imageQuality: 85);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    setState(() {
      _screenshot = bytes;
      _screenshotType = file.mimeType ?? (file.name.toLowerCase().endsWith('.png') ? 'image/png' : 'image/jpeg');
    });
  }

  Future<void> _fill() async {
    if (_url.text.trim().isEmpty && _caption.text.trim().isEmpty && _screenshot == null) {
      setState(() => _error = 'Paste a link, a caption or a screenshot.');
      return;
    }
    setState(() {
      _filling = true;
      _error = null;
    });
    try {
      final fill = await ref.read(aiFillRepositoryProvider).fill(
            url: _url.text,
            caption: _caption.text,
            screenshot: _screenshot,
            screenshotType: _screenshotType,
          );
      if (mounted) Navigator.pop(context, fill);
    } on AiFillException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Fill from link is unavailable right now.');
    } finally {
      if (mounted) setState(() => _filling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Fill from link', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text('Paste a TikTok, YouTube or web link. You check everything before saving.', style: muted),
            const SizedBox(height: 16),
            TextField(
              controller: _url,
              enabled: !_filling,
              keyboardType: TextInputType.url,
              autocorrect: false,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Link',
                prefixIcon: Icon(Icons.link),
                border: OutlineInputBorder(),
              ),
            ),
            if (_isInstagram)
              Padding(
                padding: const EdgeInsets.only(top: 6, left: 4),
                child: Text('Instagram and Facebook don’t share previews: add a screenshot or paste the caption too.',
                    style: muted),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _filling ? null : _pickScreenshot,
                  icon: const Icon(Icons.screenshot_outlined),
                  label: Text(_screenshot == null ? 'Add screenshot' : 'Change screenshot'),
                ),
                if (_screenshot != null) ...[
                  const SizedBox(width: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.memory(_screenshot!, width: 40, height: 40, fit: BoxFit.cover),
                  ),
                  IconButton(
                    tooltip: 'Remove screenshot',
                    onPressed: _filling ? null : () => setState(() => _screenshot = null),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _caption,
              enabled: !_filling,
              minLines: 2,
              maxLines: 5,
              decoration: const InputDecoration(
                labelText: 'Caption (optional)',
                hintText: 'Paste the post’s text',
                border: OutlineInputBorder(),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_error!, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error)),
              ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _filling ? null : _fill,
              icon: _filling
                  ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.auto_awesome),
              label: Text(_filling ? 'Reading…' : 'Fill in'),
            ),
            const SizedBox(height: 8),
            Text('Uses AI (Claude) to read the link. 30 fills a day.', style: muted, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/places_repository.dart';

/// The activity Location field (#73): suggests Google Maps places while you
/// type and keeps the picked place's ID. Free text still works; editing the
/// text after a pick drops the place (the database does the same).
class PlaceField extends ConsumerStatefulWidget {
  const PlaceField({
    super.key,
    required this.controller,
    required this.placeId,
    required this.onPlaceChanged,
    this.label = 'Location',
    this.hint,
  });

  final TextEditingController controller;

  /// The place picked for the current text, or null for free text.
  final String? placeId;
  final ValueChanged<String?> onPlaceChanged;

  /// The field's label and, when given, its helper text (the "Near…" filter
  /// reuses the field to pick a starting point).
  final String label;
  final String? hint;

  @override
  ConsumerState<PlaceField> createState() => _PlaceFieldState();
}

class _PlaceFieldState extends ConsumerState<PlaceField> {
  /// Wait for a pause in typing: each search is counted and billed.
  static const _pause = Duration(milliseconds: 400);

  final _focus = FocusNode();
  Timer? _debounce;
  int _latest = 0;
  bool _searching = false;
  String? _error;
  List<PlaceSuggestion> _suggestions = const [];

  /// The text a place was picked for; typing anything else drops the place.
  String? _pickedText;

  @override
  void initState() {
    super.initState();
    // Read now, before any typing: a lazy field would capture the edited text.
    _pickedText = widget.placeId == null ? null : widget.controller.text;
    _focus.addListener(() {
      // Leaving the field closes the list (taps on it count as inside the
      // field, see TextFieldTapRegion below).
      if (!_focus.hasFocus) _close();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _focus.dispose();
    super.dispose();
  }

  void _close() {
    _debounce?.cancel();
    _latest++;
    if (mounted) setState(() => _suggestions = const []);
  }

  void _onChanged(String text) {
    if (widget.placeId != null && text != _pickedText) {
      _pickedText = null;
      widget.onPlaceChanged(null);
    }
    _debounce?.cancel();
    if (text.trim().length < 3) {
      _latest++;
      setState(() {
        _suggestions = const [];
        _error = null;
        _searching = false;
      });
      return;
    }
    _debounce = Timer(_pause, () => _search(text));
  }

  Future<void> _search(String text) async {
    final mine = ++_latest;
    setState(() => _searching = true);
    try {
      final found = await ref.read(placesRepositoryProvider).suggest(text);
      if (!mounted || mine != _latest) return;
      setState(() {
        _suggestions = found;
        _error = null;
      });
    } on PlaceSearchException catch (e) {
      if (!mounted || mine != _latest) return;
      setState(() {
        _suggestions = const [];
        _error = e.message;
      });
    } catch (_) {
      if (!mounted || mine != _latest) return;
      setState(() {
        _suggestions = const [];
        _error = 'Place search is unavailable right now.';
      });
    } finally {
      if (mounted && mine == _latest) setState(() => _searching = false);
    }
  }

  void _pick(PlaceSuggestion s) {
    widget.controller.value = TextEditingValue(
      text: s.label,
      selection: TextSelection.collapsed(offset: s.label.length),
    );
    _pickedText = s.label;
    widget.onPlaceChanged(s.placeId);
    _close();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final picked = widget.placeId != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          controller: widget.controller,
          focusNode: _focus,
          onChanged: _onChanged,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            labelText: widget.label,
            prefixIcon: const Icon(Icons.place_outlined),
            suffixIcon: _searching
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                : picked
                    ? Tooltip(
                        message: 'Exact place from Google Maps',
                        child: Icon(Icons.check_circle, color: theme.colorScheme.primary),
                      )
                    : null,
            helperText: widget.hint ?? (picked ? 'Exact place from Google Maps' : 'Type to search Google Maps, or write any place'),
            border: const OutlineInputBorder(),
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
            child: Text(_error!, style: muted),
          ),
        if (_suggestions.isNotEmpty)
          TextFieldTapRegion(
            child: Card(
              margin: const EdgeInsets.only(top: 4),
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final s in _suggestions)
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.place_outlined),
                      title: Text(s.mainText),
                      subtitle: s.secondaryText.isEmpty ? null : Text(s.secondaryText),
                      onTap: () => _pick(s),
                    ),
                  const _GoogleMapsAttribution(),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Required with Google suggestions shown outside a Google map: the text
/// "Google Maps" (allowed instead of the logo where space is tight), Roboto
/// 400 at 12, #5E5E5E (white on dark), never translated or wrapped, inside
/// the same container as the suggestions.
class _GoogleMapsAttribution extends StatelessWidget {
  const _GoogleMapsAttribution();

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Align(
        alignment: Alignment.centerRight,
        child: Semantics(
          label: 'Google Maps',
          excludeSemantics: true,
          child: Text(
            'Google Maps',
            maxLines: 1,
            softWrap: false,
            style: TextStyle(
              fontFamily: 'Roboto',
              fontSize: 12,
              fontWeight: FontWeight.w400,
              letterSpacing: 0,
              color: dark ? Colors.white : const Color(0xFF5E5E5E),
            ),
          ),
        ),
      ),
    );
  }
}

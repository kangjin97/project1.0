import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/activities_repository.dart';
import '../../data/ai_fill_repository.dart';
import '../../data/models.dart';
import '../../widgets/dialogs.dart';
import 'activity_widgets.dart';
import 'fill_from_link_sheet.dart';
import 'place_field.dart';

const _currencies = ['SGD', 'MYR', 'USD', 'EUR', 'GBP', 'AUD', 'JPY', 'KRW', 'THB', 'IDR'];

/// Opens the create/edit form. Returns the activity id when saved.
Future<String?> showActivityForm(BuildContext context, {Activity? activity}) {
  return Navigator.of(context, rootNavigator: true).push<String>(
    MaterialPageRoute(fullscreenDialog: true, builder: (_) => ActivityFormPage(activity: activity)),
  );
}

class ActivityFormPage extends ConsumerStatefulWidget {
  const ActivityFormPage({super.key, this.activity});

  final Activity? activity;

  @override
  ConsumerState<ActivityFormPage> createState() => _ActivityFormPageState();
}

class _ActivityFormPageState extends ConsumerState<ActivityFormPage> {
  final _form = GlobalKey<FormState>();
  late final Activity? _a = widget.activity;
  late final _name = TextEditingController(text: _a?.name);
  late final _description = TextEditingController(text: _a?.description);
  late final _location = TextEditingController(text: _a?.location);
  late String? _placeId = _a?.placeId;
  late final _priceMin = TextEditingController(text: _num(_a?.priceMin));
  late final _priceMax = TextEditingController(text: _num(_a?.priceMax));
  late final _url = TextEditingController(text: _a?.url);
  late String _currency = _a?.currency ?? 'SGD';
  late String? _labelId = _a?.personalTypeId;

  late final List<ActivityPhoto> _keptPhotos = [...?_a?.photos];
  final List<ActivityPhoto> _removedPhotos = [];
  final List<XFile> _newPhotos = [];
  bool _saving = false;

  // From "Fill from link" (#74): a new label Claude suggested (created only if
  // tapped), and the link's preview image, used as the first photo unless
  // unticked.
  String? _suggestedLabel;
  AiFill? _filled;
  bool _useFilledPhoto = true;

  bool get _editing => _a != null;

  /// Labels are personal: only the owner sees and sets them.
  bool get _isOwner => _a == null || _a.ownerId == Supabase.instance.client.auth.currentUser?.id;

  static String _num(double? v) =>
      v == null ? '' : (v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2));

  @override
  void dispose() {
    for (final c in [_name, _description, _location, _priceMin, _priceMax, _url]) {
      c.dispose();
    }
    super.dispose();
  }

  double? _parse(String s) => s.trim().isEmpty ? null : double.tryParse(s.trim());

  String? _validatePrice(String? v) {
    if (v == null || v.trim().isEmpty) return null;
    final n = double.tryParse(v.trim());
    if (n == null || n < 0) return 'Enter an amount';
    return null;
  }

  Future<void> _pickPhotos() async {
    final picked = await ImagePicker().pickMultiImage(maxWidth: 1600, imageQuality: 85);
    if (picked.isNotEmpty) setState(() => _newPhotos.addAll(picked));
  }

  /// Opens "Fill from link" and puts what comes back into the form. The user
  /// still reviews and saves; nothing is stored here.
  Future<void> _fillFromLink() async {
    final fill = await showFillFromLinkSheet(context, initialUrl: _url.text);
    if (fill == null || !mounted) return;
    String num(double? v) => _num(v);
    final labels = ref.read(labelsProvider).value ?? const <PersonalType>[];
    final existing = fill.labelIsNew
        ? null
        : labels.where((l) => l.name.toLowerCase() == fill.labelName?.toLowerCase()).firstOrNull;
    setState(() {
      if (fill.name.isNotEmpty) _name.text = fill.name;
      if (fill.description != null) _description.text = fill.description!;
      if (fill.location != null) {
        _location.text = fill.location!;
        _placeId = fill.placeId;
      }
      _priceMin.text = num(fill.priceMin);
      _priceMax.text = num(fill.priceMax);
      if (fill.currency != null && _currencies.contains(fill.currency)) _currency = fill.currency!;
      if (fill.url != null) _url.text = fill.url!;
      if (existing != null) _labelId = existing.id;
      _suggestedLabel = existing == null ? fill.labelName : null;
      _filled = fill;
      _useFilledPhoto = fill.photo != null;
    });
    showMessage(context, 'Filled in from the link. Check it before saving.');
  }

  Future<void> _addSuggestedLabel() async {
    final name = _suggestedLabel;
    if (name == null) return;
    try {
      final id = await ref.read(activitiesRepositoryProvider).addLabel(name);
      ref.invalidate(labelsProvider);
      if (mounted) {
        setState(() {
          _labelId = id;
          _suggestedLabel = null;
        });
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    var url = _url.text.trim();
    if (url.isNotEmpty && !url.contains('://')) url = 'https://$url';

    final input = ActivityInput(
      name: _name.text,
      description: _description.text,
      location: _location.text,
      placeId: _placeId,
      priceMin: _parse(_priceMin.text),
      priceMax: _parse(_priceMax.text),
      currency: _currency,
      url: url,
      personalTypeId: _labelId,
      setLabel: _isOwner,
    );

    setState(() => _saving = true);
    final repo = ref.read(activitiesRepositoryProvider);
    try {
      final id = _editing ? _a!.id : await repo.create(input);
      if (_editing) await repo.update(id, input);
      for (final p in _removedPhotos) {
        await repo.removePhoto(p);
      }
      var position = _keptPhotos.length;
      final filled = _filled;
      if (filled?.photo != null && _useFilledPhoto) {
        await repo.addPhoto(id, filled!.photo!, extension: filled.photoExtension, position: position++);
      }
      for (final file in _newPhotos) {
        final ext = file.name.contains('.') ? file.name.split('.').last : 'jpg';
        await repo.addPhoto(id, await file.readAsBytes(), extension: ext, position: position++);
      }
      invalidateActivity(ref, id);
      if (_isOwner && _labelId != _a?.personalTypeId) invalidateLabels(ref);
      if (mounted) Navigator.pop(context, id);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showError(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final gap = const SizedBox(height: 16);
    return Scaffold(
      appBar: AppBar(
        title: Text(_editing ? 'Edit activity' : 'New activity'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Save'),
            ),
          ),
        ],
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!_editing) ...[
                      FilledButton.tonalIcon(
                        onPressed: _saving ? null : _fillFromLink,
                        icon: const Icon(Icons.auto_awesome),
                        label: const Text('Fill from link'),
                      ),
                      const SizedBox(height: 4),
                      Text('Paste a TikTok, YouTube or web link and the form fills itself in.',
                          textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
                      gap,
                    ],
                    TextFormField(
                      controller: _name,
                      autofocus: !_editing,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(labelText: 'Name *', border: OutlineInputBorder()),
                      validator: (v) => (v ?? '').trim().isEmpty ? 'Give it a name' : null,
                    ),
                    if (_isOwner) ...[gap, _labelPicker()],
                    gap,
                    TextFormField(
                      controller: _description,
                      minLines: 2,
                      maxLines: 5,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(labelText: 'Description', border: OutlineInputBorder()),
                    ),
                    gap,
                    PlaceField(
                      controller: _location,
                      placeId: _placeId,
                      onPlaceChanged: (id) => setState(() => _placeId = id),
                    ),
                    gap,
                    Text('Price range', style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 110,
                          child: DropdownButtonFormField<String>(
                            // initialValue is read once; a fill can change it.
                            key: ValueKey(_currency),
                            initialValue: _currencies.contains(_currency) ? _currency : null,
                            decoration: const InputDecoration(border: OutlineInputBorder()),
                            items: [for (final c in _currencies) DropdownMenuItem(value: c, child: Text(c))],
                            onChanged: (v) => setState(() => _currency = v ?? 'SGD'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: _priceField(_priceMin, 'Min')),
                        const Padding(padding: EdgeInsets.fromLTRB(8, 16, 8, 0), child: Text('–')),
                        Expanded(
                          child: _priceField(_priceMax, 'Max', extra: (v) {
                            final lo = _parse(_priceMin.text), hi = _parse(v ?? '');
                            return lo != null && hi != null && hi < lo ? 'Below min' : null;
                          }),
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 4, left: 4),
                      child: Text('Leave both empty if you don’t know. Use 0 for free.',
                          style: Theme.of(context).textTheme.bodySmall),
                    ),
                    gap,
                    TextFormField(
                      controller: _url,
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: 'Link',
                        hintText: 'Website, menu, booking page…',
                        prefixIcon: Icon(Icons.link),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    gap,
                    Row(
                      children: [
                        Expanded(child: Text('Photos', style: Theme.of(context).textTheme.titleSmall)),
                        TextButton.icon(
                          onPressed: _saving ? null : _pickPhotos,
                          icon: const Icon(Icons.add_photo_alternate_outlined),
                          label: const Text('Add photos'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (_filled?.photo case final photo?)
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _useFilledPhoto,
                        onChanged: _saving ? null : (v) => setState(() => _useFilledPhoto = v ?? false),
                        secondary: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Image.memory(photo, width: 56, height: 56, fit: BoxFit.cover),
                        ),
                        title: const Text('Use the link’s preview image'),
                        subtitle: const Text('Saved as the first photo'),
                      ),
                    _photoGrid(),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _newLabel() async {
    final name = await promptText(context, title: 'New label', label: 'Label', action: 'Add');
    if (name == null || name.trim().isEmpty || !mounted) return;
    try {
      final id = await ref.read(activitiesRepositoryProvider).addLabel(name);
      ref.invalidate(labelsProvider);
      setState(() => _labelId = id);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Widget _labelPicker() {
    final labels = ref.watch(labelsProvider).value ?? const <PersonalType>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Label', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        Text('Your own label. Groups file the activity under the same type, or a type they merged it into.',
            style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final l in labels)
              ChoiceChip(
                label: Text(l.name),
                selected: _labelId == l.id,
                onSelected: (on) => setState(() => _labelId = on ? l.id : null),
              ),
            if (_suggestedLabel != null)
              ActionChip(
                avatar: const Icon(Icons.auto_awesome, size: 18),
                label: Text('Add “$_suggestedLabel”'),
                tooltip: 'Suggested from the link: creates this label and picks it',
                onPressed: _addSuggestedLabel,
              ),
            ActionChip(avatar: const Icon(Icons.add, size: 18), label: const Text('New label'), onPressed: _newLabel),
          ],
        ),
      ],
    );
  }

  Widget _priceField(TextEditingController c, String label, {String? Function(String?)? extra}) => TextFormField(
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
        validator: (v) => _validatePrice(v) ?? extra?.call(v),
      );

  Widget _photoGrid() {
    final tiles = <Widget>[
      for (final p in _keptPhotos)
        _PhotoTile(
          image: ActivityPhotoImage(storagePath: p.storagePath),
          onRemove: () => setState(() {
            _keptPhotos.remove(p);
            _removedPhotos.add(p);
          }),
        ),
      for (final f in _newPhotos)
        _PhotoTile(
          image: FutureBuilder(
            future: f.readAsBytes(),
            builder: (_, snap) => snap.hasData ? Image.memory(snap.data!, fit: BoxFit.cover) : const SizedBox(),
          ),
          onRemove: () => setState(() => _newPhotos.remove(f)),
        ),
    ];
    if (tiles.isEmpty) {
      // The link's preview image is listed just above; don't contradict it.
      if (_filled?.photo != null) return const SizedBox.shrink();
      return Text('No photos yet.', style: Theme.of(context).textTheme.bodySmall);
    }
    return Wrap(spacing: 8, runSpacing: 8, children: tiles);
  }
}

class _PhotoTile extends StatelessWidget {
  const _PhotoTile({required this.image, required this.onRemove});

  final Widget image;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: 96,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ClipRRect(borderRadius: BorderRadius.circular(8), child: image),
            Positioned(
              top: 2,
              right: 2,
              child: IconButton.filledTonal(
                visualDensity: VisualDensity.compact,
                iconSize: 16,
                tooltip: 'Remove photo',
                onPressed: onRemove,
                icon: const Icon(Icons.close),
              ),
            ),
          ],
        ),
      );
}

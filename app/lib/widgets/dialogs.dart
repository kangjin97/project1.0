import 'package:flutter/material.dart';

import '../data/groups_repository.dart';

Future<String?> promptText(
  BuildContext context, {
  required String title,
  required String label,
  required String action,
  String initial = '',
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _PromptDialog(title: title, label: label, action: action, initial: initial),
  );
}

// Owns its controller so it's disposed only after the closing animation ends.
class _PromptDialog extends StatefulWidget {
  const _PromptDialog({required this.title, required this.label, required this.action, required this.initial});

  final String title;
  final String label;
  final String action;
  final String initial;

  @override
  State<_PromptDialog> createState() => _PromptDialogState();
}

class _PromptDialogState extends State<_PromptDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: TextField(
          controller: _controller,
          autofocus: true,
          decoration: InputDecoration(labelText: widget.label),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, _controller.text), child: Text(widget.action)),
        ],
      );
}

Future<bool> confirm(BuildContext context, {required String title, required String message, required String action}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(action)),
      ],
    ),
  );
  return ok ?? false;
}

void showError(BuildContext context, Object error) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(error))));
}

void showMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

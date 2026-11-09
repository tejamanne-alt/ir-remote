/// A single-field text dialog that owns its controller, so the controller
/// lives as long as the dialog (including its closing animation).
library;

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// Shows the dialog; returns the trimmed text, or `null` if cancelled or
/// empty.
Future<String?> showTextInputDialog(
  BuildContext context, {
  required String title,
  required String confirmLabel,
  String initial = '',
  String? fieldLabel,
  int maxLength = 40,
}) async {
  final v = await showDialog<String>(
    context: context,
    builder: (_) => _TextInputDialog(
      title: title,
      confirmLabel: confirmLabel,
      initial: initial,
      fieldLabel: fieldLabel,
      maxLength: maxLength,
    ),
  );
  final t = v?.trim();
  return t == null || t.isEmpty ? null : t;
}

class _TextInputDialog extends StatefulWidget {
  const _TextInputDialog({
    required this.title,
    required this.confirmLabel,
    required this.initial,
    required this.fieldLabel,
    required this.maxLength,
  });

  final String title;
  final String confirmLabel;
  final String initial;
  final String? fieldLabel;
  final int maxLength;

  @override
  State<_TextInputDialog> createState() => _TextInputDialogState();
}

class _TextInputDialogState extends State<_TextInputDialog> {
  late final _c = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _c,
        autofocus: true,
        maxLength: widget.maxLength,
        decoration: InputDecoration(labelText: widget.fieldLabel),
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.actionCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _c.text),
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

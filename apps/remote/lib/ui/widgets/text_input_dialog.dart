/// A single-field text dialog that owns its controller, so the controller
/// lives as long as the dialog (including its closing animation).
library;

import 'package:flutter/material.dart';

import '../../data/names.dart';
import '../../l10n/app_localizations.dart';

/// Shows the dialog; returns the trimmed text, or `null` if cancelled or
/// empty. The text never exceeds [maxLength] UTF-16 code units, the unit
/// the database checks (an emoji is two or more), so a returned name always
/// saves.
Future<String?> showTextInputDialog(
  BuildContext context, {
  required String title,
  required String confirmLabel,
  String initial = '',
  String? fieldLabel,
  int maxLength = maxNameLength,
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

  bool get _fits => fitsName(_c.text, widget.maxLength);

  void _submit() {
    if (!_fits) return;
    Navigator.pop(context, _c.text);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final used = _c.text.trim().length;
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _c,
        autofocus: true,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          labelText: widget.fieldLabel,
          // Counts what the database counts, not visible characters.
          counterText: '$used/${widget.maxLength}',
          errorText: _fits ? null : l.nameTooLong(widget.maxLength),
          errorMaxLines: 3,
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.actionCancel),
        ),
        FilledButton(
          onPressed: _fits ? _submit : null,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

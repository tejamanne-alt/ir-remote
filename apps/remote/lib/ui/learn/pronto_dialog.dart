/// Adding a button from pasted Pronto Hex.
library;

import 'package:flutter/material.dart';
import 'package:ir_core/ir_core.dart';

import '../../data/models.dart';
import '../../l10n/app_localizations.dart';
import '../../services/app_services.dart';
import 'learn_screen.dart';

/// Result of the Pronto dialog.
final class ProntoEntry {
  /// Creates an entry.
  const ProntoEntry(this.label, this.signal);

  /// Button name typed by the user.
  final String label;

  /// Parsed signal.
  final IrSignal signal;
}

/// Asks for a button name and Pronto Hex; returns `null` if cancelled.
Future<ProntoEntry?> showProntoDialog(
  BuildContext context, {
  String? initialLabel,
}) => showDialog<ProntoEntry>(
  context: context,
  builder: (_) => _ProntoDialog(initialLabel: initialLabel),
);

/// Adds a Pronto button to [device].
Future<void> addProntoKey(BuildContext context, SavedDevice device) async {
  final services = AppScope.of(context);
  final entry = await showProntoDialog(context);
  if (entry == null) return;
  final k = keyFromCapture(
    Keys.normalize(entry.label),
    entry.label,
    entry.signal,
    position: device.keys.length,
  );
  await services.devices.upsertKey(
    device.id,
    SavedKey(
      key: k.key,
      label: k.label,
      signal: k.protocol == null ? entry.signal : k.signal,
      toggled: k.toggled,
      source: KeySource.imported,
      protocol: k.protocol,
      params: k.params,
      position: k.position,
    ),
  );
}

class _ProntoDialog extends StatefulWidget {
  const _ProntoDialog({this.initialLabel});

  final String? initialLabel;

  @override
  State<_ProntoDialog> createState() => _ProntoDialogState();
}

class _ProntoDialogState extends State<_ProntoDialog> {
  late final _label = TextEditingController(text: widget.initialLabel ?? '');
  final _code = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _label.dispose();
    _code.dispose();
    super.dispose();
  }

  void _submit() {
    final l = AppLocalizations.of(context);
    final label = _label.text.trim();
    if (label.isEmpty) return;
    try {
      final s = Pronto.parse(_code.text);
      Navigator.of(context).pop(ProntoEntry(label, s));
    } on FormatException catch (e) {
      setState(() => _error = l.prontoInvalid(e.message));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l.prontoTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _label,
              maxLength: 24,
              decoration: InputDecoration(labelText: l.prontoKeyLabel),
            ),
            TextField(
              controller: _code,
              minLines: 3,
              maxLines: 6,
              decoration: InputDecoration(
                hintText: l.prontoHint,
                errorText: _error,
                errorMaxLines: 3,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.actionCancel),
        ),
        FilledButton(onPressed: _submit, child: Text(l.actionAdd)),
      ],
    );
  }
}

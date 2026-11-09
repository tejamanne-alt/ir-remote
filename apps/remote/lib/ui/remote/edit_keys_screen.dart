/// Custom remote builder: drag to reorder buttons, rename and delete them.
/// New buttons come from learning, Pronto paste or a Flipper import. Buttons
/// always use theme colours.
library;

import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../l10n/app_localizations.dart';
import '../../services/app_services.dart';
import '../labels.dart';
import '../learn/flipper_import.dart';
import '../learn/learn_screen.dart';
import '../learn/pronto_dialog.dart';
import '../widgets/text_input_dialog.dart';

/// Writes [keys] back with positions 0..n-1 in list order.
Future<void> saveKeyOrder(
  AppServices s,
  String deviceId,
  List<SavedKey> keys,
) async {
  for (final (i, k) in keys.indexed) {
    if (k.position == i) continue;
    await s.devices.upsertKey(
      deviceId,
      SavedKey(
        key: k.key,
        label: k.label,
        signal: k.signal,
        toggled: k.toggled,
        source: k.source,
        protocol: k.protocol,
        params: k.params,
        position: i,
      ),
    );
  }
}

/// Edits the buttons of a remote.
class EditKeysScreen extends StatelessWidget {
  /// Creates the screen.
  const EditKeysScreen({super.key, required this.deviceId});

  /// Remote being edited.
  final String deviceId;

  Future<void> _rename(BuildContext context, SavedKey k) async {
    final l = AppLocalizations.of(context);
    final s = AppScope.of(context);
    final name = await showTextInputDialog(
      context,
      title: l.deviceMenuRename,
      confirmLabel: l.actionSave,
      initial: k.label ?? keyLabel(l, k.key),
      maxLength: 24,
    );
    if (name == null) return;
    await s.devices.upsertKey(
      deviceId,
      SavedKey(
        key: k.key,
        label: name,
        signal: k.signal,
        toggled: k.toggled,
        source: k.source,
        protocol: k.protocol,
        params: k.params,
        position: k.position,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final s = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.editButtonsTitle)),
      body: SafeArea(
        child: StreamBuilder<SavedDevice?>(
          stream: s.devices.watch(deviceId),
          builder: (context, snap) {
            final device = snap.data;
            if (device == null) return const SizedBox.shrink();
            final keys = device.keys.values.toList()
              ..sort((a, b) => a.position.compareTo(b.position));
            return ReorderableListView(
              header: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(l.editButtonsHint),
              ),
              footer: Padding(
                padding: const EdgeInsets.all(16),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      icon: const Icon(Icons.school_outlined),
                      label: Text(l.deviceMenuLearn),
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => LearnScreen(deviceId: deviceId),
                        ),
                      ),
                    ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.content_paste),
                      label: Text(l.deviceMenuPronto),
                      onPressed: () => addProntoKey(context, device),
                    ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.file_open_outlined),
                      label: Text(l.optionImportFlipper),
                      onPressed: () => importFlipperInto(context, deviceId),
                    ),
                  ],
                ),
              ),
              onReorderItem: (from, to) async {
                final next = [...keys];
                next.insert(to, next.removeAt(from));
                await saveKeyOrder(s, deviceId, next);
              },
              children: [
                for (final k in keys)
                  ListTile(
                    key: ValueKey(k.key),
                    minTileHeight: 56,
                    title: Text(keyLabel(l, k.key, customLabel: k.label)),
                    subtitle: Text(_sourceLabel(l, k.source)),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: l.deviceMenuRename,
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: () => _rename(context, k),
                        ),
                        IconButton(
                          tooltip: l.actionDelete,
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => s.devices.deleteKey(deviceId, k.key),
                        ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

String _sourceLabel(AppLocalizations l, KeySource s) => switch (s) {
  KeySource.database => l.keySourceDatabase,
  KeySource.learned => l.keySourceLearned,
  KeySource.imported => l.keySourceImported,
};

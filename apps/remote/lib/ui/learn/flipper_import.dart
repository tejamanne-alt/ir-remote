/// Importing buttons from a Flipper `.ir` file into a remote.
library;

import 'package:flutter/material.dart';
import 'package:ir_core/ir_core.dart';

import '../../data/models.dart';
import '../../l10n/app_localizations.dart';
import '../../services/app_services.dart';
import '../../services/file_io.dart';
import '../widgets/remote_button.dart';

/// Converts parsed Flipper signals into saved keys, numbering positions
/// after [startPosition]. Signals whose codes cannot be rendered are skipped.
List<SavedKey> keysFromFlipper(
  FlipperParseResult result, {
  int startPosition = 0,
}) {
  final out = <SavedKey>[];
  final seen = <String>{};
  var pos = startPosition;
  for (final s in result.signals) {
    final name = Keys.normalize(s.name);
    if (!seen.add(name)) continue; // first occurrence wins
    try {
      final k = snapshotKey(name, s.code, position: pos);
      out.add(
        SavedKey(
          key: k.key,
          label: s.name,
          signal: k.signal,
          toggled: k.toggled,
          source: KeySource.imported,
          protocol: k.protocol,
          params: k.params,
          position: pos++,
        ),
      );
    } on Object {
      continue;
    }
  }
  return out;
}

/// Lets the user pick a `.ir` file and adds its buttons to [deviceId].
/// Returns the number of buttons imported, or `null` if cancelled.
Future<int?> importFlipperInto(
  BuildContext context,
  String deviceId, {
  FileIo? io,
}) async {
  final services = AppScope.of(context);
  final l = AppLocalizations.of(context);
  try {
    final text = await (io ?? services.files).pickText(
      extensions: const ['ir'],
    );
    if (text == null) return null;
    final parsed = FlipperIr.parse(text);
    final device = await services.devices.load(deviceId);
    if (device == null) return null;
    final keys = keysFromFlipper(parsed, startPosition: device.keys.length);
    for (final k in keys) {
      await services.devices.upsertKey(deviceId, k);
    }
    if (context.mounted) showSendError(context, l.importedKeys(keys.length));
    return keys.length;
  } on FormatException catch (e) {
    if (context.mounted) showSendError(context, l.importFailed(e.message));
  } on FileTooLargeException catch (e) {
    if (context.mounted) showSendError(context, l.importFailed('$e'));
  }
  return null;
}

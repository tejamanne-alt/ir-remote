/// Backup and restore of all user data as a JSON file.
library;

import 'package:flutter/material.dart';

import '../../data/backup.dart';
import '../../l10n/app_localizations.dart';
import '../../services/app_services.dart';
import '../../services/file_io.dart';

/// Export and import.
class BackupScreen extends StatefulWidget {
  /// Creates the screen.
  const BackupScreen({super.key});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  bool _busy = false;
  String? _message;

  Future<void> _export() async {
    final s = AppScope.of(context);
    final l = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      final text = await BackupCodec(s.db).export();
      final stamp = DateTime.now().toIso8601String().substring(0, 10);
      await s.files.shareText('irremote-backup-$stamp.json', text);
      if (mounted) setState(() => _message = l.backupExported);
    } on Object catch (e) {
      if (mounted) setState(() => _message = l.importFailed('$e'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    final s = AppScope.of(context);
    final l = AppLocalizations.of(context);
    String? text;
    try {
      text = await s.files.pickText(extensions: const ['json']);
    } on FileTooLargeException catch (e) {
      setState(() => _message = l.importFailed('$e'));
      return;
    }
    if (text == null || !mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(l.backupRestoreConfirmTitle),
        content: Text(l.backupRestoreConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(l.actionCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(l.backupRestore),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await BackupCodec(s.db).import(text);
      await s.reloadAfterRestore();
      if (mounted) setState(() => _message = l.backupRestored);
    } on FormatException catch (e) {
      if (mounted) setState(() => _message = l.importFailed(e.message));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.settingsBackup)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(l.backupBody),
            const SizedBox(height: 24),
            FilledButton.icon(
              icon: const Icon(Icons.upload_file),
              label: Text(l.backupExport),
              onPressed: _busy ? null : _export,
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.download),
              label: Text(l.backupRestore),
              onPressed: _busy ? null : _import,
            ),
            if (_message != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Semantics(liveRegion: true, child: Text(_message!)),
              ),
          ],
        ),
      ),
    );
  }
}

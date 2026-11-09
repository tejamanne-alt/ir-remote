/// Macros: list, editor (drag to reorder) and a run screen with progress and
/// Cancel. Macros run only when the user taps Run.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/macros.dart';
import '../../data/models.dart';
import '../../l10n/app_localizations.dart';
import '../../services/app_services.dart';
import '../../services/macro_runner.dart';
import '../labels.dart';

/// Delays offered between steps.
const List<Duration> macroDelays = [
  Duration.zero,
  Duration(milliseconds: 500),
  Duration(seconds: 1),
  Duration(seconds: 2),
  Duration(seconds: 5),
  Duration(seconds: 10),
  Duration(seconds: 30),
];

/// The macro list.
class MacrosScreen extends StatelessWidget {
  /// Creates the screen.
  const MacrosScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final s = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.macrosTitle)),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: Text(l.macroNew),
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const MacroEditorScreen()),
        ),
      ),
      body: SafeArea(
        child: StreamBuilder<List<Macro>>(
          stream: s.macros.watch(),
          builder: (context, snap) {
            final list = snap.data ?? const <Macro>[];
            if (list.isEmpty) {
              return Padding(
                padding: const EdgeInsets.all(24),
                child: Text(l.macrosEmpty),
              );
            }
            return ListView(
              children: [
                for (final m in list)
                  ListTile(
                    minTileHeight: 64,
                    title: Text(m.name),
                    subtitle: Text(l.macroStepCount(m.steps.length)),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => MacroEditorScreen(existing: m),
                      ),
                    ),
                    trailing: FilledButton.tonal(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => MacroRunScreen(macro: m),
                        ),
                      ),
                      child: Text(l.macroRun),
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

/// Creates or edits a macro.
class MacroEditorScreen extends StatefulWidget {
  /// Creates the editor; [existing] edits a saved macro.
  const MacroEditorScreen({super.key, this.existing});

  /// Macro being edited.
  final Macro? existing;

  @override
  State<MacroEditorScreen> createState() => _MacroEditorScreenState();
}

class _MacroEditorScreenState extends State<MacroEditorScreen> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final List<MacroStep> _steps = [...?widget.existing?.steps];
  List<SavedDevice> _devices = const [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadDevices();
  }

  Future<void> _loadDevices() async {
    final s = AppScope.of(context);
    final list = await s.devices.watchDevices().first;
    final full = <SavedDevice>[
      for (final d in list) ?await s.devices.load(d.id),
    ];
    if (mounted) setState(() => _devices = full);
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _addStep() async {
    final l = AppLocalizations.of(context);
    if (_devices.isEmpty) return;
    var device = _devices.first;
    String? key = device.keys.keys.isEmpty ? null : device.keys.keys.first;
    var delay = Duration.zero;
    final step = await showDialog<MacroStep>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: Text(l.macroAddStep),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: device.id,
                decoration: InputDecoration(labelText: l.macroDevice),
                items: [
                  for (final d in _devices)
                    DropdownMenuItem(value: d.id, child: Text(d.name)),
                ],
                onChanged: (id) => set(() {
                  device = _devices.firstWhere((d) => d.id == id);
                  key = device.keys.keys.isEmpty
                      ? null
                      : device.keys.keys.first;
                }),
              ),
              DropdownButtonFormField<String>(
                key: ValueKey(device.id),
                initialValue: key,
                decoration: InputDecoration(labelText: l.macroKey),
                items: [
                  for (final k in device.keys.values)
                    DropdownMenuItem(
                      value: k.key,
                      child: Text(keyLabel(l, k.key, customLabel: k.label)),
                    ),
                ],
                onChanged: (k) => set(() => key = k),
              ),
              DropdownButtonFormField<Duration>(
                initialValue: delay,
                decoration: InputDecoration(labelText: l.macroDelay),
                items: [
                  for (final d in macroDelays)
                    DropdownMenuItem(
                      value: d,
                      child: Text(
                        l.macroDelaySeconds(
                          (d.inMilliseconds / 1000).toString(),
                        ),
                      ),
                    ),
                ],
                onChanged: (d) => set(() => delay = d ?? Duration.zero),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: Text(l.actionCancel),
            ),
            FilledButton(
              onPressed: key == null
                  ? null
                  : () => Navigator.pop(
                      c,
                      MacroStep(deviceId: device.id, key: key!, delay: delay),
                    ),
              child: Text(l.actionAdd),
            ),
          ],
        ),
      ),
    );
    if (step != null) setState(() => _steps.add(step));
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty || _steps.isEmpty) return;
    final s = AppScope.of(context);
    await s.macros.save(
      Macro(
        id: widget.existing?.id ?? newId(),
        name: name.length > 40 ? name.substring(0, 40) : name,
        steps: _steps.take(Macro.maxSteps).toList(),
        createdAt: widget.existing?.createdAt ?? DateTime.now(),
      ),
    );
    if (mounted) Navigator.of(context).pop();
  }

  String _stepTitle(AppLocalizations l, MacroStep step) {
    final d = _devices.where((d) => d.id == step.deviceId).firstOrNull;
    final label = d?.keys[step.key]?.label;
    return '${d?.name ?? '?'} · ${keyLabel(l, step.key, customLabel: label)}';
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final s = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? l.macroNew : l.macroEdit),
        actions: [
          if (widget.existing != null)
            IconButton(
              tooltip: l.actionDelete,
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                final nav = Navigator.of(context);
                await s.macros.delete(widget.existing!.id);
                nav.pop();
              },
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.check),
        label: Text(l.actionSave),
        onPressed: _save,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _name,
                maxLength: 40,
                decoration: InputDecoration(labelText: l.macroName),
              ),
            ),
            Expanded(
              child: ReorderableListView(
                onReorderItem: (from, to) => setState(() {
                  _steps.insert(to, _steps.removeAt(from));
                }),
                footer: Padding(
                  padding: const EdgeInsets.all(16),
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.add),
                    label: Text(l.macroAddStep),
                    onPressed: _devices.isEmpty ? null : _addStep,
                  ),
                ),
                children: [
                  for (final (i, step) in _steps.indexed)
                    ListTile(
                      key: ValueKey('$i-${step.deviceId}-${step.key}'),
                      minTileHeight: 56,
                      leading: Text('${i + 1}'),
                      title: Text(_stepTitle(l, step)),
                      subtitle: Text(
                        l.macroDelaySeconds(
                          (step.delay.inMilliseconds / 1000).toString(),
                        ),
                      ),
                      trailing: IconButton(
                        tooltip: l.actionDelete,
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(() => _steps.removeAt(i)),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Runs a macro with visible progress and a Cancel button.
class MacroRunScreen extends StatefulWidget {
  /// Creates the screen.
  const MacroRunScreen({super.key, required this.macro});

  /// Macro to run.
  final Macro macro;

  @override
  State<MacroRunScreen> createState() => _MacroRunScreenState();
}

class _MacroRunScreenState extends State<MacroRunScreen> {
  MacroRun? _run;
  StreamSubscription<MacroProgress>? _sub;
  MacroProgress? _last;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_run != null) return;
    final run = AppScope.of(context).macroRunner.run(widget.macro);
    _run = run;
    _sub = run.events.listen((e) => setState(() => _last = e));
  }

  @override
  void dispose() {
    _run?.cancel();
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final total = widget.macro.steps.length;
    final (text, value, done) = switch (_last) {
      null => (l.macroStarting, 0.0, false),
      MacroStepStarted(:final index) => (
        l.macroProgress(index + 1, total),
        (index + 1) / total,
        false,
      ),
      MacroCompleted() => (l.macroDone, 1.0, true),
      MacroCancelled() => (l.macroCancelled, null, true),
      MacroStepFailed(:final index, :final outcome, :final missingDevice) => (
        missingDevice
            ? l.macroMissingDevice(index + 1)
            : l.macroFailed(
                index + 1,
                outcome == null ? '' : outcomeMessage(l, outcome) ?? '',
              ),
        null,
        true,
      ),
    };
    return Scaffold(
      appBar: AppBar(title: Text(widget.macro.name)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                liveRegion: true,
                child: Text(
                  text,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              const SizedBox(height: 16),
              LinearProgressIndicator(value: value),
              const SizedBox(height: 24),
              if (!done)
                FilledButton(
                  onPressed: () => _run?.cancel(),
                  child: Text(l.actionCancel),
                )
              else
                OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(l.actionDone),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

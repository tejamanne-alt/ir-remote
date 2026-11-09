/// Learning a button from an original remote through a hub with a receiver.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:ir_core/ir_core.dart';
import 'package:ir_transports/ir_transports.dart';

import '../../data/models.dart';
import '../../l10n/app_localizations.dart';
import '../../services/app_services.dart';
import '../hubs/hubs_screen.dart';
import '../labels.dart';
import '../widgets/remote_button.dart';

/// Turns a capture into a saved key: re-encoded through the codec when the
/// protocol is recognised (clean timings and the protocol's repeat rule),
/// otherwise the raw capture.
SavedKey keyFromCapture(
  String keyName,
  String? label,
  IrSignal capture, {
  int position = 0,
}) {
  final decoded = ProtocolRegistry.standard.identify(capture.durationsUs);
  if (decoded != null && !decoded.isRepeatFrame) {
    final p = ProtocolRegistry.standard.require(decoded.protocolId);
    final base = snapshotKey(
      keyName,
      ProtocolKeyCode(p.id, decoded.params),
      position: position,
    );
    return SavedKey(
      key: keyName,
      label: label,
      signal: base.signal,
      toggled: base.toggled,
      source: KeySource.learned,
      protocol: base.protocol,
      params: base.params,
      position: position,
    );
  }
  return SavedKey(
    key: keyName,
    label: label,
    signal: capture,
    source: KeySource.learned,
    position: position,
  );
}

/// Maps a user-typed button name onto the key vocabulary.
String keyNameFor(String label) => Keys.normalize(label);

enum _Phase { idle, waiting, captured, failed }

/// Learns one button at a time into [deviceId].
class LearnScreen extends StatefulWidget {
  /// Creates the screen.
  const LearnScreen({super.key, required this.deviceId});

  /// Remote that receives the learned keys.
  final String deviceId;

  @override
  State<LearnScreen> createState() => _LearnScreenState();
}

class _LearnScreenState extends State<LearnScreen> {
  final _name = TextEditingController();
  _Phase _phase = _Phase.idle;
  StreamSubscription<LearnedSignal>? _sub;
  IrSignal? _capture;
  String? _error;
  String? _decodedName;

  IrTransport? _learner(AppServices s) {
    for (final t in s.registry.all) {
      if (!t.caps.canLearn) continue;
      if (t.kind == TransportKind.simulated && !kDebugMode) continue;
      return t;
    }
    return null;
  }

  void _start() {
    final s = AppScope.of(context);
    final t = _learner(s);
    final stream = t?.learn();
    if (stream == null) return;
    setState(() {
      _phase = _Phase.waiting;
      _capture = null;
      _error = null;
    });
    _sub?.cancel();
    _sub = stream.listen(
      (c) {
        final d = ProtocolRegistry.standard.identify(c.signal.durationsUs);
        setState(() {
          _capture = c.signal;
          _decodedName = d != null && !d.isRepeatFrame ? d.protocolId : null;
          _phase = _Phase.captured;
        });
        _sub?.cancel();
      },
      onError: (Object e) => setState(() {
        _phase = _Phase.failed;
        _error = e is LearnTimeoutException ? null : '$e';
      }),
    );
  }

  Future<void> _save() async {
    final s = AppScope.of(context);
    final label = _name.text.trim();
    final capture = _capture;
    if (label.isEmpty || capture == null) return;
    final device = await s.devices.load(widget.deviceId);
    if (device == null) return;
    final key = keyFromCapture(
      keyNameFor(label),
      label,
      capture,
      position: device.keys.length,
    );
    await s.devices.upsertKey(device.id, key);
    if (!mounted) return;
    setState(() {
      _phase = _Phase.idle;
      _capture = null;
      _name.clear();
    });
  }

  Future<void> _test() async {
    final capture = _capture;
    if (capture == null) return;
    final s = AppScope.of(context);
    final l = AppLocalizations.of(context);
    final device = await s.devices.load(widget.deviceId);
    if (device == null) return;
    final o = await s.send.sendSignal(device, capture);
    if (!mounted) return;
    final msg = outcomeMessage(l, o);
    if (msg != null) showSendError(context, msg);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final s = AppScope.of(context);
    final learner = _learner(s);
    return Scaffold(
      appBar: AppBar(title: Text(l.learnTitle)),
      body: SafeArea(
        child: learner == null
            ? _NoHub(l: l)
            : ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  TextField(
                    controller: _name,
                    maxLength: 24,
                    decoration: InputDecoration(labelText: l.learnNameLabel),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    l.learnPrompt,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 24),
                  ..._phaseWidgets(l),
                ],
              ),
      ),
    );
  }

  List<Widget> _phaseWidgets(AppLocalizations l) => switch (_phase) {
    _Phase.idle => [FilledButton(onPressed: _start, child: Text(l.learnStart))],
    _Phase.waiting => [
      const Center(child: CircularProgressIndicator()),
      const SizedBox(height: 12),
      Center(child: Text(l.learnWaiting)),
    ],
    _Phase.captured => [
      Semantics(
        liveRegion: true,
        child: Text(
          l.learnCaptured,
          style: Theme.of(context).textTheme.titleLarge,
        ),
      ),
      Text(_decodedName != null ? l.learnDecoded(_decodedName!) : l.learnRaw),
      const SizedBox(height: 16),
      Row(
        children: [
          OutlinedButton(onPressed: _test, child: Text(l.learnTest)),
          const SizedBox(width: 12),
          FilledButton(
            onPressed: _name.text.trim().isEmpty ? null : _save,
            child: Text(l.actionSave),
          ),
          const SizedBox(width: 12),
          TextButton(onPressed: _start, child: Text(l.learnRetry)),
        ],
      ),
    ],
    _Phase.failed => [
      Semantics(
        liveRegion: true,
        child: Text(_error == null ? l.learnTimeout : l.learnError(_error!)),
      ),
      const SizedBox(height: 12),
      FilledButton(onPressed: _start, child: Text(l.learnRetry)),
    ],
  };
}

class _NoHub extends StatelessWidget {
  const _NoHub({required this.l});

  final AppLocalizations l;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(l.learnNoHub, textAlign: TextAlign.center),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () => Navigator.of(
            context,
          ).push(MaterialPageRoute<void>(builder: (_) => const HubsScreen())),
          child: Text(l.actionConnectHub),
        ),
      ],
    ),
  );
}

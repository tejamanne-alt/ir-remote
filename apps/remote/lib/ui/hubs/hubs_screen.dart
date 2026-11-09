/// Hubs: list with health, discovery, manual add and pairing.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ir_core/ir_core.dart';
import 'package:ir_transports/ir_transports.dart';

import '../../data/models.dart';
import '../../l10n/app_localizations.dart';
import '../../services/app_services.dart';
import '../../services/hub_service.dart';

/// Validates a dotted IPv4 address.
bool isValidIpv4(String s) {
  final parts = s.trim().split('.');
  if (parts.length != 4) return false;
  for (final p in parts) {
    final n = int.tryParse(p);
    if (n == null || n < 0 || n > 255 || p.isEmpty || p.length > 3) {
      return false;
    }
  }
  return true;
}

/// The hubs list.
class HubsScreen extends StatefulWidget {
  /// Creates the screen. With [startAdding] the add sheet opens at once.
  const HubsScreen({super.key, this.startAdding = false});

  /// Open the add flow immediately (onboarding).
  final bool startAdding;

  @override
  State<HubsScreen> createState() => _HubsScreenState();
}

class _HubsScreenState extends State<HubsScreen> {
  @override
  void initState() {
    super.initState();
    if (widget.startAdding) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _add());
    }
  }

  Future<void> _add() =>
      Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: (_) => const AddHubScreen()));

  String _status(AppLocalizations l, HealthStatus? h) => switch (h) {
    null => l.hubChecking,
    Healthy() => l.hubHealthy,
    Degraded(:final reason) => l.hubDegraded(reason),
    Unreachable(:final reason) => l.hubUnreachable(reason),
  };

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final services = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.hubsTitle)),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: Text(l.hubAdd),
        onPressed: _add,
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: services.hubs,
          builder: (context, _) {
            final builtIn = services.registry.builtIn;
            final simulator = services.registry.byId('simulated');
            final hubs = services.hubs.hubs;
            return ListView(
              padding: const EdgeInsets.only(bottom: 96),
              children: [
                if (builtIn != null)
                  ListTile(
                    leading: const Icon(Icons.smartphone),
                    title: Text(l.builtInEmitter),
                    subtitle: Text(l.hubHealthy),
                  ),
                if (simulator != null)
                  ListTile(
                    leading: const Icon(Icons.bug_report_outlined),
                    title: Text(l.simulatorName),
                  ),
                if (hubs.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(l.hubsEmpty),
                  ),
                for (final h in hubs)
                  ListTile(
                    minTileHeight: 64,
                    leading: Icon(
                      h.kind == TransportKind.broadlink
                          ? Icons.router
                          : Icons.memory,
                    ),
                    title: Text(h.name),
                    subtitle: Text(
                      '${h.host} · ${_status(l, services.hubs.healthOf(h.id))}',
                    ),
                    trailing: PopupMenuButton<String>(
                      onSelected: (v) async {
                        if (v == 'check') await services.hubs.check(h.id);
                        if (v == 'pair' && context.mounted) {
                          await Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => PairBridgeScreen(hub: h),
                            ),
                          );
                        }
                        if (v == 'remove' && context.mounted) {
                          await _remove(context, h);
                        }
                      },
                      itemBuilder: (_) => [
                        PopupMenuItem(
                          value: 'check',
                          child: Text(l.hubCheckNow),
                        ),
                        if (h.kind == TransportKind.espBridge)
                          PopupMenuItem(value: 'pair', child: Text(l.hubPair)),
                        PopupMenuItem(
                          value: 'remove',
                          child: Text(l.hubRemove),
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

  Future<void> _remove(BuildContext context, HubRecord h) async {
    final l = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        content: Text(l.hubRemoveConfirm(h.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(l.actionCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(l.hubRemove),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      await AppScope.of(context).hubs.remove(h.id);
    }
  }
}

/// Adds a hub: Bonjour discovery for bridges, or a typed address.
class AddHubScreen extends StatefulWidget {
  /// Creates the screen.
  const AddHubScreen({
    super.key,
    this.browseTimeout = const Duration(seconds: 8),
  });

  /// After this long with no results, show the Local Network recovery hint.
  final Duration browseTimeout;

  @override
  State<AddHubScreen> createState() => _AddHubScreenState();
}

class _AddHubScreenState extends State<AddHubScreen> {
  StreamSubscription<List<DiscoveredBridge>>? _sub;
  List<DiscoveredBridge> _found = const [];
  bool _browseTimedOut = false;
  Timer? _timer;
  final _address = TextEditingController();
  TransportKind _kind = TransportKind.espBridge;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _browse());
  }

  void _browse() {
    final services = AppScope.of(context);
    _sub = services.hubs.discovery.discover().listen(
      (list) {
        if (mounted) setState(() => _found = list);
      },
      onError: (Object _) {
        if (mounted) setState(() => _browseTimedOut = true);
      },
    );
    _timer = Timer(widget.browseTimeout, () {
      if (mounted && _found.isEmpty) setState(() => _browseTimedOut = true);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _timer?.cancel();
    _address.dispose();
    super.dispose();
  }

  Future<void> _addBridge(String host, int port) async {
    final services = AppScope.of(context);
    final l = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final hub = await services.hubs.addEspBridge(host, port: port);
      if (!mounted) return;
      if (hub.token != null) {
        // Already paired: its address was updated, nothing else to do.
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l.hubUpdated(hub.name))));
        Navigator.of(context).pop();
        return;
      }
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => PairBridgeScreen(hub: hub)),
      );
    } on Object catch (e) {
      if (mounted) setState(() => _error = l.hubPairFailed('$e'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addManual() async {
    final l = AppLocalizations.of(context);
    final host = _address.text.trim();
    if (!isValidIpv4(host) || !isLanHost(host)) {
      setState(() => _error = l.hubAddressError);
      return;
    }
    if (_kind == TransportKind.espBridge) {
      await _addBridge(host, 80);
    } else {
      await _addBroadlink(host);
    }
  }

  Future<void> _addBroadlink(String host) async {
    final services = AppScope.of(context);
    final l = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await services.hubs.addBroadlink(host);
      if (mounted) Navigator.of(context).pop();
    } on Object catch (e) {
      if (mounted) setState(() => _error = l.broadlinkAddFailed('$e'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final services = AppScope.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.hubAdd)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(l.hubFound, style: theme.textTheme.titleMedium),
            if (_found.isEmpty && !_browseTimedOut)
              ListTile(
                leading: const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                title: Text(l.hubDiscovering),
              ),
            if (_found.isEmpty && _browseTimedOut) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(l.hubNoneFound),
              ),
              if (services.isIos)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.wifi_lock),
                    title: Text(l.localNetworkDeniedTitle),
                    subtitle: Text(l.localNetworkDeniedBody),
                  ),
                ),
            ],
            for (final b in _found)
              ListTile(
                minTileHeight: 64,
                leading: const Icon(Icons.memory),
                title: Text(b.name),
                subtitle: Text(
                  services.hubs.addedHubFor(b) == null
                      ? b.host
                      : l.hubAlreadyAdded(b.host),
                ),
                trailing: services.hubs.addedHubFor(b) == null
                    ? null
                    : const Icon(Icons.check_circle_outline),
                onTap: _busy ? null : () => _addBridge(b.host, b.port),
              ),
            const Divider(height: 32),
            Text(l.hubManual, style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            SegmentedButton<TransportKind>(
              segments: [
                ButtonSegment(
                  value: TransportKind.espBridge,
                  label: Text(l.hubKindEsp),
                ),
                ButtonSegment(
                  value: TransportKind.broadlink,
                  label: Text(l.hubKindBroadlink),
                ),
              ],
              selected: {_kind},
              onSelectionChanged: (v) => setState(() => _kind = v.first),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _address,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: l.hubAddressLabel,
                hintText: '192.168.1.40',
              ),
            ),
            if (_kind == TransportKind.broadlink)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(l.broadlinkNote, style: theme.textTheme.bodySmall),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error!,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _busy ? null : _addManual,
              child: Text(l.actionAdd),
            ),
          ],
        ),
      ),
    );
  }
}

/// Pairs an ESP32 bridge: the user presses its button, then taps Pair.
class PairBridgeScreen extends StatefulWidget {
  /// Creates the screen.
  const PairBridgeScreen({super.key, required this.hub});

  /// The bridge.
  final HubRecord hub;

  @override
  State<PairBridgeScreen> createState() => _PairBridgeScreenState();
}

class _PairBridgeScreenState extends State<PairBridgeScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _pair() async {
    final l = AppLocalizations.of(context);
    final services = AppScope.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await services.hubs.pairEspBridge(widget.hub, 'IR Remote app');
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l.hubPaired(widget.hub.name))));
      Navigator.of(context).pop();
    } on BridgeException catch (e) {
      // The user may have left the screen while the request was pending.
      if (!mounted) return;
      setState(
        () => _error = e.code == 'pairing_window_closed'
            ? l.hubPairWindowClosed
            : l.hubPairFailed(e.detail),
      );
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _error = l.hubPairFailed('$e'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.hubPairTitle(widget.hub.name))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Icon(Icons.touch_app_outlined, size: 64),
            const SizedBox(height: 16),
            Text(l.hubPairBody, style: theme.textTheme.titleMedium),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    _error!,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
              ),
            const SizedBox(height: 24),
            FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
              ),
              onPressed: _busy ? null : _pair,
              child: Text(l.hubPair),
            ),
          ],
        ),
      ),
    );
  }
}

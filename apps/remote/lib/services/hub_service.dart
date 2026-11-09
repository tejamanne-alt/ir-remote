/// Hubs: persistence, transports, discovery and pairing.
library;

import 'dart:async';

import 'package:bonsoir/bonsoir.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:ir_core/ir_core.dart';
import 'package:ir_transports/ir_transports.dart';

import '../data/models.dart';
import '../data/repositories.dart';

/// A bridge found by Bonjour/mDNS.
final class DiscoveredBridge {
  /// Creates a discovery result.
  const DiscoveredBridge({
    required this.name,
    required this.host,
    required this.port,
    this.id,
  });

  /// Advertised name.
  final String name;

  /// Resolved IP address.
  final String host;

  /// Port.
  final int port;

  /// MAC-based ID from TXT records, if present.
  final String? id;
}

/// Finds ESP32 bridges on the LAN.
abstract interface class BridgeDiscovery {
  /// Emits the current list of bridges while listened to; cancelling stops
  /// the browse.
  Stream<List<DiscoveredBridge>> discover();
}

/// Bonjour/NSD discovery of `_irbridge._tcp` through bonsoir. On iOS this
/// uses the system Bonjour browser, which needs no multicast entitlement.
final class BonsoirBridgeDiscovery implements BridgeDiscovery {
  /// Creates the discovery.
  const BonsoirBridgeDiscovery({
    this.network = const MethodChannel('irremote/network'),
  });

  /// Service type advertised by the bridge firmware.
  static const serviceType = '_irbridge._tcp';

  /// Android multicast-lock channel.
  final MethodChannel network;

  @override
  Stream<List<DiscoveredBridge>> discover() {
    late StreamController<List<DiscoveredBridge>> controller;
    BonsoirDiscovery? discovery;
    StreamSubscription<BonsoirDiscoveryEvent>? sub;
    final found = <String, DiscoveredBridge>{};

    Future<void> lock({required bool on}) async {
      if (defaultTargetPlatform != TargetPlatform.android) return;
      try {
        await network.invokeMethod<bool>(
          on ? 'acquireMulticastLock' : 'releaseMulticastLock',
        );
      } on Object {
        // discovery still works on most devices without the lock
      }
    }

    controller = StreamController<List<DiscoveredBridge>>(
      onListen: () async {
        try {
          await lock(on: true);
          final d = BonsoirDiscovery(type: serviceType);
          discovery = d;
          await d.initialize();
          sub = d.eventStream?.listen((event) {
            switch (event) {
              case BonsoirDiscoveryServiceFoundEvent():
                event.service.resolve(d.serviceResolver);
              case BonsoirDiscoveryServiceResolvedEvent():
                final s = event.service;
                final addresses = s.hostAddresses;
                final host = addresses.firstWhere(
                  (a) => a.contains('.') && !a.contains(':'),
                  orElse: () => addresses.isEmpty ? '' : addresses.first,
                );
                if (host.isEmpty) return;
                found[s.name] = DiscoveredBridge(
                  name: s.attributes['name'] ?? s.name,
                  host: host,
                  port: s.port,
                  id: s.attributes['id'],
                );
                controller.add(found.values.toList());
              case BonsoirDiscoveryServiceLostEvent():
                found.remove(event.service.name);
                controller.add(found.values.toList());
              default:
                break;
            }
          });
          await d.start();
          controller.add(const []);
        } on Object catch (e) {
          controller.addError(e);
        }
      },
      onCancel: () async {
        await sub?.cancel();
        try {
          await discovery?.stop();
        } on Object {
          // already stopped
        }
        await lock(on: false);
        await controller.close();
      },
    );
    return controller.stream;
  }
}

/// Creates transports for hub records (injectable for tests).
typedef HubTransportFactory = IrTransport Function(HubRecord record);

/// Manages hubs and keeps the registry in sync with the hubs table.
final class HubService extends ChangeNotifier {
  /// Creates the service.
  HubService({
    required this.repo,
    required this.registry,
    required this.devices,
    HubTransportFactory? factory,
    this.discovery = const BonsoirBridgeDiscovery(),
    DateTime Function()? clock,
  }) : _factory = factory ?? defaultHubTransport,
       _clock = clock ?? DateTime.now;

  /// Hub table.
  final HubRepository repo;

  /// Transport registry.
  final TransportRegistry registry;

  /// For clearing transport choices when a hub is removed.
  final DeviceRepository devices;

  /// LAN discovery.
  final BridgeDiscovery discovery;

  final HubTransportFactory _factory;
  final DateTime Function() _clock;
  List<HubRecord> _hubs = const [];

  /// Known hubs.
  List<HubRecord> get hubs => _hubs;

  /// The default factory: ESP32 bridge (and Broadlink once wired).
  static IrTransport defaultHubTransport(HubRecord h) => switch (h.kind) {
    TransportKind.espBridge => EspBridgeTransport(
      baseUri: Uri(scheme: 'http', host: h.host, port: h.port),
      id: h.id,
      displayName: h.name,
      token: h.token,
    ),
    _ => throw UnsupportedError('hub kind ${h.kind.name} is not available'),
  };

  /// Loads hubs from the database, registers their transports and checks
  /// their health in the background.
  Future<void> loadAll() async {
    _hubs = await repo.all();
    for (final h in _hubs) {
      try {
        await registry.register(_factory(h));
      } on UnsupportedError {
        continue;
      }
    }
    notifyListeners();
    unawaited(registry.checkAll().then((_) => notifyListeners()));
  }

  /// Health of a hub, if checked.
  HealthStatus? healthOf(String id) => registry.healthOf(id);

  /// Re-checks one hub.
  Future<HealthStatus> check(String id) async {
    final h = await registry.checkHealth(id);
    notifyListeners();
    return h;
  }

  /// Adds an ESP32 bridge at [host]:[port] (unpaired) after reading its
  /// info. Throws [BridgeException], [FormatException] or I/O errors.
  Future<HubRecord> addEspBridge(String host, {int port = 80}) async {
    final probe = EspBridgeTransport(
      baseUri: Uri(scheme: 'http', host: host, port: port),
      id: 'probe',
    );
    try {
      final info = await probe.fetchInfo();
      final record = HubRecord(
        id: 'esp:${info.id}',
        kind: TransportKind.espBridge,
        name: info.name,
        host: host,
        port: port,
      );
      await _save(record);
      return record;
    } finally {
      await probe.dispose();
    }
  }

  /// Pairs an ESP32 bridge while its button window is open. Throws
  /// [BridgeException] with code `pairing_window_closed` otherwise.
  Future<void> pairEspBridge(HubRecord hub, String clientName) async {
    final t = EspBridgeTransport(
      baseUri: Uri(scheme: 'http', host: hub.host, port: hub.port),
      id: hub.id,
    );
    try {
      final token = await t.pair(clientName);
      await _save(
        HubRecord(
          id: hub.id,
          kind: hub.kind,
          name: hub.name,
          host: hub.host,
          port: hub.port,
          token: token,
          extra: hub.extra,
        ),
      );
    } finally {
      await t.dispose();
    }
    await check(hub.id);
  }

  /// Adds a Broadlink hub at [host] (unicast hello and auth). Throws when
  /// the hub cannot be reached or authenticated.
  Future<HubRecord> addBroadlink(String host) async {
    final connect = broadlinkConnector;
    if (connect == null) {
      throw UnsupportedError(
        'Broadlink support is not available in this build',
      );
    }
    final record = await connect(host);
    await _save(record);
    await check(record.id);
    return record;
  }

  /// Probes a Broadlink hub at a host and returns its record.
  Future<HubRecord> Function(String host)? broadlinkConnector;

  /// Saves an already-built record.
  Future<void> saveRecord(HubRecord record) => _save(record);

  Future<void> _save(HubRecord record) async {
    await repo.upsert(record, _clock());
    try {
      await registry.register(_factory(record));
    } on UnsupportedError {
      // stored, but no transport in this build
    }
    _hubs = await repo.all();
    notifyListeners();
  }

  /// Removes a hub; remotes that chose it fall back to automatic.
  Future<void> remove(String id) async {
    await registry.unregister(id);
    await repo.delete(id);
    await devices.clearTransport(id);
    _hubs = await repo.all();
    notifyListeners();
  }
}

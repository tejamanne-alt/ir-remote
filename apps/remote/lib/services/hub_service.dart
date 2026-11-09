/// Hubs: persistence, transports, discovery and pairing.
library;

import 'dart:async';
import 'dart:io';

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

/// Thrown when a hub address is outside the local network.
final class NotLanAddressException implements Exception {
  /// Creates the exception.
  const NotLanAddressException();

  @override
  String toString() => 'Hubs must be on your local network.';
}

/// Finds ESP32 bridges on the LAN.
abstract interface class BridgeDiscovery {
  /// Emits the current list of bridges while listened to; cancelling stops
  /// the browse.
  Stream<List<DiscoveredBridge>> discover();
}

/// The part of an mDNS browser that [BonsoirBridgeDiscovery] drives, so the
/// browse lifecycle can be tested without the platform plugin.
abstract interface class MdnsBrowser {
  /// Prepares the browser (platform channel set-up).
  Future<void> initialize();

  /// Browse events; available after [initialize].
  Stream<BonsoirDiscoveryEvent>? get eventStream;

  /// Starts browsing.
  Future<void> start();

  /// Stops browsing and releases the platform browser.
  Future<void> stop();

  /// Asks the platform to resolve [service]'s addresses.
  void resolve(BonsoirService service);
}

final class _BonsoirBrowser implements MdnsBrowser {
  _BonsoirBrowser(String type) : _d = BonsoirDiscovery(type: type);

  final BonsoirDiscovery _d;

  @override
  Future<void> initialize() => _d.initialize();

  @override
  Stream<BonsoirDiscoveryEvent>? get eventStream => _d.eventStream;

  @override
  Future<void> start() => _d.start();

  @override
  Future<void> stop() => _d.stop();

  @override
  void resolve(BonsoirService service) => service.resolve(_d.serviceResolver);
}

/// Bonjour/NSD discovery of `_irbridge._tcp` through bonsoir. On iOS this
/// uses the system Bonjour browser, which needs no multicast entitlement.
final class BonsoirBridgeDiscovery implements BridgeDiscovery {
  /// Creates the discovery.
  const BonsoirBridgeDiscovery({
    this.network = const MethodChannel('irremote/network'),
    this.browserFactory = _defaultBrowser,
  });

  /// Service type advertised by the bridge firmware.
  static const serviceType = '_irbridge._tcp';

  /// Android multicast-lock channel.
  final MethodChannel network;

  /// Creates the platform browser for [serviceType] (tests inject a fake).
  final MdnsBrowser Function(String type) browserFactory;

  static MdnsBrowser _defaultBrowser(String type) => _BonsoirBrowser(type);

  @override
  Stream<List<DiscoveredBridge>> discover() {
    late StreamController<List<DiscoveredBridge>> controller;
    MdnsBrowser? browser;
    StreamSubscription<BonsoirDiscoveryEvent>? sub;
    final found = <String, DiscoveredBridge>{};
    // Set when the listener cancels. onListen re-checks it after every
    // await, because a cancel can arrive while it waits for the lock or the
    // platform browser, after onCancel has already run.
    var cancelled = false;
    var locked = false;

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

    // Stops whatever has been started so far. Each part is stopped once:
    // a part started after an earlier call is stopped by the next one.
    Future<void> stopAll() async {
      await sub?.cancel();
      sub = null;
      final b = browser;
      browser = null;
      if (b != null) {
        try {
          await b.stop();
        } on Object {
          // already stopped
        }
      }
      if (locked) {
        locked = false;
        await lock(on: false);
      }
    }

    void emit(List<DiscoveredBridge> list) {
      if (!cancelled && !controller.isClosed) controller.add(list);
    }

    controller = StreamController<List<DiscoveredBridge>>(
      onListen: () async {
        try {
          locked = true;
          await lock(on: true);
          if (cancelled) return await stopAll();
          final d = browserFactory(serviceType);
          await d.initialize();
          // Registered only once initialized, so it is never stopped
          // half-way through its set-up.
          browser = d;
          if (cancelled) return await stopAll();
          sub = d.eventStream?.listen((event) {
            switch (event) {
              case BonsoirDiscoveryServiceFoundEvent():
                d.resolve(event.service);
              case BonsoirDiscoveryServiceResolvedEvent():
                final s = event.service;
                final addresses = s.hostAddresses;
                final host = addresses.firstWhere(
                  (a) => a.contains('.') && !a.contains(':'),
                  orElse: () => addresses.isEmpty ? '' : addresses.first,
                );
                if (host.isEmpty || !isLanHost(host)) return;
                found[s.name] = DiscoveredBridge(
                  name: s.attributes['name'] ?? s.name,
                  host: host,
                  port: s.port,
                  id: s.attributes['id'],
                );
                emit(found.values.toList());
              case BonsoirDiscoveryServiceLostEvent():
                found.remove(event.service.name);
                emit(found.values.toList());
              default:
                break;
            }
          });
          await d.start();
          if (cancelled) return await stopAll();
          emit(const []);
        } on Object catch (e) {
          if (cancelled || controller.isClosed) {
            await stopAll();
          } else {
            controller.addError(e);
          }
        }
      },
      onCancel: () async {
        cancelled = true;
        await stopAll();
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

  /// The default factory: ESP32 bridge or Broadlink hub.
  static IrTransport defaultHubTransport(HubRecord h) {
    if (!isLanHost(h.host)) {
      // Never open sockets outside the LAN, even for a hub restored from a
      // crafted backup.
      throw UnsupportedError(
        'hub address ${h.host} is not on the local network',
      );
    }
    return _transportFor(h);
  }

  static IrTransport _transportFor(HubRecord h) => switch (h.kind) {
    TransportKind.espBridge => EspBridgeTransport(
      baseUri: Uri(scheme: 'http', host: h.host, port: h.port),
      id: h.id,
      displayName: h.name,
      token: h.token,
    ),
    TransportKind.broadlink => BroadlinkTransport(
      device: BroadlinkDeviceInfo(
        address: InternetAddress(h.host),
        port: h.port,
        mac: parseMac(h.extra['mac']),
        devtype: h.extra['devtype'] is int ? h.extra['devtype']! as int : 0,
        name: h.name,
      ),
      displayName: h.name,
    ),
    _ => throw UnsupportedError('hub kind ${h.kind.name} is not available'),
  };

  /// Parses a stored `aa:bb:cc:dd:ee:ff` MAC; throws [UnsupportedError]
  /// (the hub is then kept but not registered) when it is damaged.
  static List<int> parseMac(Object? v) {
    if (v is String) {
      final parts = v.split(':');
      if (parts.length == 6) {
        final bytes = [for (final p in parts) int.tryParse(p, radix: 16)];
        if (bytes.every((b) => b != null && b >= 0 && b <= 255)) {
          return [for (final b in bytes) b!];
        }
      }
    }
    throw UnsupportedError('stored Broadlink MAC is invalid');
  }

  /// Probes a Broadlink hub with a unicast hello (the primary path: iOS
  /// cannot broadcast without Apple's multicast entitlement).
  static Future<HubRecord> probeBroadlink(String host) async {
    if (!isLanHost(host)) throw const NotLanAddressException();
    final t = await BroadlinkTransport.connect(InternetAddress(host));
    try {
      final d = t.device;
      if (d.model == null) {
        throw UnsupportedError(
          'device type ${d.devtypeHex} is not a supported RM hub',
        );
      }
      return HubRecord(
        id: t.id,
        kind: TransportKind.broadlink,
        name: t.displayName,
        host: d.address.address,
        port: d.port,
        extra: {'mac': d.macString, 'devtype': d.devtype},
      );
    } finally {
      await t.dispose();
    }
  }

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
  /// info. A bridge that is already added keeps its record (ID, name and
  /// pairing token); only its address moves to [host]:[port]. Throws
  /// [BridgeException], [FormatException] or I/O errors.
  Future<HubRecord> addEspBridge(String host, {int port = 80}) async {
    if (!isLanHost(host)) throw const NotLanAddressException();
    final probe = EspBridgeTransport(
      baseUri: Uri(scheme: 'http', host: host, port: port),
      id: 'probe',
    );
    try {
      final info = await probe.fetchInfo();
      final id = 'esp:${info.id}';
      final existing = await _stored(id);
      if (existing == null) {
        final record = HubRecord(
          id: id,
          kind: TransportKind.espBridge,
          name: info.name,
          host: host,
          port: port,
        );
        await _save(record);
        return record;
      }
      final moved = HubRecord(
        id: existing.id,
        kind: existing.kind,
        name: existing.name,
        host: host,
        port: port,
        token: existing.token,
        extra: existing.extra,
      );
      await repo.updateAddress(existing.id, host: host, port: port);
      await _register(moved);
      return moved;
    } finally {
      await probe.dispose();
    }
  }

  Future<HubRecord?> _stored(String id) async {
    for (final h in await repo.all()) {
      if (h.id == id) return h;
    }
    return null;
  }

  /// The added hub [bridge] is, if any: the same bridge ID, or the same
  /// address for a bridge that advertises no ID.
  HubRecord? addedHubFor(DiscoveredBridge bridge) {
    for (final h in _hubs) {
      if (h.kind != TransportKind.espBridge) continue;
      final id = bridge.id;
      if (id != null ? h.id == 'esp:$id' : h.host == bridge.host) return h;
    }
    return null;
  }

  /// Pairs an ESP32 bridge while its button window is open. Throws
  /// [BridgeException] with code `pairing_window_closed` otherwise.
  Future<void> pairEspBridge(HubRecord hub, String clientName) async {
    if (!isLanHost(hub.host)) throw const NotLanAddressException();
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

  /// Probes a Broadlink hub at a host and returns its record. Replaceable
  /// in tests.
  Future<HubRecord> Function(String host)? broadlinkConnector = probeBroadlink;

  /// Saves an already-built record.
  Future<void> saveRecord(HubRecord record) => _save(record);

  Future<void> _save(HubRecord record) async {
    await repo.upsert(record, _clock());
    await _register(record);
  }

  Future<void> _register(HubRecord record) async {
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

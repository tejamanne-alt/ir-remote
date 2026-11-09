/// Wires services together and exposes them to the widget tree.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:ir_core/ir_core.dart';
import 'package:ir_transports/ir_transports.dart';

import '../data/database.dart';
import '../data/macros.dart';
import '../data/repositories.dart';
import '../transports/android_consumer_ir.dart';
import 'app_settings.dart';
import 'code_library.dart';
import 'file_io.dart';
import 'hub_service.dart';
import 'macro_runner.dart';
import 'send_service.dart';
import 'signal_log.dart';

/// Every long-lived service.
final class AppServices {
  AppServices._({
    required this.db,
    required this.devices,
    required this.settings,
    required this.registry,
    required this.send,
    required this.hubs,
    required this.codes,
    required this.log,
    required this.emitter,
    required this.platform,
    required this.files,
  }) : macros = MacroRepository(db),
       macroRunner = MacroRunner(send: send, devices: devices);

  /// Builds services around [db]. [codes] is the read-only code library.
  static Future<AppServices> create({
    required AppDatabase db,
    required CodeLibrary codes,
    EmitterInfo? emitter,
    TargetPlatform? platform,
    BridgeDiscovery? discovery,
    HubTransportFactory? hubFactory,
    List<IrTransport> extraTransports = const [],
    FileIo files = const PlatformFileIo(),
  }) async {
    final log = SignalLog();
    final registry = TransportRegistry(onRecord: kDebugMode ? log.add : null);
    final devices = DeviceRepository(db);
    final settings = await AppSettings.load(SettingsRepository(db));
    final p = platform ?? defaultTargetPlatform;
    final info = emitter ?? await detectEmitter(platform: p);
    if (info.canTransmit) {
      var quirks = const <OemQuirk>[];
      try {
        quirks = OemQuirk.parseTable(
          await rootBundle.loadString('assets/oem_quirks.json'),
        );
      } on Object {
        quirks = const [];
      }
      await registry.register(AndroidConsumerIrTransport(info, quirks: quirks));
    }
    for (final t in extraTransports) {
      await registry.register(t);
    }
    if (settings.useSimulator) {
      await registry.register(SimulatedTransport(displayName: 'Simulator'));
    }
    final hubs = HubService(
      repo: HubRepository(db),
      registry: registry,
      devices: devices,
      discovery: discovery ?? const BonsoirBridgeDiscovery(),
      factory: hubFactory,
    );
    await hubs.loadAll();
    return AppServices._(
      db: db,
      devices: devices,
      settings: settings,
      registry: registry,
      send: SendService(registry: registry, devices: devices),
      hubs: hubs,
      codes: codes,
      log: log,
      emitter: info,
      platform: p,
      files: files,
    );
  }

  /// User-data database.
  final AppDatabase db;

  /// Saved remotes and rooms.
  final DeviceRepository devices;

  /// Preferences.
  final AppSettings settings;

  /// Transports.
  final TransportRegistry registry;

  /// Send pipeline.
  final SendService send;

  /// Hubs.
  final HubService hubs;

  /// Read-only code library.
  final CodeLibrary codes;

  /// Signal Inspector log (debug builds).
  final SignalLog log;

  /// Built-in emitter detection result.
  final EmitterInfo emitter;

  /// Platform the app runs on.
  final TargetPlatform platform;

  /// File picking and sharing.
  final FileIo files;

  /// Macros.
  final MacroRepository macros;

  /// Runs macros.
  final MacroRunner macroRunner;

  /// Refreshes cached state after a backup restore.
  Future<void> reloadAfterRestore() async {
    await settings.reload();
    for (final t in registry.hubs.toList()) {
      await registry.unregister(t.id);
    }
    await hubs.loadAll();
  }

  /// Whether this is an iPhone/iPad (hubs only).
  bool get isIos => platform == TargetPlatform.iOS;

  /// Turns the simulator on or off at runtime (debug builds).
  Future<void> setSimulator({required bool enabled}) async {
    await settings.setUseSimulator(value: enabled);
    if (settings.useSimulator) {
      await registry.register(SimulatedTransport(displayName: 'Simulator'));
    } else {
      await registry.unregister('simulated');
    }
  }

  /// Whether anything can send right now.
  bool get canSend => registry.resolve() != null;

  /// Closes everything.
  Future<void> dispose() async {
    await registry.dispose();
    await db.close();
  }
}

/// Makes [AppServices] available below it.
class AppScope extends InheritedWidget {
  /// Creates the scope.
  const AppScope({super.key, required this.services, required super.child});

  /// The services.
  final AppServices services;

  /// The nearest services.
  static AppServices of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'No AppScope above this widget');
    return scope!.services;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) => services != oldWidget.services;
}

/// Resolves the remote's category to the key it uses to confirm a match.
String confirmKeyFor(DeviceCategory c) => switch (c) {
  DeviceCategory.tv ||
  DeviceCategory.setTopBox ||
  DeviceCategory.soundbar => Keys.volUp,
  DeviceCategory.airConditioner => Keys.tempUp,
  DeviceCategory.fan || DeviceCategory.airPurifier => Keys.speedUp,
  DeviceCategory.projector => Keys.menu,
  DeviceCategory.generic => Keys.power,
};

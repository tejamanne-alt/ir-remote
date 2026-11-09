import 'dart:async';

import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ir_core/ir_core.dart';
import 'package:ir_transports/ir_transports.dart';
import 'package:irremote/app.dart';
import 'package:irremote/data/database.dart';
import 'package:irremote/services/app_services.dart';
import 'package:irremote/services/code_library.dart';
import 'package:irremote/services/file_io.dart';
import 'package:irremote/services/hub_service.dart';
import 'package:irremote/transports/android_consumer_ir.dart';

const testProvenance = Provenance(
  source: 'test-fixture',
  sourceUrl: 'https://example.invalid/fixtures',
  sourceCommit: 'test',
  license: 'MIT',
  importedAt: '2026-11-09',
);

CodeSet _necx2(String id, String brand, int d, {int rank = 0}) => CodeSet(
  id: id,
  brand: brand,
  category: DeviceCategory.tv,
  provenance: testProvenance,
  rank: rank,
  keys: {
    Keys.power: ProtocolKeyCode('NECx2', {'D': d, 'S': d, 'F': 2}),
    Keys.volUp: ProtocolKeyCode('NECx2', {'D': d, 'S': d, 'F': 7}),
    Keys.volDown: ProtocolKeyCode('NECx2', {'D': d, 'S': d, 'F': 11}),
    Keys.mute: ProtocolKeyCode('NECx2', {'D': d, 'S': d, 'F': 15}),
    Keys.ok: ProtocolKeyCode('NECx2', {'D': d, 'S': d, 'F': 104}),
    Keys.digit1: ProtocolKeyCode('NECx2', {'D': d, 'S': d, 'F': 4}),
  },
);

/// Fixture library: two Samsung-style sets, one LG set, one RC5 set (toggle).
InMemoryCodeLibrary testLibrary() => InMemoryCodeLibrary(
  [
    _necx2('samsung-a', 'Samsung', 7),
    _necx2('samsung-b', 'Samsung', 5, rank: 1),
    CodeSet(
      id: 'lg-a',
      brand: 'LG',
      category: DeviceCategory.tv,
      provenance: testProvenance,
      keys: {
        Keys.power: const ProtocolKeyCode('NEC1', {'D': 4, 'F': 8}),
        Keys.volUp: const ProtocolKeyCode('NEC1', {'D': 4, 'F': 2}),
      },
    ),
    CodeSet(
      id: 'philips-a',
      brand: 'Philips',
      category: DeviceCategory.tv,
      provenance: testProvenance,
      keys: {
        Keys.power: const ProtocolKeyCode('RC5', {'D': 0, 'F': 12}),
        Keys.volUp: const ProtocolKeyCode('RC5', {'D': 0, 'F': 16}),
      },
    ),
  ],
  ranking: const {
    DeviceCategory.tv: ['Samsung', 'LG', 'Sony'],
  },
  notices: const [
    DataSourceNotice(
      source: 'test-fixture',
      url: 'https://example.invalid/fixtures',
      license: 'MIT',
      notice: 'Fixture notice text.',
    ),
  ],
);

final class FakeFileIo implements FileIo {
  String? nextPick;

  /// When set, the next pick throws this instead of returning [nextPick].
  Object? nextError;
  final List<(String, String)> shared = [];

  @override
  Future<String?> pickText({List<String> extensions = const []}) async {
    final e = nextError;
    if (e != null) {
      nextError = null;
      throw e;
    }
    return nextPick;
  }

  @override
  Future<void> shareText(String name, String text) async =>
      shared.add((name, text));
}

final class FakeDiscovery implements BridgeDiscovery {
  // Closed by the test zone; broadcast streams need no listener cleanup.
  // ignore: close_sinks
  final StreamController<List<DiscoveredBridge>> controller =
      StreamController.broadcast();

  @override
  Stream<List<DiscoveredBridge>> discover() => controller.stream;
}

AppDatabase memoryDb() => AppDatabase(
  DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true),
);

/// Builds services over an in-memory database with the simulator registered.
Future<(AppServices, SimulatedTransport)> buildServices({
  EmitterInfo emitter = EmitterInfo.none,
  TargetPlatform platform = TargetPlatform.android,
  CodeLibrary? codes,
  BridgeDiscovery? discovery,
  bool withSimulator = true,
  FileIo? files,
  List<IrTransport> extraTransports = const [],
}) async {
  final sim = SimulatedTransport();
  final services = await AppServices.create(
    db: memoryDb(),
    codes: codes ?? testLibrary(),
    emitter: emitter,
    platform: platform,
    discovery: discovery ?? FakeDiscovery(),
    extraTransports: [...extraTransports, if (withSimulator) sim],
    files: files ?? FakeFileIo(),
  );
  return (services, sim);
}

/// Pumps the app. Database work runs on real async, so settle in runAsync.
Future<void> pumpApp(
  WidgetTester tester,
  AppServices services, {
  bool onboarded = true,
}) async {
  if (onboarded) {
    await tester.runAsync(() => services.settings.completeOnboarding());
  }
  await tester.pumpWidget(IrRemoteApp(services: services));
  await settle(tester);
}

/// Lets database streams and futures complete, then settles frames.
/// Never uses pumpAndSettle: progress indicators animate forever.
Future<void> settle(WidgetTester tester, {int rounds = 4}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
  // Let route transitions and short animations finish.
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> disposeServices(WidgetTester tester, AppServices s) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.runAsync(s.dispose);
}

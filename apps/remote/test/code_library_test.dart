// The app's adapter over the real bundled code database.
import 'dart:io';

import 'package:code_db/code_db.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ir_core/ir_core.dart';
import 'package:irremote/services/code_library.dart';
import 'package:irremote/services/code_library_loader.dart';

final class _EmptyBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) =>
      Future.error(FlutterError('no asset $key'));
}

/// Serves the real manifest and the given database bytes.
final class _Bundle extends CachingAssetBundle {
  _Bundle(this.db);

  final List<int> db;

  @override
  Future<ByteData> load(String key) async {
    final bytes = key.endsWith('.json')
        ? File('../../packages/code_db/assets/codes.manifest.json')
              .readAsBytesSync()
        : Uint8List.fromList(db);
    return ByteData.sublistView(Uint8List.fromList(bytes));
  }
}

void main() {
  late CodeDbLibrary lib;
  setUpAll(() {
    final path = File('../../packages/code_db/assets/codes.sqlite')
        .absolute
        .path;
    final manifest = CodeDbManifest.parse(
      File('../../packages/code_db/assets/codes.manifest.json')
          .readAsStringSync(),
    );
    lib = CodeDbLibrary(
      CodeDb.open(path, expectedContentHash: manifest.contentSha256),
    );
  });
  tearDownAll(() => lib.db.close());

  test('primary-market TV brands come first', () {
    final names = [for (final b in lib.brands(DeviceCategory.tv)) b.name];
    expect(names.take(3), ['Samsung', 'LG', 'Sony']);
    expect(lib.brands(DeviceCategory.tv).first.primaryMarket, isTrue);
    expect(
      lib.brands(DeviceCategory.tv, query: 'sams').map((b) => b.name),
      contains('Samsung'),
    );
  });

  test('every Samsung TV set renders its power test key through the codecs', () {
    final sets = lib.codeSets(DeviceCategory.tv, brand: 'Samsung');
    expect(sets, isNotEmpty);
    var rendered = 0;
    for (final s in sets) {
      final key = s.powerTestKey;
      if (key == null) continue;
      final signal = resolveKey(s, key);
      expect(signal.durationsUs.length.isOdd, isTrue);
      rendered++;
    }
    expect(rendered, greaterThan(0));
    // The best-ranked Samsung TV set includes the well-known NECx2 power code.
    final first = sets.first.keys[Keys.power];
    if (first is ProtocolKeyCode) {
      expect(ProtocolRegistry.standard.require(first.protocol).id, 'NECx2');
    }
  });

  test('"Not listed" offers one set per brand, best brands first', () {
    final sets = lib.codeSets(DeviceCategory.tv, limit: 10);
    expect(sets.length, 10);
    expect(sets.first.brand, 'Samsung');
    expect({for (final s in sets) s.brand}.length, 10);
    expect(lib.byId(sets.first.id)!.id, sets.first.id);
  });

  test('the Licenses screen gets every source notice', () {
    expect(lib.notices, isNotEmpty);
    expect(lib.notices.first.source, startsWith('flipperdevices/irdb'));
    expect(lib.notices.first.notice, isNotEmpty);
  });

  test(
    'a missing asset falls back to an empty library instead of failing',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final l = await loadBundledCodeLibrary(bundle: _EmptyBundle());
      expect(l, isA<InMemoryCodeLibrary>());
      expect(l.brands(DeviceCategory.tv), isEmpty);
    },
  );

  group('copying the bundled database', () {
    late Directory dir;
    late String target;
    setUp(() {
      dir = Directory.systemTemp.createTempSync('codes');
      final manifest = CodeDbManifest.parse(
        File('../../packages/code_db/assets/codes.manifest.json')
            .readAsStringSync(),
      );
      target =
          '${dir.path}/codes-${manifest.fileSha256.substring(0, 16)}.sqlite';
      File('${dir.path}/codes-0000000000000000.sqlite')
          .writeAsStringSync('older copy');
    });
    tearDown(() => dir.deleteSync(recursive: true));
    final real = File('../../packages/code_db/assets/codes.sqlite')
        .readAsBytesSync();

    List<String> names() =>
        [for (final f in dir.listSync()) f.uri.pathSegments.last]..sort();

    test('a copy that fails verification keeps the older copy', () async {
      final damaged = [...real]..[real.length ~/ 2] ^= 0xff;
      final l = await loadBundledCodeLibrary(
        bundle: _Bundle(damaged),
        supportDirectory: () async => dir,
      );
      expect(l, isA<InMemoryCodeLibrary>());
      expect(names(), ['codes-0000000000000000.sqlite']);
    });

    test('a failed write leaves no partial .tmp behind', () async {
      // The final path is taken by a directory, so the rename fails after
      // the .tmp has been written.
      Directory(target).createSync();
      final l = await loadBundledCodeLibrary(
        bundle: _Bundle(real),
        supportDirectory: () async => dir,
      );
      expect(l, isA<InMemoryCodeLibrary>());
      expect(names().where((n) => n.endsWith('.tmp')), isEmpty);
      expect(
        File('${dir.path}/codes-0000000000000000.sqlite').existsSync(),
        isTrue,
      );
    });

    test('a verified copy replaces the older ones', () async {
      File('${dir.path}/codes-1111111111111111.sqlite.tmp')
          .writeAsStringSync('partial');
      final l = await loadBundledCodeLibrary(
        bundle: _Bundle(real),
        supportDirectory: () async => dir,
      );
      expect(l, isA<CodeDbLibrary>());
      (l as CodeDbLibrary).db.close();
      expect(names(), [target.split('/').last]);
    });
  });
}

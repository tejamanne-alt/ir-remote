// Checks the committed assets/codes.sqlite against its manifest and sidecar,
// gate L1 on every row, and that every key resolves to a signal.
import 'dart:io';

import 'package:code_db/code_db.dart';
import 'package:crypto/crypto.dart';
import 'package:ir_core/ir_core.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

const _dir = 'assets';

void main() {
  final dbFile = File('$_dir/${BundledCodeDb.fileName}');
  final manifest = CodeDbManifest.parse(
    File('$_dir/${BundledCodeDb.manifestName}').readAsStringSync(),
  );
  late CodeDb db;
  setUpAll(
    () => db = CodeDb.open(
      dbFile.path,
      expectedContentHash: manifest.contentSha256,
    ),
  );
  tearDownAll(() => db.close());

  test('manifest, sidecar and file agree', () {
    final bytes = dbFile.readAsBytesSync();
    expect(bytes.length, manifest.fileBytes);
    expect(sha256.convert(bytes).toString(), manifest.fileSha256);
    expect(
      File('$_dir/${BundledCodeDb.sidecarName}').readAsStringSync(),
      '${manifest.contentSha256}\n',
    );
    expect(db.contentHash, manifest.contentSha256);
    expect(manifest.schemaVersion, codeDbSchemaVersion);
    final t = db.totals();
    expect(manifest.counts['codeSets'], t.codeSets);
    expect(manifest.counts['brands'], t.brands);
    expect(manifest.counts['keyCodes'], t.keyCodes);
  });

  test('stays within the 20 MB compressed budget', () {
    expect(
      gzip.encode(dbFile.readAsBytesSync()).length,
      lessThan(20 * 1000 * 1000),
    );
  });

  test('gate L1: every code set row carries full provenance', () {
    final raw = sqlite3.open(dbFile.path, mode: OpenMode.readOnly);
    addTearDown(raw.close);
    final missing = raw.select(
      "SELECT COUNT(*) FROM code_set WHERE trim(source) = '' "
      "OR trim(source_url) = '' OR trim(source_commit) = '' "
      "OR trim(license) = '' OR trim(imported_at) = '' "
      'OR source NOT IN (SELECT name FROM source)',
    );
    expect(missing.first.columnAt(0), 0);
    for (final s in db.sources()) {
      expect([
        s.url,
        s.commit,
        s.license,
        s.importedAt,
        s.notice,
      ], everyElement(isNotEmpty));
      expect(manifest.sources.map((m) => m.commit), contains(s.commit));
    }
  });

  test('gate L4: no irdb data without a recorded announcement issue', () {
    final names = db.sources().map((s) => s.name).toSet();
    if (names.contains('probonopd/irdb')) {
      expect(db.meta['irdb_announcement_issue'], isNotEmpty);
    } else {
      expect(db.meta.containsKey('irdb_announcement_issue'), isFalse);
    }
    expect(names, isNot(contains('UberGuidoZ/Flipper-IRDB')));
  });

  test('well-known power codes are present for ranked TV brands', () {
    bool has(String brand, String desc) => db
        .codeSets(brand, DeviceCategory.tv)
        .map((s) => s.keys[Keys.power])
        .whereType<ProtocolKeyCode>()
        .any((k) => '${k.protocol} ${k.params}' == desc);
    expect(has('Samsung', 'NECx2 {D: 7, S: 7, F: 2}'), isTrue);
    expect(has('LG', 'NEC1 {D: 4, S: 251, F: 8}'), isTrue);
    expect(has('Sony', 'Sony12 {D: 1, F: 21}'), isTrue);
    expect(has('Panasonic', 'Panasonic {D: 128, S: 0, F: 61}'), isTrue);
    expect(db.brands(DeviceCategory.tv).first.name, 'Samsung');
    expect(
      db.brands(DeviceCategory.tv).takeWhile((b) => b.primaryMarket).length,
      greaterThanOrEqualTo(5),
    );
  });

  test('every key of every code set resolves to a valid signal', () {
    var keys = 0;
    for (final c in db.categories()) {
      for (final b in db.brands(c.category)) {
        final sets = db.codeSets(b.name, c.category);
        expect(sets, hasLength(b.codeSetCount));
        expect(sets.map((s) => s.rank), List.generate(sets.length, (i) => i));
        for (final set in sets) {
          for (final key in set.keys.keys) {
            expect(Keys.isValid(key), isTrue, reason: key);
            final s = resolveKey(set, key);
            expect(s.durationsUs.length.isOdd, isTrue);
            expect(s.durationsUs.every((d) => d > 0 && d <= 150000), isTrue);
            keys++;
          }
        }
      }
    }
    expect(keys, db.totals().keyCodes);
  });

  test('add-device queries are fast', () {
    final sw = Stopwatch()..start();
    for (var i = 0; i < 10; i++) {
      db
        ..categories()
        ..brands(DeviceCategory.tv)
        ..brands(DeviceCategory.tv, search: 'sam')
        ..codeSets('Samsung', DeviceCategory.tv);
    }
    expect(sw.elapsedMilliseconds / 10, lessThan(100));
  });
}

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:code_db/code_db.dart';
import 'package:code_db/src/encoding.dart';
import 'package:ir_core/ir_core.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

const _fz = CodeDbSource(
  name: 'flipperdevices/irdb',
  url: 'https://github.com/flipperdevices/irdb',
  commit: 'f7b15366521cc81ba11b341538f0097bddbb748b',
  license: 'MIT',
  importedAt: '2026-04-24',
  notice: 'MIT License\n\nCopyright (c) Flipper Zero\n...',
);

Provenance _prov(String path, {CodeDbSource s = _fz}) => Provenance(
  source: s.name,
  sourceUrl: s.url,
  sourceCommit: s.commit,
  license: s.license,
  importedAt: s.importedAt,
  path: path,
);

CodeSet _set(
  String id,
  String brand,
  DeviceCategory category,
  Map<String, KeyCode> keys, {
  int rank = 0,
  String? label,
  Provenance? provenance,
}) => CodeSet(
  id: id,
  brand: brand,
  category: category,
  keys: keys,
  rank: rank,
  label: label,
  provenance: provenance ?? _prov('$id.ir'),
);

ProtocolKeyCode _nec(int d, int f) => ProtocolKeyCode('NEC1', {'D': d, 'F': f});

final _raw = RawKeyCode(
  IrSignal(
    carrierHz: 38000,
    durationsUs: [9000, 4500, 560, 1690, 560, 300000, 560],
    repeat: RepeatSpec(
      frameUs: [9000, 2250, 560],
      leadInGapUs: 40000,
      gapUs: 96000,
      minRepeats: 1,
    ),
  ),
);

CodeDbContent _content({List<CodeDbEntry>? entries}) => CodeDbContent(
  sources: [_fz],
  primaryBrands: {
    DeviceCategory.tv: ['Samsung', 'LG', 'Sony', 'Missing brand'],
  },
  meta: {'build_tool': 'test'},
  entries:
      entries ??
      [
        CodeDbEntry(
          _set('tv-lg-2', 'LG', DeviceCategory.tv, {
            Keys.volUp: _nec(4, 2),
            'custom:Netflix': _nec(4, 86),
          }, rank: 5),
        ),
        CodeDbEntry(
          _set('tv-lg-1', 'LG', DeviceCategory.tv, {
            Keys.volUp: _nec(4, 2),
            Keys.power: _nec(4, 8),
          }, rank: 1),
          mergedIds: ['tv-lg-dup'],
        ),
        CodeDbEntry(
          _set('tv-samsung', 'Samsung', DeviceCategory.tv, {
            Keys.power: const ProtocolKeyCode('Samsung32', {'D': 7, 'F': 2}),
          }, label: 'BN59'),
        ),
        CodeDbEntry(
          _set('tv-acme', 'Acme', DeviceCategory.tv, {Keys.power: _raw}),
        ),
        CodeDbEntry(
          _set('tv-zeta', 'zeta', DeviceCategory.tv, {Keys.power: _nec(1, 1)}),
        ),
        CodeDbEntry(
          _set('fan-acme', 'Acme', DeviceCategory.fan, {
            Keys.power: RawKeyCode(
              IrSignal(carrierHz: 36000, durationsUs: [1200, 400, 1200]),
            ),
            Keys.speed: const ProtocolKeyCode('RC5', {'D': 3, 'F': 9, 'T': 1}),
          }),
        ),
        CodeDbEntry(
          _set('stb-tata', 'Tata Play', DeviceCategory.setTopBox, {
            Keys.guide: _nec(9, 9),
          }),
        ),
      ],
);

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('code_db_test_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  String path(String name) => '${tmp.path}/$name';

  group('writer and loader', () {
    late CodeDbWriteResult written;
    late CodeDb db;
    setUp(() {
      written = CodeDbWriter.write(_content(), path('codes.sqlite'));
      db = CodeDb.open(
        path('codes.sqlite'),
        expectedContentHash: written.contentHash,
      );
    });
    tearDown(() => db.close());

    test('reports counts and hashes', () {
      expect(written.codeSetCount, 7);
      expect(written.brandCount, 5);
      expect(written.keyCount, 10);
      expect(written.aliasCount, 1);
      expect(written.contentHash, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(written.fileBytes, File(path('codes.sqlite')).lengthSync());
      expect(db.contentHash, written.contentHash);
      expect(db.meta['build_tool'], 'test');
      expect(db.meta['schema_version'], '$codeDbSchemaVersion');
      final t = db.totals();
      expect(t.codeSets, 7);
      expect(t.brands, 5);
      expect(t.keyCodes, 10);
      expect(t.mergedDuplicates, 1);
      expect(t.codeSetsBySource, {'flipperdevices/irdb': 7});
    });

    test('lists categories with counts in enum order', () {
      expect(
        db.categories().map((c) => (c.category, c.codeSetCount, c.brandCount)),
        [
          (DeviceCategory.tv, 5, 4),
          (DeviceCategory.setTopBox, 1, 1),
          (DeviceCategory.fan, 1, 1),
        ],
      );
    });

    test('lists primary-market brands first, then alphabetically', () {
      final tv = db.brands(DeviceCategory.tv);
      expect(tv.map((b) => b.name), ['Samsung', 'LG', 'Acme', 'zeta']);
      expect(tv.map((b) => b.primaryMarket), [true, true, false, false]);
      expect(tv[1].codeSetCount, 2);
      expect(db.brands(DeviceCategory.fan).single.primaryMarket, isFalse);
      expect(db.brands(DeviceCategory.airConditioner), isEmpty);
    });

    test('searches brands ignoring case, spaces and punctuation', () {
      expect(db.brands(DeviceCategory.tv, search: 'l').map((b) => b.name), [
        'LG',
      ]);
      expect(
        db.brands(DeviceCategory.tv, search: 'SAM sung').single.name,
        'Samsung',
      );
      expect(
        db.brands(DeviceCategory.setTopBox, search: 'tata-play').single.name,
        'Tata Play',
      );
      // LIKE wildcards in the query are literal.
      expect(db.brands(DeviceCategory.tv, search: '%'), isEmpty);
      expect(db.brands(DeviceCategory.tv, search: r'\'), isEmpty);
      expect(db.brands(DeviceCategory.tv, search: 'nope'), isEmpty);
    });

    test('returns code sets in matching order with keys and provenance', () {
      final lg = db.codeSets('LG', DeviceCategory.tv);
      expect(lg.map((s) => s.id), ['tv-lg-1', 'tv-lg-2']);
      expect(lg.map((s) => s.rank), [0, 1]);
      // Keys come back in vocabulary order, custom keys last.
      expect(lg.first.keys.keys, [Keys.power, Keys.volUp]);
      expect(lg.last.keys.keys, [Keys.volUp, 'custom:Netflix']);
      final power = lg.first.keys[Keys.power]! as ProtocolKeyCode;
      expect(power.protocol, 'NEC1');
      expect(power.params, {'D': 4, 'S': 251, 'F': 8});
      expect(
        resolveKey(lg.first, Keys.power),
        const Nec1().encode(power.params),
      );
      expect(lg.first.protocol, 'NEC1');
      final p = lg.first.provenance;
      expect(p.source, _fz.name);
      expect(p.sourceUrl, _fz.url);
      expect(p.sourceCommit, _fz.commit);
      expect(p.license, 'MIT');
      expect(p.importedAt, '2026-04-24');
      expect(p.path, 'tv-lg-1.ir');
      expect(lg.first.brand, 'LG');
      expect(lg.first.category, DeviceCategory.tv);
      expect(db.codeSets('LG', DeviceCategory.fan), isEmpty);
      expect(db.codeSets('lg', DeviceCategory.tv), isEmpty);
    });

    test('stores protocol codes canonically', () {
      final samsung = db.codeSets('Samsung', DeviceCategory.tv).single;
      final code = samsung.keys[Keys.power]! as ProtocolKeyCode;
      expect(code.protocol, 'NECx2');
      expect(code.params, {'D': 7, 'S': 7, 'F': 2});
      expect(samsung.label, 'BN59');
      final fan = db.codeSets('Acme', DeviceCategory.fan).single;
      final rc5 = fan.keys[Keys.speed]! as ProtocolKeyCode;
      expect(rc5.params, {'D': 3, 'F': 9});
      expect(fan.protocol, isNull);
    });

    test('round-trips raw signals, with and without repeat', () {
      final acme = db.codeSets('Acme', DeviceCategory.tv).single;
      expect((acme.keys[Keys.power]! as RawKeyCode).signal, _raw.signal);
      final fan = db.codeSets('Acme', DeviceCategory.fan).single;
      final s = (fan.keys[Keys.power]! as RawKeyCode).signal;
      expect(s.durationsUs, [1200, 400, 1200]);
      expect(s.repeat, isNull);
      expect(s.carrierHz, 36000);
    });

    test('finds code sets by id and by merged-duplicate alias', () {
      expect(db.codeSetById('tv-samsung')?.brand, 'Samsung');
      expect(db.codeSetById('tv-lg-dup')?.id, 'tv-lg-1');
      expect(db.codeSetById('nope'), isNull);
    });

    test('lists sources with their notices', () {
      final s = db.sources().single;
      expect(s.name, _fz.name);
      expect(s.notice, _fz.notice);
      expect(s.commit, _fz.commit);
    });

    test('opens read-only and leaves the file untouched', () {
      final before = File(path('codes.sqlite')).readAsBytesSync();
      db
        ..categories()
        ..codeSets('LG', DeviceCategory.tv)
        ..close();
      db = CodeDb.open(path('codes.sqlite'));
      expect(File(path('codes.sqlite')).readAsBytesSync(), before);
    });
  });

  group('determinism', () {
    test('the same content gives a byte-identical file and hash', () {
      final a = CodeDbWriter.write(_content(), path('a.sqlite'));
      final shuffled = [..._content().entries]..shuffle(Random(3));
      final b = CodeDbWriter.write(
        _content(entries: shuffled),
        path('b.sqlite'),
      );
      expect(b.contentHash, a.contentHash);
      expect(b.fileSha256, a.fileSha256);
      expect(
        File(path('b.sqlite')).readAsBytesSync(),
        File(path('a.sqlite')).readAsBytesSync(),
      );
    });

    test('any content change changes the hash', () {
      final a = CodeDbWriter.write(_content(), path('a.sqlite'));
      final entries = [..._content().entries]..removeLast();
      final b = CodeDbWriter.write(
        _content(entries: entries),
        path('b.sqlite'),
      );
      expect(b.contentHash, isNot(a.contentHash));
    });

    test('rewriting replaces the old file', () {
      CodeDbWriter.write(_content(), path('a.sqlite'));
      final again = CodeDbWriter.write(_content(), path('a.sqlite'));
      expect(CodeDb.open(path('a.sqlite')).contentHash, again.contentHash);
    });
  });

  group('integrity', () {
    late String file;
    late String hash;
    setUp(() {
      file = path('codes.sqlite');
      hash = CodeDbWriter.write(_content(), file).contentHash;
    });

    void tamper(String sql) {
      final rw = sqlite3.open(file);
      rw.execute(sql);
      rw.close();
    }

    test('a modified row fails verification with a typed error', () {
      tamper(
        "UPDATE key_code SET params = 'D=4,S=251,F=9' "
        'WHERE protocol IS NOT NULL AND ord = 0',
      );
      expect(
        () => CodeDb.open(file),
        throwsA(
          isA<CodeDbIntegrityException>()
              .having((e) => e.expected, 'expected', hash)
              .having((e) => e.actual, 'actual', isNot(hash)),
        ),
      );
      // The stored-hash-only mode trusts the rows.
      CodeDb.open(
        file,
        expectedContentHash: hash,
        verification: CodeDbVerification.storedHashOnly,
      ).close();
    });

    test('a different expected hash fails verification', () {
      expect(
        () => CodeDb.open(file, expectedContentHash: '0' * 64),
        throwsA(isA<CodeDbIntegrityException>()),
      );
    });

    test('a changed stored hash fails verification', () {
      tamper("UPDATE meta SET value = 'x' WHERE key = 'content_hash'");
      expect(() => CodeDb.open(file), throwsA(isA<CodeDbIntegrityException>()));
    });

    test('rejects missing files, non-databases and foreign databases', () {
      expect(
        () => CodeDb.open(path('missing.sqlite')),
        throwsA(isA<CodeDbOpenException>()),
      );
      File(path('junk.sqlite')).writeAsStringSync('not a database at all');
      expect(
        () => CodeDb.open(path('junk.sqlite')),
        throwsA(isA<CodeDbException>()),
      );
      final other = sqlite3.open(path('other.sqlite'))
        ..execute('CREATE TABLE t (a)');
      other.close();
      expect(
        () => CodeDb.open(path('other.sqlite')),
        throwsA(isA<CodeDbSchemaException>()),
      );
      tamper('PRAGMA user_version = 99');
      expect(() => CodeDb.open(file), throwsA(isA<CodeDbSchemaException>()));
    });
  });

  group('gate L1 and input validation', () {
    CodeDbContent withSet(CodeSet set, {CodeDbSource source = _fz}) =>
        CodeDbContent(sources: [source], entries: [CodeDbEntry(set)]);

    Provenance prov({
      String source = 'flipperdevices/irdb',
      String? url,
      String? commit,
      String? license,
      String importedAt = '2026-04-24',
    }) => Provenance(
      source: source,
      sourceUrl: url ?? _fz.url,
      sourceCommit: commit ?? _fz.commit,
      license: license ?? _fz.license,
      importedAt: importedAt,
    );

    final power = {Keys.power: _nec(1, 1)};

    test('an empty provenance field fails the build', () {
      for (final p in [
        prov(source: ''),
        prov(url: ''),
        prov(commit: ' '),
        prov(license: ''),
        prov(importedAt: ''),
      ]) {
        expect(
          () => CodeDbWriter.write(
            withSet(_set('x', 'B', DeviceCategory.tv, power, provenance: p)),
            path('l1.sqlite'),
          ),
          throwsA(isA<CodeDbProvenanceException>()),
        );
      }
      expect(File(path('l1.sqlite')).existsSync(), isFalse);
    });

    test('provenance must match a declared, complete source', () {
      expect(
        () => CodeDbWriter.validate(
          withSet(
            _set(
              'x',
              'B',
              DeviceCategory.tv,
              power,
              provenance: prov(commit: 'abc'),
            ),
          ),
        ),
        throwsA(isA<CodeDbProvenanceException>()),
      );
      expect(
        () => CodeDbWriter.validate(
          withSet(
            _set(
              'x',
              'B',
              DeviceCategory.tv,
              power,
              provenance: prov(source: 'other'),
            ),
          ),
        ),
        throwsA(isA<CodeDbProvenanceException>()),
      );
      const noNotice = CodeDbSource(
        name: 'flipperdevices/irdb',
        url: 'https://github.com/flipperdevices/irdb',
        commit: 'f7b15366521cc81ba11b341538f0097bddbb748b',
        license: 'MIT',
        importedAt: '2026-04-24',
        notice: '',
      );
      expect(
        () => CodeDbWriter.validate(
          withSet(_set('x', 'B', DeviceCategory.tv, power), source: noNotice),
        ),
        throwsA(isA<CodeDbProvenanceException>()),
      );
    });

    test('rejects invalid code sets', () {
      void bad(CodeDbContent c) => expect(
        () => CodeDbWriter.validate(c),
        throwsA(isA<CodeDbBuildException>()),
      );
      bad(withSet(_set('x', 'B', DeviceCategory.tv, {})));
      bad(withSet(_set('x', ' B', DeviceCategory.tv, power)));
      bad(withSet(_set('x', 'B', DeviceCategory.tv, {'BAD': _nec(1, 1)})));
      bad(
        withSet(
          _set('x', 'B', DeviceCategory.tv, {
            Keys.power: const ProtocolKeyCode('Nope', {'D': 1}),
          }),
        ),
      );
      bad(
        withSet(
          _set('x', 'B', DeviceCategory.tv, {
            Keys.power: const ProtocolKeyCode('NEC1', {'D': 300, 'F': 1}),
          }),
        ),
      );
      bad(
        withSet(
          _set('x', 'B', DeviceCategory.tv, {
            Keys.power: RawKeyCode(
              IrSignal(carrierHz: 38000, durationsUs: [1, 2]),
            ),
          }),
        ),
      );
      bad(
        CodeDbContent(
          sources: [_fz],
          entries: [
            CodeDbEntry(_set('x', 'B', DeviceCategory.tv, power)),
            CodeDbEntry(
              _set('y', 'B', DeviceCategory.tv, power),
              mergedIds: ['x'],
            ),
          ],
        ),
      );
      bad(
        CodeDbContent(
          sources: [_fz],
          entries: [CodeDbEntry(_set('x', 'B', DeviceCategory.tv, power))],
          meta: {'content_hash': 'x'},
        ),
      );
    });
  });

  group('encodings', () {
    test('varints round-trip and reject truncation', () {
      final values = [0, 1, 127, 128, 300, 9000, 65535, 150000, 0xFFFFFFFF];
      expect(decodeVarints(encodeVarints(values)), values);
      expect(encodeVarints([127, 128]), [127, 0x80, 1]);
      expect(
        () => decodeVarints(Uint8List.fromList([0x80])),
        throwsA(isA<CodeDbFormatException>()),
      );
      expect(
        () => decodeVarints(Uint8List.fromList(List.filled(6, 0xFF))),
        throwsA(isA<CodeDbFormatException>()),
      );
      expect(() => encodeVarints([-1]), throwsArgumentError);
    });

    test('params round-trip and reject garbage', () {
      expect(decodeParams(encodeParams({'D': 4, 'S': 251, 'F': 8})), {
        'D': 4,
        'S': 251,
        'F': 8,
      });
      expect(decodeParams(''), isEmpty);
      for (final bad in ['D', 'D=', '=4', 'D=x', '1=2', 'D=4,,F=1']) {
        expect(
          () => decodeParams(bad),
          throwsA(isA<CodeDbFormatException>()),
          reason: bad,
        );
      }
    });

    test('brand search keys and key order', () {
      expect(brandSearchKey('Tata Play'), 'tataplay');
      expect(brandSearchKey('d2h'), 'd2h');
      expect(brandSearchKey('Blue-Star (India)'), 'bluestarindia');
      final keys = ['custom:b', Keys.volUp, 'custom:a', Keys.power];
      expect(keys..sort(compareKeys), [
        Keys.power,
        Keys.volUp,
        'custom:a',
        'custom:b',
      ]);
    });

    test('manifest round-trips', () {
      final m = CodeDbManifest(
        schemaVersion: 1,
        file: 'codes.sqlite',
        contentSha256: 'a' * 64,
        fileSha256: 'b' * 64,
        fileBytes: 10,
        sources: const [
          ManifestSource(
            name: 'n',
            url: 'u',
            commit: 'c',
            license: 'MIT',
            importedAt: '2026-04-24',
          ),
        ],
        counts: {'codeSets': 3},
      );
      final back = CodeDbManifest.parse(m.encode());
      expect(back.toJson(), m.toJson());
      expect(
        () => CodeDbManifest.parse('[]'),
        throwsA(isA<CodeDbFormatException>()),
      );
      expect(
        () => CodeDbManifest.parse('{'),
        throwsA(isA<CodeDbFormatException>()),
      );
    });
  });
}

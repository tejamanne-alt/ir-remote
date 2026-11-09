import 'dart:convert';
import 'dart:io';

import 'package:code_db/code_db.dart';
import 'package:crypto/crypto.dart';
import 'package:db_build/db_build.dart';
import 'package:ir_core/ir_core.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'fixtures.dart';

void main() {
  late Directory tmp;
  late Map<String, String> trees;
  late String thirdParty;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('db_build_test_');
    final fz = p.join(tmp.path, 'flipper');
    final ir = p.join(tmp.path, 'irdb');
    writeFlipperTree(fz);
    writeIrdbTree(ir);
    trees = {flipperIrdb.name: fz, probonopdIrdb.name: ir};
    thirdParty = p.join(tmp.path, 'THIRD_PARTY.md');
    File(thirdParty).writeAsStringSync(
      '# Third party\n\n'
      'irdb announcement issue: https://github.com/probonopd/irdb/issues/<n>\n',
    );
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  String out(String name) => p.join(tmp.path, name);

  int cli(List<String> args, {SourceResolver? resolver, StringBuffer? err}) =>
      runCli(
        [...args, '--third-party', thirdParty],
        resolver: resolver ?? fakeResolver(trees),
        out: StringBuffer(),
        err: err ?? StringBuffer(),
      );

  Map<String, Object?> report(String dir) =>
      jsonDecode(File(p.join(dir, 'codes.report.json')).readAsStringSync())
          as Map<String, Object?>;

  group('build', () {
    test('imports, deduplicates, ranks and writes a verified database', () {
      expect(cli(['--out', out('a')]), exitOk);
      final dir = out('a');
      final manifest = CodeDbManifest.parse(
        File(p.join(dir, 'codes.manifest.json')).readAsStringSync(),
      );
      final sidecar = File(p.join(dir, 'codes.sqlite.sha256'))
          .readAsStringSync();
      expect(sidecar, '${manifest.contentSha256}\n');
      final db = CodeDb.open(
        p.join(dir, 'codes.sqlite'),
        expectedContentHash: manifest.contentSha256,
      );
      addTearDown(db.close);

      // Without --include-irdb only Flipper data is present.
      expect(db.sources().map((s) => s.name), ['flipperdevices/irdb']);
      expect(db.sources().single.notice, startsWith('MIT License'));
      expect(db.totals().codeSets, 6);
      expect(db.totals().mergedDuplicates, 3);

      // "SAMSUNG" and "Samsung" are one brand; three files are one set.
      final samsung = db.codeSets('Samsung', DeviceCategory.tv).single;
      expect(samsung.keys.keys, [Keys.power, Keys.input, Keys.volUp]);
      final power = samsung.keys[Keys.power]! as ProtocolKeyCode;
      expect('${power.protocol} ${power.params}', 'NECx2 {D: 7, S: 7, F: 2}');
      expect(samsung.provenance.importedAt, '2026-04-24');
      expect(samsung.provenance.sourceCommit, flipperIrdb.commit);
      expect(samsung.provenance.license, 'MIT');
      expect(samsung.provenance.path, startsWith('database/categories/TVs/'));
      expect(
        db
            .codeSetById(
              stableId(
                'fz',
                flipperIrdb.name,
                'database/categories/TVs/Samsung/Samsung_B/Samsung_B.ir',
              ),
            )
            ?.id,
        samsung.id,
      );

      // LG: the 20%-off raw subset merged; ranking puts power and
      // popularity first.
      final lg = db.codeSets('LG', DeviceCategory.tv);
      expect(lg.map((s) => s.label), ['LG_1', 'LG_4', 'LG_3']);
      expect(lg.first.keys.keys, [Keys.power, Keys.mute, 'custom:Mute']);
      expect(lg.first.keys[Keys.mute], isA<RawKeyCode>());

      // Ranked brands first, then alphabetical; Tata Sky reads Tata Play.
      expect(db.brands(DeviceCategory.tv).map((b) => b.name), [
        'Samsung',
        'LG',
      ]);
      final stb = db.codeSets('Tata Play', DeviceCategory.setTopBox).single;
      expect((stb.keys[Keys.power]! as ProtocolKeyCode).params, {
        'D': 0x80,
        'S': 0x7F,
        'F': 0x0A,
      });
      expect((stb.keys[Keys.guide]! as ProtocolKeyCode).params, {
        'D': 31,
        'F': 65,
      });
      // The Flipper config.json alias maps "Wind" to SPEED.
      final fan = db.codeSets('Acme', DeviceCategory.fan).single;
      expect(fan.keys.keys, [Keys.power, Keys.speed]);
      expect((fan.keys[Keys.power]! as RawKeyCode).signal.durationsUs, [
        1200,
        400,
        1200,
      ]);
      expect(db.categories().map((c) => c.category), [
        DeviceCategory.tv,
        DeviceCategory.setTopBox,
        DeviceCategory.fan,
      ]);

      final r = report(dir);
      final fz = (r['sources']! as Map)['flipperdevices/irdb'] as Map;
      expect(fz['files'], {
        'seen': 13,
        'imported': 9,
        'excluded': {
          'categoryNotInV1:DVD': 1,
          'formatError': 1,
          'noImportableSignals': 1,
          'unexpectedPath': 1,
        },
      });
      final signals = fz['signals'] as Map;
      expect(signals['skipped'], {
        'duplicateKeySameCode': 1,
        'unsupportedProtocol:NEC42': 1,
        'unsupportedProtocol:RCA': 1,
      });
      expect((fz['keys'] as Map)['viaSourceAlias'], 1);
      expect(
        (r['excludedSources']! as Map).keys,
        containsAll(['UberGuidoZ/Flipper-IRDB', 'probonopd/irdb']),
      );
      final sets = r['codeSets']! as Map;
      expect(sets['beforeDedupe'], 9);
      expect(sets['duplicatesMerged'], 3);
      expect(sets['afterDedupe'], 6);
      final database = r['database']! as Map;
      expect(database['contentSha256'], manifest.contentSha256);
      expect(database['gzipBytes'], lessThan(database['bytes']! as int));
    });

    test('two builds from the same inputs produce the same hash and bytes', () {
      expect(cli(['--out', out('a')]), exitOk);
      expect(cli(['--out', out('b')]), exitOk);
      String read(String d, String f) => File(p.join(d, f)).readAsStringSync();
      expect(
        read(out('b'), 'codes.sqlite.sha256'),
        read(out('a'), 'codes.sqlite.sha256'),
      );
      expect(
        File(p.join(out('b'), 'codes.sqlite')).readAsBytesSync(),
        File(p.join(out('a'), 'codes.sqlite')).readAsBytesSync(),
      );
      for (final f in ['codes.manifest.json', 'codes.report.json']) {
        expect(read(out('b'), f), read(out('a'), f), reason: f);
      }
      // A fixed --imported-at changes provenance and therefore the hash.
      expect(cli(['--out', out('c'), '--imported-at', '2026-11-09']), exitOk);
      expect(
        read(out('c'), 'codes.sqlite.sha256'),
        isNot(read(out('a'), 'codes.sqlite.sha256')),
      );
    });

    test('gate L1: an empty provenance field fails the build', () {
      for (final patch in [
        (SourceSpec s) => copySpec(s, licenseId: ''),
        (SourceSpec s) => copySpec(s, commit: ''),
      ]) {
        final err = StringBuffer();
        final code = cli(
          ['--out', out('l1')],
          resolver: fakeResolver(trees, patch: patch),
          err: err,
        );
        expect(code, isNot(exitOk));
        expect(err.toString(), contains('gate L1'));
        expect(File(p.join(out('l1'), 'codes.sqlite')).existsSync(), isFalse);
      }
    });

    test('gate L4: irdb needs --include-irdb and a recorded issue', () {
      final err = StringBuffer();
      expect(cli(['--out', out('x'), '--include-irdb'], err: err), exitFailed);
      expect(err.toString(), contains('gate L4'));
      expect(Directory(out('x')).existsSync(), isFalse);

      File(thirdParty).writeAsStringSync(
        'irdb announcement issue: https://github.com/probonopd/irdb/issues/42\n',
      );
      // The issue alone does not include irdb.
      expect(cli(['--out', out('without')]), exitOk);
      expect(report(out('without'))['sources'], hasLength(1));

      expect(cli(['--out', out('with'), '--include-irdb']), exitOk);
      final db = CodeDb.open(p.join(out('with'), 'codes.sqlite'));
      addTearDown(db.close);
      expect(db.sources().map((s) => s.name), [
        'flipperdevices/irdb',
        'probonopd/irdb',
      ]);
      final irdb = db.sources().last;
      expect(irdb.notice, startsWith('Contains/accesses irdb by Simon Peter'));
      expect(irdb.license, 'LicenseRef-irdb');
      expect(
        db.meta['irdb_announcement_issue'],
        'https://github.com/probonopd/irdb/issues/42',
      );
      // The irdb Samsung power code duplicates Flipper's and is merged into
      // the Flipper set (preferred source); ONIDA comes from irdb only.
      final samsung = db.codeSets('Samsung', DeviceCategory.tv).single;
      expect(samsung.provenance.source, 'flipperdevices/irdb');
      expect(
        db
            .codeSetById(
              stableId('irdb', probonopdIrdb.name, 'codes/Samsung/TV/7,7.csv'),
            )
            ?.id,
        samsung.id,
      );
      final onida = db.codeSets('ONIDA', DeviceCategory.tv).single;
      expect(onida.provenance.source, 'probonopd/irdb');
      expect(onida.provenance.importedAt, '2026-01-14');
      expect(onida.label, 'TV 0,-1');
      expect(db.brands(DeviceCategory.tv).map((b) => b.name), [
        'Samsung',
        'LG',
        'ONIDA',
      ]);
      final r = report(out('with'));
      final ir = (r['sources']! as Map)['probonopd/irdb'] as Map;
      expect((ir['files'] as Map)['excluded'], {'deviceTypeNotInV1': 1});
      expect((ir['signals'] as Map)['skipped'], {
        'unsupportedProtocol:Pioneer': 1,
      });
    });

    test('rejects bad arguments', () {
      expect(cli([]), exitUsage);
      expect(cli(['--out', out('a'), 'extra']), exitUsage);
      expect(cli(['--nope']), exitUsage);
      expect(cli(['--out', out('a'), '--imported-at', 'yesterday']), exitUsage);
      expect(cli(['--help']), exitOk);
    });

    test('a source failure is a failed build', () {
      final err = StringBuffer();
      final code = cli(
        ['--out', out('a')],
        resolver: (s) => throw const SourceException('licence changed'),
        err: err,
      );
      expect(code, exitFailed);
      expect(err.toString(), contains('licence changed'));
    });
  });

  group('gate L4 line', () {
    String? parse(String text) {
      final f = File(out('tp.md'))..writeAsStringSync(text);
      return irdbAnnouncementIssue(f.path);
    }

    test('accepts only a numbered probonopd/irdb issue URL', () {
      expect(
        parse(
          'irdb announcement issue: https://github.com/probonopd/irdb/issues/7',
        ),
        'https://github.com/probonopd/irdb/issues/7',
      );
      expect(
        parse(
          '- IRDB Announcement Issue:  https://github.com/probonopd/irdb/issues/123 (opened)',
        ),
        'https://github.com/probonopd/irdb/issues/123',
      );
      expect(
        parse(
          'irdb announcement issue: https://github.com/probonopd/irdb/issues/<n>',
        ),
        isNull,
      );
      expect(
        parse(
          'irdb announcement issue: https://github.com/someone/irdb/issues/7',
        ),
        isNull,
      );
      expect(
        parse(
          'irdb announcement issue: https://github.com/probonopd/irdb/issues/7/x',
        ),
        isNull,
      );
      expect(parse(''), isNull);
      expect(irdbAnnouncementIssue(out('missing.md')), isNull);
    });
  });

  group('licences', () {
    test('MIT is recognized and edits are not', () {
      expect(isMitLicense(mitText), isTrue);
      expect(isMitLicense(mitText.replaceAll('sublicense, ', '')), isFalse);
      expect(isMitLicense('GNU GENERAL PUBLIC LICENSE Version 3'), isFalse);
    });

    test('the irdb notice is extracted verbatim, whitespace normalized', () {
      expect(
        irdbNotice(irdbLicenseExcerpt),
        'Contains/accesses irdb by Simon Peter and contributors, used under '
        'permission. For licensing details and for information on how to '
        'contribute to the database, see https://github.com/probonopd/irdb',
      );
      expect(irdbNotice('MIT License'), isNull);
    });

    test('the pinned flipperdevices/irdb licence verifies as MIT', () {
      // The fixture is byte-identical to LICENSE at the pinned commit.
      expect(_sha(mitText), flipperIrdb.licenseSha256);
      expect(verifyLicense(flipperIrdb, utf8.encode(mitText)), mitText.trim());
    });

    test('a licence that differs from the reviewed text stops the build', () {
      expect(
        () => verifyLicense(flipperIrdb, utf8.encode('$mitText ')),
        throwsA(isA<SourceException>()),
      );
      expect(
        () => verifyLicense(probonopdIrdb, utf8.encode(irdbLicenseExcerpt)),
        throwsA(isA<SourceException>()),
      );
      // Reviewed hash but not MIT: still refused.
      const gpl = 'GNU GENERAL PUBLIC LICENSE';
      expect(
        () => verifyLicense(
          copySpec(flipperIrdb, licenseSha256: _sha(gpl)),
          utf8.encode(gpl),
        ),
        throwsA(isA<SourceException>()),
      );
      // Reviewed hash, irdb kind, conditions missing: refused.
      expect(
        () => verifyLicense(
          copySpec(probonopdIrdb, licenseSha256: _sha(mitText)),
          utf8.encode(mitText),
        ),
        throwsA(isA<SourceException>()),
      );
      expect(
        verifyLicense(
          copySpec(probonopdIrdb, licenseSha256: _sha(irdbLicenseExcerpt)),
          utf8.encode(irdbLicenseExcerpt),
        ),
        startsWith('Contains/accesses irdb'),
      );
    });
  });

  group('dedupe and ranking', () {
    Candidate cand(
      String id,
      Map<String, KeyCode> keys, {
      SourceSpec source = flipperIrdb,
    }) => Candidate(
      id: id,
      rawBrand: 'B',
      category: DeviceCategory.tv,
      label: id,
      keys: keys,
      provenance: Provenance(
        source: source.name,
        sourceUrl: source.url,
        sourceCommit: source.commit,
        license: source.licenseId,
        importedAt: '2026-04-24',
        path: id,
      ),
      source: source,
    )..brand = 'B';

    const nec = ProtocolKeyCode('NEC1', {'D': 4, 'S': 251, 'F': 8});

    test('a raw capture of a protocol code is equivalent within 25%', () {
      final eq = SignalEquivalence();
      final rendered = nec.toSignal(ProtocolRegistry.standard);
      RawKeyCode raw(double f, {int hz = 38000}) => RawKeyCode(
        IrSignal(
          carrierHz: hz,
          durationsUs: [for (final d in rendered.durationsUs) (d * f).round()],
        ),
      );
      expect(eq.equivalent(nec, raw(1.0)), isTrue);
      expect(eq.equivalent(raw(0.85), nec), isTrue);
      expect(eq.equivalent(nec, raw(1.3)), isFalse);
      expect(eq.equivalent(nec, raw(1.0, hz: 30000)), isFalse);
      expect(
        eq.equivalent(
          nec,
          const ProtocolKeyCode('NEC2', {'D': 4, 'S': 251, 'F': 8}),
        ),
        isFalse,
      );
    });

    test('exact duplicates keep the preferred source; subsets merge', () {
      final a = cand('a', {Keys.power: nec}, source: probonopdIrdb);
      final b = cand('b', {Keys.power: nec});
      final c = cand('c', {
        Keys.power: nec,
        Keys.mute: const ProtocolKeyCode('NEC1', {'D': 4, 'S': 251, 'F': 9}),
      });
      final d = cand('d', {'custom:x': nec});
      final kept = deduplicate([a, b, c, d]);
      expect(kept.map((k) => k.id), ['c', 'd']);
      expect(kept.first.merged.map((m) => m.id), ['b', 'a']);
      expect(kept.first.weight, 3);
    });

    test(
      'ranking: power, then popularity, core keys, mapped keys, protocol',
      () {
        final noPower = cand('a', {Keys.mute: nec});
        final popular = cand('b', {Keys.power: nec})
          ..merged.add(cand('b2', {Keys.power: nec}));
        final full = cand('c', {Keys.power: nec, Keys.volUp: nec});
        final raw = cand('d', {
          Keys.power: RawKeyCode(IrSignal(carrierHz: 38000, durationsUs: [1])),
          Keys.volUp: nec,
        });
        final custom = cand('e', {Keys.power: nec, 'custom:x': nec});
        final ranks = rankWithinBrand([noPower, raw, custom, full, popular]);
        expect(
          (ranks.entries.toList()..sort((x, y) => x.value.compareTo(y.value)))
              .map((e) => e.key),
          ['b', 'c', 'd', 'e', 'a'],
        );
      },
    );
  });

  group('brands', () {
    test('canonicalizes spellings and ranked names', () {
      final c = BrandCanonicalizer();
      for (final b in [
        'SAMSUNG',
        'Tata_Sky',
        'Curtis_Mathis',
        'CurtisMathis',
        'CurtisMathis',
        'blue_star',
      ]) {
        c.add(b);
      }
      expect(c.canonical('SAMSUNG'), 'Samsung');
      expect(c.canonical('Tata_Sky'), 'Tata Play');
      expect(c.canonical('Curtis_Mathis'), 'CurtisMathis');
      expect(c.canonical('blue_star'), 'Blue Star');
      expect(primaryBrands[DeviceCategory.tv], tvBrandsV1);
      expect(tvBrandsV1.first, 'Samsung');
      expect(stbV1, hasLength(5));
      expect(acBrandsV1, hasLength(8));
    });
  });
}

String _sha(String text) => sha256.convert(utf8.encode(text)).toString();

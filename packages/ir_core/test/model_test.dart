import 'dart:convert';

import 'package:ir_core/ir_core.dart';
import 'package:test/test.dart';

const _prov = Provenance(
  source: 'test',
  sourceUrl: 'https://example.invalid/test',
  sourceCommit: 'abc123',
  license: 'MIT',
  importedAt: '2026-11-09',
);

void main() {
  group('Keys', () {
    test('normalizes common source names', () {
      expect(Keys.normalize('Power'), Keys.power);
      expect(Keys.normalize('POWER'), Keys.power);
      expect(Keys.normalize('Vol_up'), Keys.volUp);
      expect(Keys.normalize('vol+'), Keys.volUp);
      expect(Keys.normalize('Ch_prev'), Keys.chDown);
      expect(Keys.normalize('Source'), Keys.input);
      expect(Keys.normalize('5'), Keys.digit5);
      expect(Keys.normalize('Enter'), Keys.ok);
      expect(Keys.normalize('Power Off'), Keys.powerOff);
    });

    test('keeps unmapped names as custom keys', () {
      expect(Keys.normalize('Netflix'), 'custom:Netflix');
      expect(Keys.isValid('custom:Netflix'), isTrue);
      expect(Keys.isValid('custom:'), isFalse);
      expect(Keys.isValid('NOT_A_KEY'), isFalse);
      expect(Keys.isValid(Keys.mute), isTrue);
      expect(Keys.digits.length, 10);
    });
  });

  group('CodeSet', () {
    final set = CodeSet(
      id: 'tv-1',
      brand: 'Brand',
      category: DeviceCategory.tv,
      provenance: _prov,
      keys: {
        Keys.power: const ProtocolKeyCode('NEC1', {'D': 4, 'F': 8}),
        Keys.volUp: const ProtocolKeyCode('NEC1', {'D': 4, 'F': 2}),
      },
    );

    test('resolves keys through the codec registry', () {
      expect(
        resolveKey(set, Keys.power),
        const Nec1().encode({'D': 4, 'F': 8}),
      );
      expect(set.protocol, 'NEC1');
      expect(set.powerTestKey, Keys.power);
    });

    test('reports missing keys and bad parameters as resolution errors', () {
      expect(
        () => resolveKey(set, Keys.mute),
        throwsA(isA<CommandResolutionException>()),
      );
      final broken = CodeSet(
        id: 'b',
        brand: 'B',
        category: DeviceCategory.tv,
        provenance: _prov,
        keys: {
          'A': const ProtocolKeyCode('NEC1', {'D': 999, 'F': 1}),
          'B': const ProtocolKeyCode('Nope', {'D': 1}),
        },
      );
      expect(
        () => resolveKey(broken, 'A'),
        throwsA(isA<CommandResolutionException>()),
      );
      expect(
        () => resolveKey(broken, 'B'),
        throwsA(
          isA<CommandResolutionException>().having(
            (e) => e.toString(),
            'message',
            contains('unknown protocol'),
          ),
        ),
      );
      expect(broken.protocol, isNull);
    });

    test('key codes round-trip through JSON', () {
      final raw = RawKeyCode(
        IrSignal(carrierHz: 38000, durationsUs: [1, 2, 3]),
      );
      for (final k in [set.keys[Keys.power]!, raw]) {
        final back = KeyCode.fromJson(jsonDecode(jsonEncode(k.toJson())));
        expect(
          back.toSignal(ProtocolRegistry.standard),
          k.toSignal(ProtocolRegistry.standard),
        );
      }
      for (final bad in [
        null,
        <String, Object?>{},
        {'protocol': 'NEC1', 'params': 3},
        {
          'protocol': 'NEC1',
          'params': {'D': 'x'},
        },
      ]) {
        expect(() => KeyCode.fromJson(bad), throwsFormatException);
      }
    });

    test('provenance requires every gate L1 field', () {
      expect(Provenance.fromJson(_prov.toJson()).toJson(), _prov.toJson());
      for (final field in [
        'source',
        'sourceUrl',
        'sourceCommit',
        'license',
        'importedAt',
      ]) {
        final m = _prov.toJson()..remove(field);
        expect(
          () => Provenance.fromJson(m),
          throwsFormatException,
          reason: field,
        );
        expect(
          () => Provenance.fromJson({..._prov.toJson(), field: ''}),
          throwsFormatException,
        );
      }
      expect(() => Provenance.fromJson('x'), throwsFormatException);
      expect(
        Provenance.fromJson({..._prov.toJson(), 'path': 'a/b.ir'}).path,
        'a/b.ir',
      );
    });

    test('categories parse by name', () {
      expect(DeviceCategory.parse('tv'), DeviceCategory.tv);
      expect(() => DeviceCategory.parse('toaster'), throwsFormatException);
    });

    test('commands carry their code set', () {
      const k = KeyCommand('tv-1', Keys.power);
      const a = AcCommand('ac-1', AcState.matchingProbe);
      expect(k.codeSetId, 'tv-1');
      expect(a.state.targetTempC, 24);
      expect(set.label, isNull);
      expect(set.rank, 0);
    });
  });

  group('AcState', () {
    const caps = AcCapabilities(
      version: 1,
      modes: {AcMode.cool, AcMode.dry, AcMode.fan},
      minTempC: 16,
      maxTempC: 30,
      tempStepC: 1,
      fanLevels: 3,
      fanAuto: false,
      power: PowerControl.discrete,
      features: {
        AcFeature.swingV: FeatureControl.state,
        AcFeature.light: FeatureControl.toggle,
      },
    );

    test('JSON round-trips and equality ignores feature order', () {
      final s = AcState.matchingProbe
          .withFeature(AcFeature.turbo, on: true)
          .withFeature(AcFeature.swingV, on: true);
      final back = AcState.fromJson(jsonDecode(jsonEncode(s.toJson())));
      expect(back, s);
      expect(back.hashCode, s.hashCode);
      expect(back.has(AcFeature.turbo), isTrue);
      expect(
        s.withFeature(AcFeature.turbo, on: false).has(AcFeature.turbo),
        isFalse,
      );
      expect(s.toString(), contains('cool'));
    });

    test('fromJson rejects malformed states', () {
      for (final bad in [
        null,
        {'power': 'yes', 'mode': 'cool', 'targetTempC': 24},
        {'power': true, 'mode': 'warm', 'targetTempC': 24},
        {
          'power': true,
          'mode': 'cool',
          'targetTempC': 24,
          'features': ['laser'],
        },
      ]) {
        expect(() => AcState.fromJson(bad), throwsFormatException);
      }
    });

    test('clamp keeps only what the capability declares', () {
      const s = AcState(
        power: true,
        mode: AcMode.heat,
        targetTempC: 33.4,
        fan: 0,
        features: {AcFeature.swingV, AcFeature.light, AcFeature.eco},
      );
      final c = caps.clamp(s);
      expect(c.mode, AcMode.cool);
      expect(c.targetTempC, 30);
      expect(c.fan, 1);
      expect(c.features, {AcFeature.swingV});
      expect(caps.clamp(s.copyWith(targetTempC: 20.6)).targetTempC, 21);
      expect(caps.clamp(s.copyWith(fan: 9)).fan, 3);
    });

    test('toggles describe events', () {
      const AcToggle t = FeatureToggle(AcFeature.light);
      expect((t as FeatureToggle).feature, AcFeature.light);
      expect(const PowerToggle(), isA<AcToggle>());
    });
  });
}

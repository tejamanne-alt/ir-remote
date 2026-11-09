// Property tests: encode-then-decode round trips for random parameters, with
// and without timing jitter, plus negative cases for every decoder.
import 'dart:math';

import 'package:ir_core/ir_core.dart';
import 'package:test/test.dart';

void main() {
  const iterations = 300;

  for (final protocol in builtInProtocols) {
    group(protocol.id, () {
      test('round-trips random parameters exactly', () {
        final rng = Random(protocol.id.hashCode);
        for (var i = 0; i < iterations; i++) {
          final params = _randomParams(protocol, rng);
          final signal = protocol.encode(params);
          final decoded = protocol.decode(signal.durationsUs);
          expect(decoded, isNotNull, reason: 'params $params');
          expect(decoded!.params, protocol.normalize(params));
        }
      });

      test('round-trips with ±15% jitter on every duration', () {
        final rng = Random(protocol.id.hashCode ^ 0x5eed);
        for (var i = 0; i < iterations; i++) {
          final params = _randomParams(protocol, rng);
          final signal = protocol.encode(params);
          final noisy = [
            for (final d in signal.durationsUs)
              max(1, (d * (0.85 + rng.nextDouble() * 0.3)).round()),
          ];
          final decoded = protocol.decode(noisy);
          expect(decoded, isNotNull, reason: 'params $params noisy $noisy');
          expect(decoded!.params, protocol.normalize(params));
        }
      });

      test('rejects timings stretched by 60%', () {
        final rng = Random(protocol.id.hashCode ^ 0xbad);
        final params = _randomParams(protocol, rng);
        final signal = protocol.encode(params);
        final stretched = [
          for (final d in signal.durationsUs) (d * 1.6).round(),
        ];
        expect(protocol.decode(stretched), isNull);
      });

      test('rejects truncated frames', () {
        final rng = Random(protocol.id.hashCode ^ 0x7);
        for (var i = 0; i < 50; i++) {
          final signal = protocol.encode(_randomParams(protocol, rng));
          final cut = 1 + rng.nextInt(signal.durationsUs.length - 2);
          final truncated = signal.durationsUs.sublist(0, cut);
          final decoded = protocol.decode(truncated);
          if (decoded != null) {
            // Only a protocol repeat frame may legitimately be a prefix.
            expect(
              decoded.isRepeatFrame,
              isTrue,
              reason: 'decoded ${decoded.params} from $cut durations',
            );
          }
        }
      });

      test('never throws on random input', () {
        final rng = Random(protocol.id.hashCode ^ 0xf022);
        for (var i = 0; i < 500; i++) {
          final n = rng.nextInt(120);
          final input = [for (var k = 0; k < n; k++) 1 + rng.nextInt(12000)];
          protocol.decode(input); // must not throw
        }
        expect(protocol.decode(const []), isNull);
      });

      test('normalize rejects unknown and out-of-range parameters', () {
        expect(
          () => protocol.normalize({'Z': 1}),
          throwsA(isA<ProtocolParamException>()),
        );
        final p = protocol.params.first;
        expect(
          () => protocol.normalize({
            ..._randomParams(protocol, Random(1)),
            p.name: p.max + 1,
          }),
          throwsA(isA<ProtocolParamException>()),
        );
        final required = protocol.params.where((p) => !p.hasDefault);
        if (required.isNotEmpty) {
          expect(
            () => protocol.normalize({}),
            throwsA(isA<ProtocolParamException>()),
          );
        }
      });

      test('signals pass validation for a 2 s, wide-carrier transport', () {
        const caps = TransportCapabilities(
          carrierRangesHz: [CarrierRange(30000, 60000)],
          maxPatternUs: 2000000,
          canLearn: false,
          latencyClass: LatencyClass.local,
        );
        final signal = protocol.encode(_randomParams(protocol, Random(3)));
        expect(const SignalValidator().validate(signal, caps), isEmpty);
      });
    });
  }

  group('defaults', () {
    test('subdevice defaults to 255-D for NEC and NECx (IrpProtocols)', () {
      expect(const Nec1().normalize({'D': 4, 'F': 8})['S'], 251);
      expect(const NecX2().normalize({'D': 7, 'F': 2})['S'], 248);
      expect(const NecX2().normalize({'D': 7, 'S': 7, 'F': 2})['S'], 7);
    });

    test('NECx1 repeat carries the complement of device bit 0', () {
      final odd = const NecX1().encode({'D': 7, 'S': 7, 'F': 2});
      final even = const NecX1().encode({'D': 6, 'S': 6, 'F': 2});
      // ~D:1 is 0 for odd D (short space) and 1 for even D (long space).
      expect(odd.repeat!.frameUs[3], 564);
      expect(even.repeat!.frameUs[3], 1692);
    });

    test('toggle defaults to 0 and the toggle bit changes the frame', () {
      for (final p in [const Rc5(), const Rc6()]) {
        expect(p.normalize({'D': 1, 'F': 2})['T'], 0);
        final a = p.encode({'D': 1, 'F': 2, 'T': 0});
        final b = p.encode({'D': 1, 'F': 2, 'T': 1});
        expect(a.durationsUs, isNot(equals(b.durationsUs)));
        expect(p.decode(b.durationsUs)!.params['T'], 1);
      }
    });

    test('Sony sends three frames per tap', () {
      final s = SonySirc.sony12.encode({'D': 1, 'F': 21});
      expect(s.minRepeats, 2);
      expect(s.frames().length, 3);
    });

    test('LG checksum is the low nibble of the command nibble sum', () {
      expect(Lg28.checksum(0x7776), (7 + 7 + 7 + 6) & 0xF);
      expect(Lg28.checksum(0), 0);
    });
  });

  group('discrimination', () {
    test('Sony variants are told apart by length', () {
      final s15 = SonySirc.sony15.encode({'D': 0x1A, 'F': 0x2A});
      expect(SonySirc.sony12.decode(s15.durationsUs), isNull);
      expect(SonySirc.sony20.decode(s15.durationsUs), isNull);
      expect(
        ProtocolRegistry.standard.identify(s15.durationsUs)!.protocolId,
        'Sony15',
      );
    });

    test('Sharp and Denon are told apart by check bits', () {
      final sharp = SharpFamily.sharp.encode({'D': 1, 'F': 22});
      expect(SharpFamily.denon.decode(sharp.durationsUs), isNull);
      final denon = SharpFamily.denon.encode({'D': 1, 'F': 22});
      expect(SharpFamily.sharp.decode(denon.durationsUs), isNull);
    });

    test('NEC1 frame with a non-inverted check byte is NEC1-f16', () {
      final f16 = const Nec1F16().encode({'D': 4, 'S': 251, 'F': 0x1234});
      expect(const Nec1().decode(f16.durationsUs), isNull);
      expect(
        ProtocolRegistry.standard.identify(f16.durationsUs)!.protocolId,
        'NEC1-f16',
      );
    });

    test('NEC ditto is identified as a repeat frame', () {
      final s = const Nec1().encode({'D': 4, 'F': 8});
      final r = ProtocolRegistry.standard.identify(s.repeat!.frameUs);
      expect(r!.isRepeatFrame, isTrue);
      expect(r.protocolId, 'NEC1');
    });

    test(
      'a JVC repeat (no header) decodes as a repeat with the same command',
      () {
        final s = const Jvc().encode({'D': 3, 'F': 23});
        final r = const Jvc().decode(s.repeat!.frameUs)!;
        expect(r.isRepeatFrame, isTrue);
        expect(r.params, {'D': 3, 'F': 23});
      },
    );

    test('identify returns null for noise', () {
      expect(ProtocolRegistry.standard.identify([100, 100, 100]), isNull);
    });
  });

  group('registry', () {
    test('looks up aliases case-insensitively', () {
      expect(ProtocolRegistry.standard.lookup('samsung32')!.id, 'NECx2');
      expect(ProtocolRegistry.standard.lookup('NEC')!.id, 'NEC1');
      // Different protocols, never aliases: NEC42 (42-bit) and RC5x (RC5
      // with an extra 6-bit field).
      expect(ProtocolRegistry.standard.lookup('NEC42'), isNull);
      expect(ProtocolRegistry.standard.lookup('RC5x'), isNull);
      expect(ProtocolRegistry.standard.lookup('sirc')!.id, 'Sony12');
      expect(ProtocolRegistry.standard.lookup('rc-5')!.id, 'RC5');
      expect(ProtocolRegistry.standard.lookup('nope'), isNull);
      expect(
        () => ProtocolRegistry.standard.require('nope'),
        throwsA(isA<UnknownProtocolException>()),
      );
    });

    test('rejects duplicate names', () {
      expect(
        () => ProtocolRegistry([const Nec1(), const Nec1()]),
        throwsStateError,
      );
    });
  });

  group('ToggleTracker', () {
    test('flips per press and holds for repeats, per device', () {
      final t = ToggleTracker();
      const rc5 = Rc5();
      final p = {'D': 0, 'F': 12};
      expect(t.forNewPress('tv', rc5, p)['T'], 0);
      expect(t.forRepeat('tv', rc5, p)['T'], 0);
      expect(t.forNewPress('tv', rc5, p)['T'], 1);
      expect(t.forRepeat('tv', rc5, p)['T'], 1);
      expect(t.forNewPress('other', rc5, p)['T'], 0);
      expect(t.forNewPress('tv', const Nec1(), p), same(p));
      t.reset();
      expect(t.forRepeat('tv', rc5, p)['T'], 0);
    });
  });
}

Map<String, int> _randomParams(IrProtocol protocol, Random rng) => {
  for (final p in protocol.params)
    p.name: p.bits >= 31 ? rng.nextInt(1 << 30) : rng.nextInt(p.max + 1),
};

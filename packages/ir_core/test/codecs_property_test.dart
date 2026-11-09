// Property tests: encode-then-decode round trips for random parameters, with
// and without timing jitter, plus negative cases for every decoder.
import 'dart:math';

import 'package:ir_core/ir_core.dart';
import 'package:ir_core/src/codecs/timing.dart';
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

      test('round-trips with ±24% jitter on every duration', () {
        // Just inside the default ±25% tolerance. For RC6 the 2t and 3t
        // windows overlap here, so this also covers ambiguous durations.
        final rng = Random(protocol.id.hashCode ^ 0x24);
        for (var i = 0; i < iterations; i++) {
          final params = _randomParams(protocol, rng);
          final signal = protocol.encode(params);
          final noisy = _jitter(signal.durationsUs, 0.24, rng);
          final decoded = protocol.decode(noisy);
          expect(decoded, isNotNull, reason: 'params $params noisy $noisy');
          expect(decoded!.params, protocol.normalize(params));
        }
      });

      test('decodes a jittered frame followed by its gaps and repeats', () {
        final rng = Random(protocol.id.hashCode ^ 0x2e9);
        for (var i = 0; i < iterations; i++) {
          final params = _randomParams(protocol, rng);
          final signal = protocol.encode(params);
          final noisy = _jitter(signal.flatten(repeats: 2), 0.15, rng);
          final decoded = protocol.decode(noisy);
          expect(decoded, isNotNull, reason: 'params $params noisy $noisy');
          expect(decoded!.isRepeatFrame, isFalse);
          expect(decoded.params, protocol.normalize(params));
          expect(decoded.consumed, signal.durationsUs.length);
        }
      });

      test('rejects its frame followed by 8 more bits', () {
        // What a longer protocol with the same leader sends (an AC state
        // frame, a 48-bit NEC variant): the codec's frame is only a prefix.
        final rng = Random(protocol.id.hashCode ^ 0x8b);
        for (var i = 0; i < 100; i++) {
          final signal = protocol.encode(_randomParams(protocol, rng));
          final extra = [for (var b = 0; b < 8; b++) rng.nextInt(2)];
          final longer = _withExtraBits(protocol, signal.durationsUs, extra);
          expect(protocol.decode(longer), isNull, reason: '$longer');
          final gap = signal.leadInGapUs;
          expect(protocol.decode([...longer, gap, ...longer]), isNull);
          final id = ProtocolRegistry.standard.identify(longer)?.protocolId;
          expect(id, isNot(protocol.id), reason: '$longer');
          // Sony12 plus 8 bits is a well-formed Sony20 frame; nothing else
          // may match a lengthened frame.
          expect(
            id,
            protocol == SonySirc.sony12 ? anyOf(isNull, 'Sony20') : isNull,
            reason: '$longer',
          );
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

    test('an NEC-leader AC frame is not taken for an NEC-family frame', () {
      // Gree-style: 9 ms + 4.5 ms leader, 35 bits, a mark and a 20 ms
      // connector space, 32 more bits and a stop mark.
      final rng = Random(35);
      final gree = <int>[9000, 4500];
      void bits(int n) {
        for (var i = 0; i < n; i++) {
          gree.addAll([620, rng.nextBool() ? 1600 : 540]);
        }
      }

      bits(35);
      gree.addAll([620, 19980]);
      bits(32);
      gree.add(620);
      expect(ProtocolRegistry.standard.identify(gree), isNull);
      for (final p in [const Nec1(), const Nec1F16(), const Nec2()]) {
        expect(p.decode(gree), isNull, reason: p.id);
      }
    });

    test('a 48-bit NEC-style frame is not taken for NEC1', () {
      final nec = const Nec1().encode({'D': 4, 'F': 8}).durationsUs;
      final frame48 = [
        ...nec,
        for (var i = 0; i < 16; i++) ...[i.isEven ? 1692 : 564, 564],
      ];
      expect(const Nec1().decode(frame48), isNull);
      expect(ProtocolRegistry.standard.identify(frame48), isNull);
    });

    test('RC6 accepts a 3t duration read low into the 2t window', () {
      // Element 8 is the 3t mark of mode bit 0 and a toggle of 1 (1332 us);
      // at 1106 us it is inside both the 2t and the 3t window.
      final s = const Rc6().encode({'D': 0, 'F': 0, 'T': 1});
      expect(s.durationsUs[8], 1332);
      final d = [...s.durationsUs]..[8] = 1106;
      expect(const Rc6().decode(d)!.params, {'D': 0, 'F': 0, 'T': 1});
    });

    test('identify tells NEC1 from NEC2 by the frame after the gap', () {
      final reg = ProtocolRegistry.standard;
      const p = {'D': 4, 'F': 8};
      String? id(List<int> d) => reg.identify(d)?.protocolId;
      expect(id(const Nec2().encode(p).flatten(repeats: 2)), 'NEC2');
      expect(id(const Nec2().encode(p).flatten(repeats: 1)), 'NEC2');
      expect(id(const Nec1().encode(p).flatten(repeats: 2)), 'NEC1');
      expect(id(const Nec1().encode(p).flatten(repeats: 1)), 'NEC1');
      // No second frame: the first-listed variant, as before.
      expect(id(const Nec2().encode(p).durationsUs), 'NEC1');
      // Something unrelated after the gap: also the first-listed variant.
      final main = const Nec2().encode(p).durationsUs;
      expect(id([...main, 40000, 300, 300, 300]), 'NEC1');
      expect(reg.identify(const Nec2().encode(p).flatten(repeats: 2))!.params, {
        'D': 4,
        'S': 251,
        'F': 8,
      });
    });

    test('identify tells NECx1 from NECx2 by the frame after the gap', () {
      final reg = ProtocolRegistry.standard;
      String? id(List<int> d) => reg.identify(d)?.protocolId;
      for (final p in [
        {'D': 7, 'S': 7, 'F': 2},
        {'D': 6, 'S': 6, 'F': 2},
      ]) {
        expect(id(const NecX1().encode(p).flatten(repeats: 2)), 'NECx1');
        expect(id(const NecX1().encode(p).flatten(repeats: 1)), 'NECx1');
        expect(id(const NecX2().encode(p).flatten(repeats: 2)), 'NECx2');
        expect(id(const NecX1().encode(p).durationsUs), 'NECx2');
      }
    });

    test('identify keeps NEC variants apart under jitter', () {
      final rng = Random(0x1d);
      for (final protocol in [
        const Nec1(),
        const Nec2(),
        const NecX1(),
        const NecX2(),
      ]) {
        for (var i = 0; i < 100; i++) {
          final params = _randomParams(protocol, rng);
          final flat = protocol.encode(params).flatten(repeats: 2);
          final r = ProtocolRegistry.standard.identify(
            _jitter(flat, 0.15, rng),
          );
          expect(r?.protocolId, protocol.id, reason: '$params');
          expect(r!.params, protocol.normalize(params));
        }
      }
    });

    test('identify returns null for noise', () {
      expect(ProtocolRegistry.standard.identify([100, 100, 100]), isNull);
    });
  });

  group('searchUnitExpansions', () {
    test(
      'tries both readings of an ambiguous duration, fewest units first',
      () {
        // 1050 us is inside both the 2-unit and the 3-unit window of 444 us.
        final seen = <String>[];
        final r = searchUnitExpansions(
          const [444, 1050, 444],
          0,
          444,
          const TimingTolerance(),
          accept: (levels, end) {
            seen.add(levels.map((l) => l ? 'M' : 's').join());
            return levels.length == 5 ? levels.length : null;
          },
        );
        expect(seen, ['MssM', 'MsssM']);
        expect(r, 5);
      },
    );

    test('bounds the work on hostile input', () {
      // Every duration is ambiguous: 2^40 readings without the bound.
      var calls = 0;
      final r = searchUnitExpansions<int>(
        List.filled(40, 1050),
        0,
        444,
        const TimingTolerance(),
        maxExpansions: 50,
        accept: (levels, end) {
          calls++;
          return null;
        },
      );
      expect(r, isNull);
      expect(calls, 50);
    });

    test('a short unmatched space or any unmatched mark rejects', () {
      Object? accept(List<bool> l, int e) => true;
      const t = TimingTolerance();
      expect(
        searchUnitExpansions([444, 200, 444], 0, 444, t, accept: accept),
        isNull,
      );
      expect(searchUnitExpansions([5000], 0, 444, t, accept: accept), isNull);
      expect(
        searchUnitExpansions([444, 5000, 444], 0, 444, t, accept: accept),
        isTrue,
      );
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

/// Scales every duration independently by a random factor in
/// `1 ± maxRelative`.
List<int> _jitter(List<int> durations, double maxRelative, Random rng) => [
  for (final d in durations)
    max(
      1,
      (d * (1 - maxRelative + rng.nextDouble() * 2 * maxRelative)).round(),
    ),
];

/// [frame] followed by [bits] more data bits in [p]'s own bit coding, before
/// the final mark: what a longer frame with the same leader looks like.
List<int> _withExtraBits(IrProtocol p, List<int> frame, List<int> bits) {
  switch (p) {
    case Rc5():
      // 889 us half-bits; 1 = space then mark; 27 captured half-bits (the
      // first start half-bit is the leading space).
      return _extendBiphase(frame, 889, 27, false, bits);
    case Rc6():
      // 444 us units; 1 = mark then space; leader (8t) plus 44 half-bits.
      return _extendBiphase(frame, 444, 52, true, bits);
    case SonySirc():
      // Pulse width: a 600 us space, then a 600 (0) or 1200 (1) us mark.
      return [
        ...frame,
        for (final b in bits) ...[600, b == 1 ? 1200 : 600],
      ];
  }
  // Pulse distance: the stop mark becomes the next bit's mark.
  final (zero, one, mark) = switch (p.id) {
    'Panasonic' => (432, 1296, 432),
    'LG' => (550, 1578, 526),
    'JVC' => (525, 1575, 525),
    'Sharp' || 'Denon' => (792, 1848, 264),
    _ => (564, 1692, 564), // NEC family
  };
  return [
    ...frame,
    for (final b in bits) ...[b == 1 ? one : zero, mark],
  ];
}

List<int> _extendBiphase(
  List<int> frame,
  int unit,
  int frameSlots,
  bool oneStartsWithMark,
  List<int> bits,
) {
  final levels = <bool>[
    for (var i = 0; i < frame.length; i++)
      for (var k = 0; k < frame[i] ~/ unit; k++) i.isEven,
  ];
  // A final space half-bit is not in the frame (it merges into the gap).
  while (levels.length < frameSlots) {
    levels.add(false);
  }
  for (final b in bits) {
    final first = (b == 1) == oneStartsWithMark;
    levels
      ..add(first)
      ..add(!first);
  }
  final out = <int>[];
  for (var i = 0; i < levels.length; i++) {
    if (i > 0 && levels[i] == levels[i - 1]) {
      out[out.length - 1] += unit;
    } else {
      out.add(unit);
    }
  }
  if (!levels.last) out.removeLast();
  return out;
}

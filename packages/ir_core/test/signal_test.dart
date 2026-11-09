import 'dart:convert';

import 'package:ir_core/ir_core.dart';
import 'package:test/test.dart';

const _android = TransportCapabilities(
  carrierRangesHz: [CarrierRange(30000, 60000)],
  maxPatternUs: 2000000,
  canLearn: false,
  latencyClass: LatencyClass.local,
);

void main() {
  group('IrSignal', () {
    final nec = const Nec1().encode({'D': 4, 'F': 8});

    test('frames() sends main frame plus requested repeats', () {
      expect(nec.frames().length, 1);
      final f = nec.frames(repeats: 3);
      expect(f.length, 4);
      expect(f.first.frame, nec.durationsUs);
      expect(f.first.gapAfterUs, nec.repeat!.leadInGapUs);
      expect(f[1].frame, nec.repeat!.frameUs);
      expect(f.last.gapAfterUs, nec.repeat!.gapUs);
      expect(() => nec.frames(repeats: -1), throwsArgumentError);
    });

    test('flatten joins frames with gaps and ends on a mark', () {
      final flat = nec.flatten(repeats: 2);
      expect(
        flat.length,
        nec.durationsUs.length + 2 * (nec.repeat!.frameUs.length + 1),
      );
      expect(flat.length.isOdd, isTrue);
      expect(flat[nec.durationsUs.length], nec.repeat!.leadInGapUs);
    });

    test('a signal without repeat uses the default trailing gap', () {
      final s = IrSignal(carrierHz: 38000, durationsUs: [100, 200, 300]);
      expect(s.leadInGapUs, IrSignal.defaultTrailingGapUs);
      expect(s.minRepeats, 0);
      expect(s.frames(repeats: 5).length, 1);
      expect(s.flatten(), [100, 200, 300]);
      expect(s.frameLengthUs, 600);
    });

    test('JSON round-trips and equality covers every field', () {
      final back = IrSignal.fromJson(jsonDecode(jsonEncode(nec.toJson())));
      expect(back, nec);
      expect(back.hashCode, nec.hashCode);
      final sony = SonySirc.sony12.encode({'D': 1, 'F': 21});
      expect(IrSignal.fromJson(jsonDecode(jsonEncode(sony.toJson()))), sony);
      expect(sony == nec, isFalse);
      expect(nec.toString(), contains('38400 Hz'));
      expect(nec.repeat.toString(), contains('RepeatSpec'));
    });

    test('fromJson rejects malformed input with FormatException only', () {
      final bad = <Object?>[
        null,
        42,
        'x',
        <String, Object?>{},
        {'carrierHz': '38k', 'durationsUs': <int>[]},
        {'carrierHz': 38000, 'durationsUs': 'nope'},
        {
          'carrierHz': 38000,
          'durationsUs': [1, 'a', 3],
        },
        {
          'carrierHz': 38000,
          'durationsUs': List.filled(maxJsonDurations + 1, 1),
        },
        {
          'carrierHz': 38000,
          'durationsUs': [1],
          'repeat': 5,
        },
        {
          'carrierHz': 38000,
          'durationsUs': [1],
          'repeat': {
            'frameUs': [1],
            'leadInGapUs': 0,
            'gapUs': 1,
          },
        },
        {
          'carrierHz': 38000,
          'durationsUs': [1],
          'repeat': {
            'frameUs': [1],
            'leadInGapUs': 5,
            'gapUs': 1,
            'minRepeats': -1,
          },
        },
      ];
      for (final b in bad) {
        expect(() => IrSignal.fromJson(b), throwsFormatException, reason: '$b');
      }
    });

    test('RepeatSpec guards its invariants', () {
      expect(
        () => RepeatSpec(frameUs: [1], leadInGapUs: 0, gapUs: 1),
        throwsArgumentError,
      );
      expect(
        () =>
            RepeatSpec(frameUs: [1], leadInGapUs: 1, gapUs: 1, minRepeats: -1),
        throwsArgumentError,
      );
    });
  });

  group('SignalValidator', () {
    const v = SignalValidator();

    test('accepts every codec signal on Android-like caps', () {
      for (final p in builtInProtocols) {
        final params = {for (final s in p.params) s.name: 1};
        expect(v.validate(p.encode(params), _android), isEmpty, reason: p.id);
      }
    });

    test('rejects empty, even-length, zero and over-cap durations', () {
      RejectReason one(List<int> d) => v
          .validate(IrSignal(carrierHz: 38000, durationsUs: d), _android)
          .single
          .reason;
      expect(one([]), RejectReason.invalidDurations);
      expect(one([100, 100]), RejectReason.invalidDurations);
      expect(one([100, 0, 100]), RejectReason.invalidDurations);
      expect(one([100, 150001, 100]), RejectReason.invalidDurations);
      expect(one([-5]), RejectReason.invalidDurations);
    });

    test('checks repeat frame and gaps against the per-element cap', () {
      final s = IrSignal(
        carrierHz: 38000,
        durationsUs: [100],
        repeat: RepeatSpec(frameUs: [100], leadInGapUs: 200000, gapUs: 10),
      );
      expect(
        v.validate(s, _android).single.reason,
        RejectReason.invalidDurations,
      );
      const loose = SignalValidator(
        limits: ValidationLimits(maxElementUs: 300000),
      );
      expect(loose.validate(s, _android), isEmpty);
    });

    test(
      'rejects a carrier outside the transport ranges, never substitutes',
      () {
        final s = IrSignal(carrierHz: 455000, durationsUs: [100]);
        final issues = v.validate(s, _android);
        expect(issues.single.reason, RejectReason.carrierOutOfRange);
        expect(issues.single.toString(), contains('455000'));
      },
    );

    test('unknown carrier ranges fall back to the plausible window', () {
      const unknown = TransportCapabilities(
        carrierRangesHz: null,
        maxPatternUs: 2000000,
        canLearn: false,
        latencyClass: LatencyClass.local,
      );
      expect(
        v.validate(IrSignal(carrierHz: 38000, durationsUs: [1]), unknown),
        isEmpty,
      );
      final bad = v.validate(
        IrSignal(carrierHz: 10000, durationsUs: [1]),
        unknown,
      );
      expect(bad.single.detail, contains('unknown'));
    });

    test('rejects frames longer than the transport maximum', () {
      const tiny = TransportCapabilities(
        carrierRangesHz: [CarrierRange(30000, 60000)],
        maxPatternUs: 10000,
        maxDurations: 10,
        canLearn: false,
        latencyClass: LatencyClass.lan,
      );
      final s = const Nec1().encode({'D': 1, 'F': 1});
      final reasons = v.validate(s, tiny).map((i) => i.reason).toSet();
      expect(reasons, {
        RejectReason.patternTooLong,
        RejectReason.tooManyDurations,
      });
    });
  });

  group('plan', () {
    const v = SignalValidator();
    final nec = const Nec1().encode({'D': 4, 'F': 8});

    test('joins frames into one chunk when they fit', () {
      final chunks = v.plan(nec, _android, repeats: 3);
      expect(chunks.length, 1);
      expect(chunks.single.durationsUs, nec.flatten(repeats: 3));
      expect(chunks.single.gapAfterUs, nec.repeat!.gapUs);
      expect(chunks.single.carrierHz, 38400);
    });

    test('splits at frame boundaries when the pattern limit is reached', () {
      const short = TransportCapabilities(
        carrierRangesHz: [CarrierRange(30000, 60000)],
        maxPatternUs: 250000,
        canLearn: false,
        latencyClass: LatencyClass.local,
      );
      final chunks = v.plan(nec, short, repeats: 20);
      expect(chunks.length, greaterThan(1));
      for (final c in chunks) {
        expect(c.lengthUs, lessThan(short.maxPatternUs));
        expect(c.durationsUs.length.isOdd, isTrue);
      }
      // Total on-air content is preserved.
      final total = chunks.fold<int>(
        0,
        (a, c) => a + c.lengthUs + c.gapAfterUs,
      );
      final expected =
          nec.flatten(repeats: 20).fold<int>(0, (a, b) => a + b) +
          nec.repeat!.gapUs;
      expect(total, expected);
    });

    test('splits on the duration-count limit too', () {
      const counted = TransportCapabilities(
        carrierRangesHz: [CarrierRange(30000, 60000)],
        maxPatternUs: 2000000,
        maxDurations: 80,
        canLearn: false,
        latencyClass: LatencyClass.lan,
      );
      final chunks = v.plan(nec, counted, repeats: 4);
      expect(chunks.every((c) => c.durationsUs.length <= 80), isTrue);
      expect(chunks.length, greaterThan(1));
    });

    test('throws if a single frame cannot fit', () {
      const tiny = TransportCapabilities(
        carrierRangesHz: [CarrierRange(30000, 60000)],
        maxPatternUs: 1000,
        canLearn: false,
        latencyClass: LatencyClass.local,
      );
      expect(() => v.plan(nec, tiny), throwsArgumentError);
    });
  });

  group('transport value types', () {
    test('results and statuses describe themselves', () {
      expect(
        const TransmitSent(elapsed: Duration(milliseconds: 5)).toString(),
        contains('5 ms'),
      );
      expect(
        const TransmitRejected(RejectReason.carrierOutOfRange, 'x').toString(),
        contains('carrierOutOfRange'),
      );
      expect(
        const TransmitTransportUnavailable('off').toString(),
        contains('off'),
      );
      expect(
        const TransmitTimeout(Duration(seconds: 1)).toString(),
        contains('1000'),
      );
      final now = DateTime(2026);
      expect(Healthy(checkedAt: now).isUsable, isTrue);
      expect(Degraded(checkedAt: now, reason: 'r').isUsable, isTrue);
      expect(
        Degraded(checkedAt: now, reason: 'r', canSend: false).isUsable,
        isFalse,
      );
      expect(Unreachable(checkedAt: now, reason: 'r').isUsable, isFalse);
      expect(const CarrierRange(1, 2), const CarrierRange(1, 2));
      expect(
        const CarrierRange(1, 2).hashCode,
        const CarrierRange(1, 2).hashCode,
      );
      expect(const CarrierRange(1, 2).toString(), '1-2 Hz');
      expect(_android.toString(), contains('2000000'));
    });
  });
}

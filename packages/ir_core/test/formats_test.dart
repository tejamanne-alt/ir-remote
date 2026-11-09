import 'dart:math';

import 'package:ir_core/ir_core.dart';
import 'package:test/test.dart';

void main() {
  group('Pronto', () {
    test('parses a hand-computed 0000 code exactly', () {
      // Divisor 0x6D: unit = 109 × 0.241246 µs = 26.2958 µs.
      final s = Pronto.parse('0000 006D 0002 0000 0157 00AC 0015 0689');
      expect(s.carrierHz, 38029);
      expect(s.durationsUs, [9019, 4523, 552]);
      expect(s.leadInGapUs, 43993);
      // Once-only codes repeat the once sequence while held.
      expect(s.repeat!.frameUs, s.durationsUs);
    });

    test('once and repeat sequences map to frame and repeat', () {
      final s = Pronto.parse(
        '0000 006D 0001 0002 0157 00AC 0157 0055 0015 0E47',
      );
      expect(s.durationsUs, [9019]);
      expect(s.repeat!.frameUs, [9019, 2235, 552]);
      expect(s.leadInGapUs, 4523);
      expect(s.repeat!.gapUs, (0xE47 * 109 * Pronto.tickUs).round());
    });

    test('repeat-only codes use the repeat sequence as the main frame', () {
      final s = Pronto.parse('0000 006D 0000 0001 0157 00AC');
      expect(s.durationsUs, [9019]);
      expect(s.repeat!.frameUs, [9019]);
    });

    test('round-trips every codec within one carrier period', () {
      for (final p in builtInProtocols) {
        final params = {for (final s in p.params) s.name: 1};
        final original = p.encode(params);
        final hex = Pronto.format(original);
        expect(hex, matches(RegExp(r'^0000( [0-9A-F]{4})+$')));
        final back = Pronto.parse(hex);
        final period = 1e6 / original.carrierHz;
        expect(
          (back.carrierHz - original.carrierHz).abs(),
          lessThan(original.carrierHz * 0.01),
        );
        _close(back.durationsUs, original.durationsUs, period);
        _close(back.repeat!.frameUs, original.repeat!.frameUs, period);
        expect(
          (back.leadInGapUs - original.leadInGapUs).abs(),
          lessThan(period),
        );
        // The decoded protocol survives the trip.
        expect(
          p.decode(back.durationsUs)?.params,
          p.normalize(params),
          reason: p.id,
        );
      }
    });

    test('formats a signal without repeat with the default gap', () {
      final hex = Pronto.format(IrSignal(carrierHz: 38000, durationsUs: [500]));
      final back = Pronto.parse(hex);
      expect(back.durationsUs.single, closeTo(500, 27));
      expect(back.leadInGapUs, closeTo(IrSignal.defaultTrailingGapUs, 27));
      expect(
        () => Pronto.format(IrSignal(carrierHz: 0, durationsUs: [1])),
        throwsArgumentError,
      );
    });

    test('RC5 and RC6 presets render through the codecs', () {
      final rc5 = Pronto.parse('5000 0073 0000 0001 0000 000C');
      expect(rc5, const Rc5().encode({'D': 0, 'F': 12}));
      final rc6 = Pronto.parse('6000 0073 0000 0002 0004 005A');
      expect(rc6, const Rc6().encode({'D': 4, 'F': 0x5A}));
    });

    test('rejects malformed codes with FormatException', () {
      for (final bad in [
        '',
        '0000',
        '0000 006D 0001',
        'zzzz 006D 0000 0001 0001 0001',
        '00000 006D 0000 0001 0001 0001',
        '0000 0000 0000 0001 0001 0001',
        '0000 006D 0000 0000',
        '0000 006D 0001 0000 0001',
        '0000 006D 0001 0000 0001 0001 0001',
        '0000 006D 0001 0000 0001 0000',
        '0100 006D 0001 0000 0001 0001',
        '5000 0073 0000 0001 0020 000C',
        '6000 0073 0000 0002 0100 0001',
        '5000 0073 0000 0001',
        'x' * (Pronto.maxInputLength + 1),
        // Divisor 1 or 2 implies a 4.1 or 2.1 MHz carrier and bursts that
        // round to 0 us.
        '0000 0001 0000 0001 0001 0001',
        '0000 0002 0001 0000 0001 0001',
        '0000 0001 0001 0000 0001 0005',
        // Divisor 0x01A0 (416) implies 9.96 kHz, just below the range.
        '0000 01A0 0001 0000 0010 0100',
        '0000 FFFF 0001 0000 0010 0100',
      ]) {
        expect(() => Pronto.parse(bad), throwsFormatException, reason: bad);
      }
    });

    test('accepts carriers from 10 to 500 kHz', () {
      // Divisor 9: 460.6 kHz (Bang & Olufsen's 455 kHz rounds here).
      final high = Pronto.parse('0000 0009 0001 0000 0010 0100');
      expect(high.carrierHz, 460572);
      expect(high.carrierHz, lessThanOrEqualTo(Pronto.maxCarrierHz));
      expect(high.durationsUs, [35]);
      // Divisor 0x019E (414): 10.01 kHz.
      final low = Pronto.parse('0000 019E 0001 0000 0010 0100');
      expect(low.carrierHz, greaterThanOrEqualTo(Pronto.minCarrierHz));
      expect(
        () => Pronto.parse('0000 0008 0001 0000 0010 0100'),
        throwsFormatException,
      );
    });

    test('survives 10,000 fuzz cases without a crash', () {
      final rng = Random(20261109);
      final seeds = [
        Pronto.format(const Nec1().encode({'D': 4, 'F': 8})),
        Pronto.format(SonySirc.sony12.encode({'D': 1, 'F': 21})),
        '0000 006D 0002 0000 0157 00AC 0015 0689',
        '5000 0073 0000 0001 0000 000C',
      ];
      const alphabet = '0123456789ABCDEFabcdef ,\n\t-xZ';
      var parsed = 0;
      for (var i = 0; i < 10000; i++) {
        final String input;
        switch (i % 4) {
          case 3: // well-formed learned header, extreme divisor and bursts
            final once = rng.nextInt(3);
            final rep = rng.nextInt(3);
            final divisor = rng.nextBool()
                ? rng.nextInt(16)
                : rng.nextInt(0x10000);
            String w(int v) => v.toRadixString(16).padLeft(4, '0');
            input = [
              0,
              divisor,
              once,
              rep,
              for (var k = 0; k < 2 * (once + rep); k++)
                rng.nextBool() ? rng.nextInt(6) : rng.nextInt(0x10000),
            ].map(w).join(' ');
          case 0: // random words
            final n = rng.nextInt(40);
            input = List.generate(
              n,
              (_) => rng.nextInt(0x10000).toRadixString(16).padLeft(4, '0'),
            ).join(' ');
          case 1: // mutated valid code
            final chars = seeds[rng.nextInt(seeds.length)].split('');
            final edits = 1 + rng.nextInt(6);
            for (var e = 0; e < edits && chars.isNotEmpty; e++) {
              final pos = rng.nextInt(chars.length);
              switch (rng.nextInt(3)) {
                case 0:
                  chars[pos] = alphabet[rng.nextInt(alphabet.length)];
                case 1:
                  chars.removeAt(pos);
                default:
                  chars.insert(pos, alphabet[rng.nextInt(alphabet.length)]);
              }
            }
            input = chars.join();
          default: // random characters
            input = String.fromCharCodes(
              List.generate(rng.nextInt(80), (_) => rng.nextInt(128)),
            );
        }
        try {
          final s = Pronto.parse(input);
          parsed++;
          expect(s.durationsUs.length.isOdd, isTrue);
          expect(s.durationsUs.every((d) => d > 0), isTrue);
          expect(
            s.carrierHz,
            inInclusiveRange(Pronto.minCarrierHz, Pronto.maxCarrierHz),
          );
          final r = s.repeat;
          if (r != null) {
            expect(r.frameUs.every((d) => d > 0), isTrue);
            expect(r.leadInGapUs > 0 && r.gapUs > 0, isTrue);
          }
        } on FormatException {
          // expected for most inputs
        }
      }
      expect(parsed, greaterThan(0));
    });
  });

  group('RawFormat', () {
    test('parses unsigned and signed lists', () {
      expect(RawFormat.parse('9000 4500 560').durationsUs, [9000, 4500, 560]);
      final s = RawFormat.parse('+9000 -4500 +560 -40000', carrierHz: 36000);
      expect(s.durationsUs, [9000, 4500, 560]);
      expect(s.leadInGapUs, 40000);
      expect(s.carrierHz, 36000);
      expect(RawFormat.parse('9000,4500,\n560').durationsUs.length, 3);
    });

    test('formats signed durations', () {
      expect(
        RawFormat.format(IrSignal(carrierHz: 38000, durationsUs: [1, 2, 3])),
        '+1 -2 +3',
      );
    });

    test('rejects malformed text', () {
      for (final bad in [
        '',
        'abc',
        '-100 +200',
        '+100 +200',
        '100 0 100',
        '12345678',
        List.filled(RawFormat.maxDurations + 1, '1').join(' '),
        'x' * (RawFormat.maxInputLength + 1),
      ]) {
        expect(() => RawFormat.parse(bad), throwsFormatException, reason: bad);
      }
    });
  });
}

void _close(List<int> a, List<int> b, double tol) {
  expect(a.length, b.length);
  for (var i = 0; i < a.length; i++) {
    expect((a[i] - b[i]).abs(), lessThanOrEqualTo(tol), reason: 'index $i');
  }
}

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:ir_core/ir_core.dart';
import 'package:test/test.dart';

const _header = 'Filetype: IR signals file\nVersion: 1\n';

String _parsed(String name, String protocol, String address, String command) =>
    '#\nname: $name\ntype: parsed\nprotocol: $protocol\n'
    'address: $address\ncommand: $command\n';

ProtocolKeyCode _one(String protocol, String address, String command) {
  final r = FlipperIr.parse(
    _header + _parsed('Key', protocol, address, command),
  );
  expect(r.skipped, isEmpty, reason: '${r.skipped}');
  return r.signals.single.code as ProtocolKeyCode;
}

/// `protocol {params}`; params are in codec order, so this is canonical.
String _d(ProtocolKeyCode c) => '${c.protocol} ${c.params}';

IrSignal _fixture(String path) {
  final json = jsonDecode(File('test/fixtures/$path').readAsStringSync());
  return IrSignal.fromJson(json);
}

void main() {
  group('Flipper .ir format', () {
    test('parses the example from the format description', () {
      final r = FlipperIr.parse(
        'Filetype: IR signals file\n'
        'Version: 1\n'
        '#\n'
        'name: Button_1\n'
        'type: parsed\n'
        'protocol: NECext\n'
        'address: EE 87 00 00\n'
        'command: 5D A0 00 00\n'
        '#\n'
        'name: Button_2\n'
        'type: raw\n'
        'frequency: 38000\n'
        'duty_cycle: 0.330000\n'
        'data: 504 3432 502 483 500 484 510 502 502 482 501 485 509 1452 504 '
        '1458 509 1452 504 481 501 474 509 3420 503\n'
        '#\n'
        'name: Button_3\n'
        'type: parsed\n'
        'protocol: SIRC\n'
        'address: 01 00 00 00\n'
        'command: 15 00 00 00\n',
      );
      expect(r.filetype, 'IR signals file');
      expect(r.skipped, isEmpty);
      expect(r.signals.map((s) => s.name), [
        'Button_1',
        'Button_2',
        'Button_3',
      ]);
      expect(r.signals.map((s) => s.line), [4, 10, 16]);
      final b1 = r.signals[0].code as ProtocolKeyCode;
      // Command high byte 0xA0 is not ~0x5D (0xA2): a 16-bit function.
      expect(b1.protocol, 'NEC1-f16');
      expect(b1.params, {'D': 0xEE, 'S': 0x87, 'F': 0xA05D});
      final b2 = (r.signals[1].code as RawKeyCode).signal;
      expect(b2.carrierHz, 38000);
      expect(b2.durationsUs.length, 25);
      expect(b2.durationsUs.first, 504);
      expect(b2.durationsUs.last, 503);
      expect(b2.repeat, isNull);
      expect(r.signals[1].source, 'raw');
      final b3 = r.signals[2].code as ProtocolKeyCode;
      expect(b3.protocol, 'Sony12');
      expect(b3.params, {'D': 1, 'F': 0x15});
      expect(r.signals[2].source, 'SIRC');
    });

    test('accepts the library file type, CRLF and blank lines', () {
      final r = FlipperIr.parse(
        'Filetype: IR library file\r\nVersion: 1\r\n\r\n# comment\r\n'
        'name: POWER\r\ntype: parsed\r\nprotocol: NEC\r\n'
        'address: 04 00 00 00\r\ncommand: 08 00 00 00\r\n',
      );
      expect(r.filetype, 'IR library file');
      expect(r.signals.single.name, 'POWER');
    });

    test('a trailing space in raw data is dropped, not made a gap', () {
      final r = FlipperIr.parse(
        '${_header}name: A\ntype: raw\nfrequency: 36000\n'
        'duty_cycle: 0.33\ndata: 900 900 1800 172\n',
      );
      final s = (r.signals.single.code as RawKeyCode).signal;
      expect(s.durationsUs, [900, 900, 1800]);
      expect(s.repeat, isNull);
      expect(s.carrierHz, 36000);
    });

    test('duty_cycle is optional for raw signals', () {
      final r = FlipperIr.parse(
        '${_header}name: A\ntype: raw\nfrequency: 38000\ndata: 100\n',
      );
      expect((r.signals.single.code as RawKeyCode).signal.durationsUs, [100]);
    });

    test('rejects unusable files with FormatException', () {
      for (final bad in [
        '',
        'Version: 1\nFiletype: IR signals file\n',
        'Filetype: IR signals file\n',
        'Filetype: Flipper SubGhz Key File\nVersion: 1\n',
        'Filetype: IR signals file\nVersion: 2\n',
        '${_header}type: raw\n',
        '${_header}name: A\nthis line has no colon\n',
        '${_header}name: A\n: value\n',
        '${_header}name: A\nbad key!: 1\n',
        '${_header}name: A\n${'x' * (FlipperIr.maxLineLength + 1)}\n',
        'x' * (FlipperIr.maxInputLength + 1),
      ]) {
        expect(
          () => FlipperIr.parse(bad),
          throwsFormatException,
          reason: bad.length > 80 ? '${bad.length} chars' : bad,
        );
      }
    });

    test('enforces the signal limit', () {
      final ok = StringBuffer(_header);
      for (var i = 0; i < FlipperIr.maxSignals; i++) {
        ok.write(
          'name: K$i\ntype: parsed\nprotocol: NEC\n'
          'address: 00 00 00 00\ncommand: 01 00 00 00\n',
        );
      }
      expect(FlipperIr.parse(ok.toString()).signals, hasLength(10000));
      ok.write('name: one more\n');
      expect(() => FlipperIr.parse(ok.toString()), throwsFormatException);
    });

    test('caps fields per signal and per file, failing fast', () {
      // Near 5 MiB of empty fields in one block. Before the cap, every line
      // became a field record first (about 220 MiB) and the block was then
      // merely skipped.
      final oneBlock = StringBuffer('${_header}name: A\n');
      while (oneBlock.length < FlipperIr.maxInputLength - 3) {
        oneBlock.write('a:\n');
      }
      final input = oneBlock.toString();
      final sw = Stopwatch()..start();
      expect(() => FlipperIr.parse(input), throwsFormatException);
      expect(sw.elapsedMilliseconds, lessThan(500));

      // Many small blocks with undefined fields: the file-wide cap.
      final many = StringBuffer(_header);
      const perBlock = FlipperIr.maxFieldsPerSignal;
      for (var n = 0; n * perBlock <= FlipperIr.maxFields; n++) {
        many.write('name: K$n\n');
        for (var f = 1; f < perBlock; f++) {
          many.write('${'x' * f}: 1\n');
        }
      }
      expect(() => FlipperIr.parse(many.toString()), throwsFormatException);

      // At the per-signal cap a block still parses (undefined fields are
      // ignored).
      final full = StringBuffer(
        '${_header}name: A\ntype: parsed\nprotocol: NEC\n'
        'address: 04 00 00 00\ncommand: 08 00 00 00\n',
      );
      for (var f = 5; f < FlipperIr.maxFieldsPerSignal; f++) {
        full.write('unknown_${'x' * f}: 1\n');
      }
      expect(FlipperIr.parse(full.toString()).signals, hasLength(1));
      full.write('one_more: 1\n');
      expect(() => FlipperIr.parse(full.toString()), throwsFormatException);
    });

    test('reports bad blocks and keeps the rest', () {
      final b = StringBuffer(_header)
        ..write(_parsed('Good', 'NEC', '04 00 00 00', '08 00 00 00'))
        ..write(_parsed('Nec42', 'NEC42', '1A 01 00 00', '17 00 00 00'))
        ..write(_parsed('Rca', 'RCA', '0F 00 00 00', '54 00 00 00'))
        ..write(_parsed('Pio', 'Pioneer', 'A0 00 00 00', '5F 00 00 00'))
        ..write(_parsed('Denon', 'Kaseikyo', '41 54 32 00', '01 00 00 00'))
        ..write(_parsed('Wide', 'NEC', '00 01 00 00', '08 00 00 00'))
        ..write(_parsed('Hex', 'NEC', '04 00 00', '08 00 00 00'))
        ..write(_parsed('Hex2', 'NEC', '4 00 00 00', '08 00 00 00'))
        ..write(_parsed('Hex3', 'NEC', 'G4 00 00 00', '08 00 00 00'))
        ..write(
          '#\nname: NoType\nprotocol: NEC\n'
          '#\nname: Odd\ntype: learned\n'
          '#\nname: Dup\ntype: raw\ntype: raw\n'
          '#\nname: NoProto\ntype: parsed\naddress: 00 00 00 00\n'
          '#\nname: Freq\ntype: raw\nfrequency: 38k\ndata: 1\n'
          '#\nname: Freq2\ntype: raw\nfrequency: 5\ndata: 1\n'
          '#\nname: Duty\ntype: raw\nfrequency: 38000\nduty_cycle: 7\n'
          'data: 1\n'
          '#\nname: Zero\ntype: raw\nfrequency: 38000\ndata: 10 0 10\n'
          '#\nname: Neg\ntype: raw\nfrequency: 38000\ndata: 10 -5 10\n'
          '#\nname: Empty\ntype: raw\nfrequency: 38000\ndata:\n'
          '#\nname: Long\ntype: raw\nfrequency: 38000\ndata: '
          '${List.filled(1025, '10').join(' ')}\n'
          '#\nname:\ntype: raw\nfrequency: 38000\ndata: 10\n'
          '#\nname: Unknown field\ntype: raw\nfrequency: 38000\n'
          'data: 10\nfuture_field: 1\n',
        );
      final r = FlipperIr.parse(b.toString());
      expect(r.signals.map((s) => s.name), ['Good', 'Unknown field']);
      final reasons = {for (final s in r.skipped) s.name: s.reason};
      expect(reasons, {
        'Nec42': FlipperSkipReason.unsupportedProtocol,
        'Rca': FlipperSkipReason.unsupportedProtocol,
        'Pio': FlipperSkipReason.unsupportedProtocol,
        'Denon': FlipperSkipReason.unsupportedProtocol,
        'Wide': FlipperSkipReason.outOfRange,
        'Hex': FlipperSkipReason.malformedField,
        'Hex2': FlipperSkipReason.malformedField,
        'Hex3': FlipperSkipReason.malformedField,
        'NoType': FlipperSkipReason.malformedField,
        'Odd': FlipperSkipReason.unknownType,
        'Dup': FlipperSkipReason.malformedField,
        'NoProto': FlipperSkipReason.malformedField,
        'Freq': FlipperSkipReason.malformedField,
        'Freq2': FlipperSkipReason.outOfRange,
        'Duty': FlipperSkipReason.malformedField,
        'Zero': FlipperSkipReason.outOfRange,
        'Neg': FlipperSkipReason.malformedField,
        'Empty': FlipperSkipReason.malformedField,
        'Long': FlipperSkipReason.outOfRange,
        '': FlipperSkipReason.malformedField,
      });
      final nec42 = r.skipped.firstWhere((s) => s.name == 'Nec42');
      expect(nec42.protocol, 'NEC42');
      expect(nec42.toString(), contains('unsupportedProtocol (NEC42)'));
    });
  });

  group('Flipper protocol mapping', () {
    test('Samsung32 TV power is NECx2 D=7 F=2', () {
      final c = _one('Samsung32', '07 00 00 00', '02 00 00 00');
      expect(c.protocol, 'NECx2');
      expect(c.params, {'D': 7, 'S': 7, 'F': 2});
      expect(
        c.toSignal(ProtocolRegistry.standard).durationsUs,
        _fixture('NECx2/samsung_tv_power.json').durationsUs,
      );
    });

    test('NEC LG TV power is NEC1 D=4 F=8', () {
      final c = _one('NEC', '04 00 00 00', '08 00 00 00');
      expect(c.protocol, 'NEC1');
      expect(c.params, {'D': 4, 'S': 251, 'F': 8});
      expect(
        c.toSignal(ProtocolRegistry.standard),
        _fixture('NEC1/lg_tv_power.json'),
      );
    });

    test('NECext: little-endian address, 8- or 16-bit command', () {
      final inv = _one('NECext', '86 05 00 00', '0F F0 00 00');
      expect(inv.protocol, 'NEC1');
      expect(inv.params, {'D': 0x86, 'S': 0x05, 'F': 0x0F});
      expect(
        inv.toSignal(ProtocolRegistry.standard).durationsUs,
        _fixture('NEC1/extended_address.json').durationsUs,
      );
      final f16 = _one('NECext', '04 37 00 00', '34 12 00 00');
      expect(f16.protocol, 'NEC1-f16');
      expect(f16.params, {'D': 4, 'S': 0x37, 'F': 0x1234});
      expect(
        f16.toSignal(ProtocolRegistry.standard).durationsUs,
        _fixture('NEC1-f16/f16.json').durationsUs,
      );
    });

    test('SIRC variants map to Sony12/15/20 with the 20-bit split', () {
      expect(_one('SIRC', '01 00 00 00', '15 00 00 00').params, {
        'D': 1,
        'F': 0x15,
      });
      final s15 = _one('SIRC15', 'E4 00 00 00', '38 00 00 00');
      expect(_d(s15), 'Sony15 {D: 228, F: 56}');
      // 0x0D3A = 26 | 105 << 5: device 26, extension 105 (5 + 8 bits).
      final s20 = _one('SIRC20', '3A 0D 00 00', '15 00 00 00');
      expect(_d(s20), 'Sony20 {D: 26, S: 105, F: 21}');
      expect(
        ProtocolRegistry.standard
            .identify(s20.toSignal(ProtocolRegistry.standard).durationsUs)
            ?.params,
        {'D': 26, 'S': 105, 'F': 0x15},
      );
    });

    test('RC5 and RC5X map to RC5; RC5X sets command bit 6', () {
      final rc5 = _one('RC5', '00 00 00 00', '0C 00 00 00');
      expect(_d(rc5), 'RC5 {D: 0, F: 12}');
      final rc5x = _one('RC5X', '00 00 00 00', '12 00 00 00');
      expect(_d(rc5x), 'RC5 {D: 0, F: 82}');
      expect(
        rc5.toSignal(ProtocolRegistry.standard),
        _fixture('RC5/tv_power_t0.json'),
      );
    });

    test('RC6 maps to RC6 mode 0 without the toggle bit', () {
      final c = _one('RC6', '00 00 00 00', '0C 00 00 00');
      expect(_d(c), 'RC6 {D: 0, F: 12}');
      expect(
        c.toSignal(ProtocolRegistry.standard),
        _fixture('RC6/tv_power_t0.json'),
      );
    });

    test('Kaseikyo with the Panasonic vendor code maps to Panasonic', () {
      // Panasonic TV power: D=128 S=0 F=61, the Kaseikyo 10-bit data 0x3D0.
      final power = _one('Kaseikyo', '80 02 20 00', 'D0 03 00 00');
      expect(_d(power), 'Panasonic {D: 128, S: 0, F: 61}');
      expect(
        power.toSignal(ProtocolRegistry.standard),
        _fixture('Panasonic/tv_power.json'),
      );
      // Address byte 3 (ID) lands in F bits 6-7; byte 0 low nibble in S.
      final down = _one('Kaseikyo', '80 02 20 01', 'B0 00 00 00');
      expect(down.params, {'D': 128, 'S': 0, 'F': 75});
      final s = _one('Kaseikyo', '89 02 20 03', 'C4 03 00 00');
      expect(s.params, {'D': 128, 'S': 0x49, 'F': 0x3C | 0xC0});
    });

    test('mapParsed exposes the table and range errors', () {
      expect(FlipperIr.mapParsed('Samsung32', 7, 2)?.params, {
        'D': 7,
        'S': 7,
        'F': 2,
      });
      expect(FlipperIr.mapParsed('NEC42', 1, 1), isNull);
      expect(FlipperIr.mapParsed('Kaseikyo', 0x325441, 1), isNull);
      expect(() => FlipperIr.mapParsed('SIRC', 32, 1), throwsFormatException);
      expect(
        () => FlipperIr.mapParsed('Kaseikyo', 0x04200280, 1),
        throwsFormatException,
      );
      expect(
        () => FlipperIr.mapParsed('Kaseikyo', 0x00200280, 0x400),
        throwsFormatException,
      );
      for (final p in FlipperIr.supportedProtocols) {
        final address = p == 'Kaseikyo' ? 0x200200 : 0;
        expect(FlipperIr.mapParsed(p, address, 0), isNotNull, reason: p);
      }
    });

    test('every mapped code decodes back to itself', () {
      final rng = Random(7);
      final widths = {
        'NEC': (8, 8),
        'NECext': (16, 16),
        'Samsung32': (8, 8),
        'SIRC': (5, 7),
        'SIRC15': (8, 7),
        'SIRC20': (13, 7),
        'RC5': (5, 6),
        'RC5X': (5, 6),
        'RC6': (8, 8),
      };
      for (var i = 0; i < 500; i++) {
        for (final e in widths.entries) {
          final a = rng.nextInt(1 << e.value.$1);
          final c = rng.nextInt(1 << e.value.$2);
          final code = FlipperIr.mapParsed(e.key, a, c)!;
          final decoded = ProtocolRegistry.standard
              .require(code.protocol)
              .decode(code.toSignal(ProtocolRegistry.standard).durationsUs);
          expect(decoded, isNotNull, reason: '${e.key} $a $c');
          expect(
            {...decoded!.params}..remove('T'),
            code.params,
            reason: '${e.key} $a $c',
          );
        }
      }
    });
  });

  test('survives 12,000 fuzz cases with FormatException only', () {
    final rng = Random(20261109);
    const rawBody =
        '#\nname: R\ntype: raw\nfrequency: 38000\n'
        'duty_cycle: 0.330000\ndata: 504 3432 502 483 500 484 510\n';
    final bodies = [
      _parsed('Power', 'Samsung32', '07 00 00 00', '02 00 00 00') +
          _parsed('Vol', 'NECext', 'EE 87 00 00', '5D A0 00 00') +
          _parsed('P', 'Kaseikyo', '80 02 20 01', 'B0 00 00 00'),
      rawBody,
      _parsed('S', 'SIRC20', '10 05 00 00', '7E 00 00 00') +
          _parsed('X', 'RC5X', '1F 00 00 00', '3F 00 00 00'),
    ];
    const alphabet = 'name:typeparsedrawprotocol0123456789ABCDEF #\n\r\t:.-';
    String mutate(String seed) {
      final chars = seed.split('');
      final edits = 1 + rng.nextInt(8);
      for (var e = 0; e < edits && chars.isNotEmpty; e++) {
        final pos = rng.nextInt(chars.length);
        switch (rng.nextInt(4)) {
          case 0:
            chars[pos] = alphabet[rng.nextInt(alphabet.length)];
          case 1:
            chars.removeAt(pos);
          case 2:
            chars.insert(pos, alphabet[rng.nextInt(alphabet.length)]);
          default:
            final len = rng.nextInt(min(30, chars.length - pos)) + 1;
            final copy = chars.sublist(pos, pos + len);
            chars.insertAll(rng.nextInt(chars.length), copy);
        }
      }
      return chars.join();
    }

    const keys = [
      'name', 'type', 'protocol', 'address', 'command', 'frequency', //
      'duty_cycle', 'data', '#', 'x',
    ];
    const values = [
      'parsed',
      'raw',
      'NEC',
      'NECext',
      'RC5X',
      'Kaseikyo',
      'SIRC20',
      'RCA',
      '00 00 00 00',
      'FF FF FF FF',
      '80 02 20 03',
      '38000',
      '0.33',
      '1 2 3',
      '9000 4500 560',
      '',
      '-1',
      '99999999999',
      'é',
      '07 00 00',
    ];
    var parsed = 0;
    var signals = 0;
    for (var i = 0; i < 12000; i++) {
      final String input;
      switch (i % 4) {
        case 0: // whole file mutated, header included
          input = mutate(_header + bodies[rng.nextInt(bodies.length)]);
        case 1: // body mutated
          input = _header + mutate(bodies[rng.nextInt(bodies.length)]);
        case 2: // random fields after a first name
          final b = StringBuffer('${_header}name: K\n');
          for (var n = rng.nextInt(30); n > 0; n--) {
            b.writeln(
              '${keys[rng.nextInt(keys.length)]}: '
              '${values[rng.nextInt(values.length)]}',
            );
          }
          input = b.toString();
        default: // random characters
          input = String.fromCharCodes(
            List.generate(rng.nextInt(200), (_) => rng.nextInt(0x3000)),
          );
      }
      try {
        final r = FlipperIr.parse(input);
        parsed++;
        signals += r.signals.length;
        for (final s in r.signals) {
          final sig = s.code.toSignal(ProtocolRegistry.standard);
          expect(sig.durationsUs.length.isOdd, isTrue);
          expect(sig.durationsUs.every((d) => d > 0), isTrue);
        }
      } on FormatException {
        // expected for many inputs
      }
    }
    expect(parsed, greaterThan(4000));
    expect(signals, greaterThan(1000));
  });
}

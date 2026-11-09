import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:ir_core/ir_core.dart';
import 'package:test/test.dart';

IrSignal _fixture(String path) => IrSignal.fromJson(
  jsonDecode(File('test/fixtures/$path').readAsStringSync()),
);

void main() {
  group('irdb CSV', () {
    test('parses a Samsung TV file into NECx2 codes', () {
      final r = IrdbCsv.parse(
        'functionname,protocol,device,subdevice,function\n'
        'INPUT SOURCE,NECx2,7,7,1\n'
        'POWER,NECx2,7,7,2\n'
        'VOLUME +,NECx2,7,7,7\n',
      );
      expect(r.skipped, isEmpty);
      expect(r.signals.map((s) => s.functionName), [
        'INPUT SOURCE',
        'POWER',
        'VOLUME +',
      ]);
      final power = r.signals[1];
      expect(power.line, 3);
      expect(power.sourceProtocol, 'NECx2');
      expect(power.code.protocol, 'NECx2');
      expect(power.code.params, {'D': 7, 'S': 7, 'F': 2});
      expect(
        power.code.toSignal(ProtocolRegistry.standard).durationsUs,
        _fixture('NECx2/samsung_tv_power.json').durationsUs,
      );
    });

    test('maps NEC names and fills the NEC1 subdevice default', () {
      final r = IrdbCsv.parse(
        'POWER,NEC1,4,-1,8\n'
        'MUTE,nec1,4,251,9\n'
        'VOL+,NEC,4,-1,2\n'
        'X,NEC2,32,223,16\n',
      );
      expect(r.skipped, isEmpty);
      expect(r.signals.map((s) => '${s.code.protocol} ${s.code.params}'), [
        'NEC1 {D: 4, S: 251, F: 8}',
        'NEC1 {D: 4, S: 251, F: 9}',
        'NEC1 {D: 4, S: 251, F: 2}',
        'NEC2 {D: 32, S: 223, F: 16}',
      ]);
      expect(
        r.signals.first.code.toSignal(ProtocolRegistry.standard),
        _fixture('NEC1/lg_tv_power.json'),
      );
    });

    test('maps the other verified protocols', () {
      final r = IrdbCsv.parse(
        'a,Sony12,1,-1,21\n'
        'b,Sony15,164,-1,52\n'
        'c,Sony20,26,73,21\n'
        'd,RC5,0,-1,12\n'
        'e,RC5,0,-1,82\n'
        'f,RC6,0,-1,12\n'
        'g,Panasonic,128,0,61\n'
        'h,JVC,3,-1,23\n'
        'i,Sharp,1,-1,22\n'
        'j,Denon,2,-1,238\n'
        'k,NECx1,8,8,1\n',
      );
      expect(r.skipped, isEmpty, reason: '${r.skipped}');
      expect(r.signals.map((s) => s.code.protocol), [
        'Sony12', 'Sony15', 'Sony20', 'RC5', 'RC5', 'RC6', 'Panasonic', //
        'JVC', 'Sharp', 'Denon', 'NECx1',
      ]);
      expect(r.signals[2].code.params, {'D': 26, 'S': 73, 'F': 21});
      expect(r.signals[4].code.params, {'D': 0, 'F': 82});
      expect(
        r.signals[6].code.toSignal(ProtocolRegistry.standard),
        _fixture('Panasonic/tv_power.json'),
      );
      expect(
        r.signals[5].code.toSignal(ProtocolRegistry.standard),
        _fixture('RC6/tv_power_t0.json'),
      );
    });

    test('handles quoting, odd headers and headerless files', () {
      final r = IrdbCsv.parse(
        'functionname\tprotocol,device,subdevice,function\n'
        '"SP-A, FRONT",Denon,2,-1,238\n'
        'CURSOR "OK",Sony15,186,-1,24\n'
        '0 ?!",NEC1,96,-1,12\n'
        '"say ""hi""",NEC1,1,-1,1\n',
      );
      expect(r.skipped, isEmpty);
      expect(r.signals.map((s) => s.functionName), [
        'SP-A, FRONT',
        'CURSOR "OK"',
        '0 ?!"',
        'say "hi"',
      ]);
      expect(IrdbCsv.parse('1,NEC,1,254,0\r\n').signals.single.code.params, {
        'D': 1,
        'S': 254,
        'F': 0,
      });
      expect(
        IrdbCsv.parse('function,protocol,device,subdevice,function\n').signals,
        isEmpty,
      );
    });

    test('skips unverified or invalid rows with reasons', () {
      final r = IrdbCsv.parse(
        'functionname,protocol,device,subdevice,function\n'
        'a,Pioneer,170,-1,28\n'
        'b,NEC1-f16,4,-1,8\n'
        'c,RC5x,1,-1,1\n'
        'd,JVC{2},3,-1,1\n'
        'e,NECx2,7,-1,2\n'
        'f,NECx1,7,-1,2\n'
        'g,Panasonic,128,-1,61\n'
        'h,Sony12,1,0,21\n'
        'i,Sony12,32,-1,1\n'
        'j,NEC1,256,-1,1\n'
        'k,RC5,0,-1,128\n'
        'l,NEC1,x,-1,1\n'
        'm,NEC1,1,-1\n'
        ',NEC1,1,-1,1\n'
        'n,NEC1,1,-2,1\n'
        'o,NEC1,1,-1,1234567\n',
      );
      expect(r.signals, isEmpty);
      expect(r.skipped.map((s) => s.reason), [
        IrdbSkipReason.unsupportedProtocol,
        IrdbSkipReason.unsupportedProtocol,
        IrdbSkipReason.unsupportedProtocol,
        IrdbSkipReason.unsupportedProtocol,
        IrdbSkipReason.ambiguousDefault,
        IrdbSkipReason.ambiguousDefault,
        IrdbSkipReason.malformedRow,
        IrdbSkipReason.outOfRange,
        IrdbSkipReason.outOfRange,
        IrdbSkipReason.outOfRange,
        IrdbSkipReason.outOfRange,
        IrdbSkipReason.malformedRow,
        IrdbSkipReason.malformedRow,
        IrdbSkipReason.malformedRow,
        IrdbSkipReason.outOfRange,
        IrdbSkipReason.malformedRow,
      ]);
      expect(r.skipped.first.line, 2);
      expect(r.skipped.first.functionName, 'a');
      expect(r.skipped.first.protocol, 'Pioneer');
      expect(r.skipped.first.toString(), contains('Pioneer'));
    });

    test('enforces size and row limits with FormatException', () {
      expect(
        () => IrdbCsv.parse('x' * (IrdbCsv.maxInputLength + 1)),
        throwsFormatException,
      );
      expect(
        () => IrdbCsv.parse('${'a' * IrdbCsv.maxLineLength},NEC1,1,-1,1'),
        throwsFormatException,
      );
      final rows = List.filled(IrdbCsv.maxSignals, 'K,NEC1,1,-1,1').join('\n');
      expect(IrdbCsv.parse(rows).signals, hasLength(10000));
      expect(
        () => IrdbCsv.parse('$rows\nK,NEC1,1,-1,1'),
        throwsFormatException,
      );
    });
  });

  test('survives 12,000 fuzz cases with FormatException only', () {
    final rng = Random(20261110);
    const seed =
        'functionname,protocol,device,subdevice,function\n'
        'POWER,NECx2,7,7,2\n'
        '"SP-A, FRONT",Denon,2,-1,238\n'
        'MENU,Sony20,26,73,21\n'
        'OK,Panasonic,128,0,61\n'
        'UP,RC5,0,-1,82\n';
    const alphabet = 'NECxSonyRC56Panasonic0123456789-,"\n\r\t {}';
    const protocols = [
      'NEC1',
      'NEC',
      'NEC2',
      'NECx1',
      'NECx2',
      'Sony12',
      'Sony15',
      'Sony20',
      'RC5',
      'RC6',
      'Panasonic',
      'JVC',
      'Sharp',
      'Denon',
      'Pioneer',
      'nec1',
      'NEC1-f16',
      '',
    ];
    var parsed = 0;
    var signals = 0;
    for (var i = 0; i < 12000; i++) {
      final String input;
      switch (i % 3) {
        case 0: // mutated valid file
          final chars = seed.split('');
          for (var e = 1 + rng.nextInt(8); e > 0 && chars.isNotEmpty; e--) {
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
        case 1: // random rows with plausible fields
          input = List.generate(rng.nextInt(20), (_) {
            String n() => '${rng.nextInt(600) - 100}';
            return 'K${rng.nextInt(9)},'
                '${protocols[rng.nextInt(protocols.length)]},'
                '${n()},${n()},${n()}';
          }).join('\n');
        default: // random characters
          input = String.fromCharCodes(
            List.generate(rng.nextInt(200), (_) => rng.nextInt(0x3000)),
          );
      }
      try {
        final r = IrdbCsv.parse(input);
        parsed++;
        signals += r.signals.length;
        for (final s in r.signals) {
          final sig = s.code.toSignal(ProtocolRegistry.standard);
          expect(sig.durationsUs.length.isOdd, isTrue);
        }
      } on FormatException {
        // possible for oversized lines only
      }
    }
    expect(parsed, greaterThan(11000));
    expect(signals, greaterThan(5000));
  });
}

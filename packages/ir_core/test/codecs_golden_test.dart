// Golden tests: every codec must reproduce the fixtures generated from the
// published IRP notation by tools/fixtures/irp_oracle.py, and decode them back.
import 'dart:convert';
import 'dart:io';

import 'package:ir_core/ir_core.dart';
import 'package:test/test.dart';

void main() {
  final dir = Directory('test/fixtures');
  final files =
      dir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  test('fixtures exist for every built-in protocol', () {
    final covered = {
      for (final f in files)
        (jsonDecode(f.readAsStringSync()) as Map)['protocol'] as String,
    };
    for (final p in builtInProtocols) {
      expect(covered, contains(p.id), reason: 'no fixture for ${p.id}');
    }
  });

  for (final file in files) {
    final doc = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
    final protocolId = doc['protocol']! as String;
    final params = (doc['params']! as Map).cast<String, int>();
    final expected = IrSignal.fromJson(doc);
    final name = file.uri.pathSegments.skip(2).join('/');

    group(name, () {
      final protocol = ProtocolRegistry.standard.require(protocolId);

      test('encodes exactly to the fixture', () {
        final actual = protocol.encode(params);
        expect(actual.carrierHz, expected.carrierHz);
        expect(actual.durationsUs, expected.durationsUs);
        expect(actual.repeat, expected.repeat);
      });

      test('decodes the fixture to the same parameters', () {
        final decoded = protocol.decode(expected.durationsUs);
        expect(decoded, isNotNull);
        expect(decoded!.isRepeatFrame, isFalse);
        expect(decoded.params, protocol.normalize(params));
        expect(decoded.consumed, expected.durationsUs.length);
      });

      test('registry identifies the fixture as this protocol family', () {
        final decoded = ProtocolRegistry.standard.identify(
          expected.durationsUs,
        );
        expect(decoded, isNotNull);
        // NEC1/NEC2 and NECx1/NECx2 share main frames and differ only in
        // repeats; identification prefers the first-listed variant.
        const sameMainFrame = {'NEC2': 'NEC1', 'NECx1': 'NECx2'};
        expect(decoded!.protocolId, sameMainFrame[protocolId] ?? protocolId);
      });

      test('registry identifies the fixture with its repeats exactly', () {
        // The frame after the gap separates NEC1/NEC2 and NECx1/NECx2.
        final decoded = ProtocolRegistry.standard.identify(
          expected.flatten(repeats: 2),
        );
        expect(decoded, isNotNull);
        expect(decoded!.protocolId, protocolId);
        expect(decoded.params, protocol.normalize(params));
      });

      test('decodes when the frame is followed by its gap and a repeat', () {
        final flat = expected.flatten(repeats: 1);
        final decoded = protocol.decode(flat);
        expect(decoded, isNotNull);
        expect(decoded!.params, protocol.normalize(params));
        expect(decoded.consumed, expected.durationsUs.length);
      });

      test('repeat frame decodes as a repeat or as the same command', () {
        final r = expected.repeat!;
        final decoded = protocol.decode(r.frameUs);
        if (_identicalFrames(r.frameUs, expected.durationsUs)) {
          expect(decoded!.params, protocol.normalize(params));
        } else {
          expect(decoded, isNotNull);
          expect(
            decoded!.isRepeatFrame ||
                _mapEquals(decoded.params, protocol.normalize(params)),
            isTrue,
          );
        }
      });
    });
  }
}

bool _identicalFrames(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _mapEquals(Map<String, int> a, Map<String, int> b) =>
    a.length == b.length && a.entries.every((e) => b[e.key] == e.value);

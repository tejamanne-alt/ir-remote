/// Philips RC5 codec, including the RC5 extended command range (RC5x field
/// bit).
///
/// Written from published protocol descriptions; no code copied.
///
/// Sources:
/// - SB-Projects, "Philips RC-5 Protocol",
///   https://www.sbprojects.net/knowledge/ir/rc5.php — 36 kHz carrier,
///   Manchester coding with 889 us half-bits (1.778 ms bit time), logical 1
///   is space-then-mark and logical 0 is mark-then-space, two start bits
///   (the second inverted into command bit 6 in the extended version), a
///   toggle bit that flips on every new key press, 5 address bits and 6
///   command bits MSB first, 114 ms repetition period.
/// - JP1 / hifi-remote DecodeIR protocol list (IRP notation),
///   http://www.hifi-remote.com/wiki/index.php/DecodeIR:
///   RC5 {36k,msb,889}<1,-1|-1,1>(1,~F:1:6,T:1,D:5,F:6,^114m)+
///
/// Hold-to-repeat resends the same frame with the same toggle value.
library;

import '../signal/ir_signal.dart';
import 'protocol.dart';
import 'timing.dart';

const int _half = 889;
const int _period = 114000;

/// The RC5 protocol.
final class Rc5 extends IrProtocol {
  /// Creates the codec.
  const Rc5();

  @override
  String get id => 'RC5';

  @override
  List<String> get aliases => const ['RC5x', 'RC-5'];

  @override
  int get carrierHz => 36000;

  @override
  List<ParamSpec> get params => const [
    ParamSpec('D', bits: 5, label: 'Address'),
    ParamSpec('F', bits: 7, label: 'Command'),
    ParamSpec('T', bits: 1, defaultValue: 0, label: 'Toggle'),
  ];

  @override
  IrSignal encodeNormalized(Map<String, int> p) {
    final f = p['F']!;
    final bits = <int>[
      1,
      ((f >> 6) & 1) ^ 1,
      p['T']!,
      for (var i = 4; i >= 0; i--) (p['D']! >> i) & 1,
      for (var i = 5; i >= 0; i--) (f >> i) & 1,
    ];
    final b = FrameBuilder();
    for (final bit in bits) {
      if (bit == 1) {
        b
          ..space(_half)
          ..mark(_half);
      } else {
        b
          ..mark(_half)
          ..space(_half);
      }
    }
    final frame = b.build().frame;
    final len = frame.fold(0, (a, b) => a + b);
    return IrSignal(
      carrierHz: carrierHz,
      durationsUs: frame,
      repeat: RepeatSpec(
        frameUs: frame,
        leadInGapUs: _period - len,
        gapUs: _period - len,
      ),
    );
  }

  @override
  DecodedCommand? decode(
    List<int> durationsUs, {
    TimingTolerance tolerance = const TimingTolerance(),
  }) {
    if (durationsUs.isEmpty) return null;
    final expanded = expandToUnits(
      durationsUs,
      0,
      _half,
      tolerance,
      maxUnits: 2,
      maxLevels: 27,
    );
    if (expanded == null) return null;
    // The first start bit's leading space is implicit (absorbed into the
    // preceding gap), and a trailing space may be merged into the next gap.
    final levels = <bool>[false, ...expanded.levels];
    if (levels.length == 27) levels.add(false);
    if (levels.length != 28) return null;
    final bits = <int>[];
    for (var i = 0; i < 28; i += 2) {
      final a = levels[i];
      final b = levels[i + 1];
      if (a == b) return null;
      bits.add(a ? 0 : 1);
    }
    if (bits[0] != 1) return null;
    var d = 0;
    for (var i = 3; i < 8; i++) {
      d = (d << 1) | bits[i];
    }
    var f = 0;
    for (var i = 8; i < 14; i++) {
      f = (f << 1) | bits[i];
    }
    f |= (bits[1] ^ 1) << 6;
    return DecodedCommand(
      protocolId: id,
      params: {'D': d, 'F': f, 'T': bits[2]},
      consumed: _consumedFor(durationsUs, expanded.end),
    );
  }
}

/// A frame always ends with a mark; if expansion stopped after a space the
/// frame's last duration is the one before it.
int _consumedFor(List<int> durations, int end) => end.isOdd ? end : end - 1;

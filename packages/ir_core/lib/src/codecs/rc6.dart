/// Philips RC6 mode 0 codec.
///
/// Written from published protocol descriptions; no code copied.
///
/// Sources:
/// - SB-Projects, "Philips RC-6 Protocol",
///   https://www.sbprojects.net/knowledge/ir/rc6.php — 36 kHz carrier,
///   444 us unit (t), leader of 6t mark and 2t space, Manchester coding where
///   logical 1 is mark-then-space and logical 0 is space-then-mark (the
///   opposite of RC5), start bit 1, three mode bits, a double-width trailer
///   (toggle) bit, then 8 address and 8 command bits MSB first for mode 0.
/// - JP1 / hifi-remote DecodeIR protocol list (IRP notation),
///   http://www.hifi-remote.com/wiki/index.php/DecodeIR:
///   RC6 {36k,444,msb}<-1,1|1,-1>(6,-2,1:1,0:3,<-2,2|2,-2>(T:1),D:8,F:8,^107m)+
///
/// Hold-to-repeat resends the same frame with the same toggle value.
library;

import '../signal/ir_signal.dart';
import 'protocol.dart';
import 'timing.dart';

const int _t = 444;
const int _period = 107000;

/// The RC6 mode 0 protocol.
final class Rc6 extends IrProtocol {
  /// Creates the codec.
  const Rc6();

  @override
  String get id => 'RC6';

  @override
  List<String> get aliases => const ['RC6-0-16', 'RC-6'];

  @override
  int get carrierHz => 36000;

  @override
  List<ParamSpec> get params => const [
    ParamSpec('D', bits: 8, label: 'Address'),
    ParamSpec('F', bits: 8, label: 'Command'),
    ParamSpec('T', bits: 1, defaultValue: 0, label: 'Toggle'),
  ];

  static void _bit(FrameBuilder b, int bit, int width) {
    if (bit == 1) {
      b
        ..mark(width)
        ..space(width);
    } else {
      b
        ..space(width)
        ..mark(width);
    }
  }

  @override
  IrSignal encodeNormalized(Map<String, int> p) {
    final b = FrameBuilder()
      ..mark(6 * _t)
      ..space(2 * _t);
    _bit(b, 1, _t);
    for (var i = 0; i < 3; i++) {
      _bit(b, 0, _t);
    }
    _bit(b, p['T']!, 2 * _t);
    for (var i = 7; i >= 0; i--) {
      _bit(b, (p['D']! >> i) & 1, _t);
    }
    for (var i = 7; i >= 0; i--) {
      _bit(b, (p['F']! >> i) & 1, _t);
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
    final c = DurationCursor(durationsUs, tolerance);
    if (!c.mark(6 * _t) || !c.space(2 * _t)) return null;
    // Bits after the leader: start (2 slots), mode (6), trailer (4), D (16),
    // F (16) = 44 slots of t.
    const slots = 44;
    final expanded = expandToUnits(
      durationsUs,
      c.index,
      _t,
      tolerance,
      maxUnits: 3,
      maxLevels: slots,
    );
    if (expanded == null) return null;
    final levels = [...expanded.levels];
    // A final 0 bit's trailing mark is kept; a final 1 bit's trailing space
    // merges into the gap.
    if (levels.length == slots - 1) levels.add(false);
    if (levels.length != slots) return null;
    var pos = 0;
    int? readBit(int width) {
      final first = levels.sublist(pos, pos + width);
      final second = levels.sublist(pos + width, pos + 2 * width);
      pos += 2 * width;
      final a = first.every((l) => l);
      final aSpace = first.every((l) => !l);
      final b = second.every((l) => l);
      final bSpace = second.every((l) => !l);
      if (a && bSpace) return 1;
      if (aSpace && b) return 0;
      return null;
    }

    if (readBit(1) != 1) return null;
    for (var i = 0; i < 3; i++) {
      if (readBit(1) != 0) return null; // mode 0 only
    }
    final t = readBit(2);
    if (t == null) return null;
    var d = 0;
    for (var i = 0; i < 8; i++) {
      final bit = readBit(1);
      if (bit == null) return null;
      d = (d << 1) | bit;
    }
    var f = 0;
    for (var i = 0; i < 8; i++) {
      final bit = readBit(1);
      if (bit == null) return null;
      f = (f << 1) | bit;
    }
    final end = expanded.end;
    return DecodedCommand(
      protocolId: id,
      params: {'D': d, 'F': f, 'T': t},
      consumed: end.isOdd ? end : end - 1,
    );
  }
}

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
///
/// End of frame: the frame always lasts 52t (23.1 ms) of the 107 ms period,
/// so 83.9 ms of silence follows it. The decoder requires that gap (within
/// the tolerance) or the end of the capture after the frame's last half-bit;
/// more half-bits there mean the frame is the prefix of a longer one.
library;

import '../signal/ir_signal.dart';
import 'protocol.dart';
import 'timing.dart';

const int _t = 444;
const int _period = 107000;

/// Slots of t after the leader: start (2), mode (6), trailer (4), D (16)
/// and F (16).
const int _slots = 44;

/// Bits after the leader: start, three mode bits, trailer, 8 D and 8 F.
const int _bits = 21;

/// Shortest gap after a frame (see the library comment): 83912 us.
const int _minGapUs = _period - (8 + _slots) * _t;

/// Half-bit width of bit [i] after the leader, in t: the trailer (toggle)
/// bit is double width.
int _width(int i) => i == 4 ? 2 : 1;

/// The value of the bit whose first half starts at slot [pos], or `null` if
/// its halves are not one level each, opposite to each other. A 1 is mark
/// then space.
int? _bitAt(List<bool> levels, int pos, int width) {
  final first = levels[pos];
  for (var k = 0; k < 2 * width; k++) {
    if (levels[pos + k] != (k < width ? first : !first)) return null;
  }
  return first ? 1 : 0;
}

/// Whether the complete bits of a partial expansion are valid: biphase
/// halves, a start bit of 1 and mode 0.
bool _viable(List<bool> levels) {
  var pos = 0;
  for (var i = 0; i < _bits; i++) {
    final w = _width(i);
    if (pos + 2 * w > levels.length) return true;
    final bit = _bitAt(levels, pos, w);
    if (bit == null || (i == 0 && bit != 1) || (i >= 1 && i <= 3 && bit != 0)) {
      return false;
    }
    pos += 2 * w;
  }
  return true;
}

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
    return searchUnitExpansions(
      durationsUs,
      c.index,
      _t,
      tolerance,
      maxUnits: 3,
      maxLevels: _slots,
      viable: _viable,
      accept: (expanded, end) =>
          _fromLevels(durationsUs, expanded, end, tolerance),
    );
  }

  DecodedCommand? _fromLevels(
    List<int> durationsUs,
    List<bool> expanded,
    int end,
    TimingTolerance tolerance,
  ) {
    // A final 0 bit's trailing mark is kept; a final 1 bit's trailing space
    // merges into the gap.
    final levels = [...expanded];
    if (levels.length == _slots - 1) levels.add(false);
    if (levels.length != _slots) return null;
    if (!endsAtGap(durationsUs, end, _minGapUs, tolerance)) return null;
    // Start and mode bits were checked by [_viable]; values are MSB first.
    final values = <int>[];
    var pos = 0;
    for (var i = 0; i < _bits; i++) {
      final w = _width(i);
      final bit = _bitAt(levels, pos, w);
      if (bit == null) return null;
      values.add(bit);
      pos += 2 * w;
    }
    var d = 0;
    var f = 0;
    for (var i = 0; i < 8; i++) {
      d = (d << 1) | values[5 + i];
      f = (f << 1) | values[13 + i];
    }
    return DecodedCommand(
      protocolId: id,
      params: {'D': d, 'F': f, 'T': values[4]},
      consumed: end.isOdd ? end : end - 1,
    );
  }
}

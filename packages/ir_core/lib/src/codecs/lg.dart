/// LG 28-bit codec (used by LG air conditioners and some LG appliances).
///
/// LG TVs normally use NEC1 with device 4; this codec is the separate 28-bit
/// protocol.
///
/// Written from published protocol descriptions; no code copied.
///
/// Sources:
/// - Arduino-IRremote (MIT licence), protocol notes at the top of
///   src/ir_LG.hpp,
///   https://github.com/Arduino-IRremote/Arduino-IRremote/blob/master/src/ir_LG.hpp
///   — 38 kHz, MSB first, 8-bit address + 16-bit command + 4-bit checksum
///   (sum of the command's four nibbles, low four bits), 16-unit + 8-unit
///   leader on a 526 us unit, 526 us bit mark, 550 us zero space, 1578 us
///   one space, stop mark, NEC-like repeat (leader mark, 4-unit space,
///   stop) on a 110 ms period.
/// - IRMP documentation, "LGAIR",
///   https://www.mikrocontroller.net/articles/IRMP_-_english#LGAIR — the
///   same frame layout measured from an LG air-conditioner remote.
///
/// End of frame: frames repeat on a 110 ms period, so the gap after a frame
/// is at least 110 ms minus the longest frame: 24 leader units, 28 one bits
/// (526 + 1578 us each) and the stop mark, 72.1 ms, which leaves 37.9 ms.
/// The decoder requires that gap (within the tolerance) or the end of the
/// capture after the stop mark of main and repeat frames; a data bit's
/// space there means the frame is the prefix of a longer one (an NEC frame
/// shares the leader within the tolerance).
library;

import '../signal/ir_signal.dart';
import 'protocol.dart';
import 'timing.dart';

const int _unit = 526;
const int _oneSpace = 1578;
const int _period = 110000;

/// Shortest gap after a frame (see the library comment): 37938 us.
const int _minGapUs = _period - (24 * _unit + 28 * (_unit + _oneSpace) + _unit);
const PulseCoding _coding = PulseCoding(
  zeroMarkUs: _unit,
  zeroSpaceUs: 550,
  oneMarkUs: _unit,
  oneSpaceUs: _oneSpace,
);

/// The LG 28-bit protocol.
final class Lg28 extends IrProtocol {
  /// Creates the codec.
  const Lg28();

  @override
  String get id => 'LG';

  @override
  List<String> get aliases => const ['LG28', 'LGAIR'];

  @override
  int get carrierHz => 38000;

  @override
  List<ParamSpec> get params => const [
    ParamSpec('D', bits: 8, label: 'Address'),
    ParamSpec('F', bits: 16, label: 'Command'),
  ];

  /// The 4-bit checksum of a 16-bit command.
  static int checksum(int command) {
    var sum = 0;
    for (var v = command; v != 0; v >>= 4) {
      sum += v & 0xF;
    }
    return sum & 0xF;
  }

  @override
  IrSignal encodeNormalized(Map<String, int> p) {
    final f = p['F']!;
    final b = FrameBuilder()
      ..mark(16 * _unit)
      ..space(8 * _unit);
    _coding
      ..write(b, p['D']!, 8, msbFirst: true)
      ..write(b, f, 16, msbFirst: true)
      ..write(b, checksum(f), 4, msbFirst: true);
    b.mark(_unit);
    final frame = b.build().frame;
    final len = frame.fold(0, (a, b) => a + b);
    final repeatFrame = [16 * _unit, 4 * _unit, _unit];
    return IrSignal(
      carrierHz: carrierHz,
      durationsUs: frame,
      repeat: RepeatSpec(
        frameUs: repeatFrame,
        leadInGapUs: _period - len,
        gapUs: _period - repeatFrame.fold(0, (a, b) => a + b),
      ),
    );
  }

  @override
  DecodedCommand? decode(
    List<int> durationsUs, {
    TimingTolerance tolerance = const TimingTolerance(),
  }) {
    final c = DurationCursor(durationsUs, tolerance);
    if (!c.mark(16 * _unit)) return null;
    if (c.space(4 * _unit)) {
      if (!c.mark(_unit) || !c.atGap(_minGapUs)) return null;
      return DecodedCommand(
        protocolId: id,
        params: const {},
        consumed: c.index,
        isRepeatFrame: true,
      );
    }
    if (!c.space(8 * _unit)) return null;
    final d = _coding.read(c, 8, msbFirst: true);
    final f = _coding.read(c, 16, msbFirst: true);
    final k = _coding.read(c, 4, msbFirst: true);
    if (d == null || f == null || k == null || k != checksum(f)) return null;
    if (!c.mark(_unit) || !c.atGap(_minGapUs)) return null;
    return DecodedCommand(
      protocolId: id,
      params: {'D': d, 'F': f},
      consumed: c.index,
    );
  }
}

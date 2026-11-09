/// Sharp and Denon codecs (the same 15-bit, two-frame family).
///
/// Written from published protocol descriptions; no code copied.
///
/// Sources:
/// - SB-Projects, "Sharp Protocol",
///   https://www.sbprojects.net/knowledge/ir/sharp.php — 38 kHz carrier,
///   pulse-distance bits with a 320 us mark (0 = 1 ms period, 1 = 2 ms
///   period), 5 address bits, 8 command bits, an expansion bit and a check
///   bit, LSB first; each command is sent twice, the second time with the
///   command and the last two bits inverted, about 40 ms apart.
/// - JP1 / hifi-remote DecodeIR protocol list (IRP notation),
///   http://www.hifi-remote.com/wiki/index.php/DecodeIR:
///   Sharp {38k,264}<1,-3|1,-7>(D:5,F:8,1:2,1,-165,D:5,~F:8,2:2,1,-165)+
///   Denon {38k,264}<1,-3|1,-7>(D:5,F:8,0:2,1,-165,D:5,~F:8,3:2,1,-165)+
///
/// Both halves form one command, so they live in one frame; the 43.6 ms
/// space between them is inside the frame, and the same space follows it.
///
/// End of frame: the IRP ends each half with a stop mark and a 165-unit
/// (43.6 ms) space, so the decoder requires that space (within the
/// tolerance) or the end of the capture after the second stop mark. A data
/// bit's space there means the frame is the prefix of a longer one.
library;

import '../signal/ir_signal.dart';
import 'protocol.dart';
import 'timing.dart';

const int _unit = 264;
const int _gapUnits = 165;
const PulseCoding _coding = PulseCoding(
  zeroMarkUs: _unit,
  zeroSpaceUs: 3 * _unit,
  oneMarkUs: _unit,
  oneSpaceUs: 7 * _unit,
);

/// A Sharp-family protocol with fixed check-bit values per half.
final class SharpFamily extends IrProtocol {
  const SharpFamily._(this.id, this._firstCheck, this._secondCheck);

  /// Sharp.
  static const SharpFamily sharp = SharpFamily._('Sharp', 1, 2);

  /// Denon (also used by some Sharp-derived devices).
  static const SharpFamily denon = SharpFamily._('Denon', 0, 3);

  @override
  final String id;

  final int _firstCheck;
  final int _secondCheck;

  @override
  int get carrierHz => 38000;

  @override
  List<ParamSpec> get params => const [
    ParamSpec('D', bits: 5, label: 'Address'),
    ParamSpec('F', bits: 8, label: 'Command'),
  ];

  @override
  IrSignal encodeNormalized(Map<String, int> p) {
    final d = p['D']!;
    final f = p['F']!;
    final b = FrameBuilder();
    _coding
      ..write(b, d, 5)
      ..write(b, f, 8)
      ..write(b, _firstCheck, 2);
    b
      ..mark(_unit)
      ..space(_gapUnits * _unit);
    _coding
      ..write(b, d, 5)
      ..write(b, 255 - f, 8)
      ..write(b, _secondCheck, 2);
    b.mark(_unit);
    final frame = b.build().frame;
    return IrSignal(
      carrierHz: carrierHz,
      durationsUs: frame,
      repeat: RepeatSpec(
        frameUs: frame,
        leadInGapUs: _gapUnits * _unit,
        gapUs: _gapUnits * _unit,
      ),
    );
  }

  @override
  DecodedCommand? decode(
    List<int> durationsUs, {
    TimingTolerance tolerance = const TimingTolerance(),
  }) {
    final c = DurationCursor(durationsUs, tolerance);
    final d1 = _coding.read(c, 5);
    final f1 = _coding.read(c, 8);
    final k1 = _coding.read(c, 2);
    if (d1 == null || f1 == null || k1 != _firstCheck) return null;
    if (!c.mark(_unit) || !c.space(_gapUnits * _unit)) return null;
    final d2 = _coding.read(c, 5);
    final f2 = _coding.read(c, 8);
    final k2 = _coding.read(c, 2);
    if (d2 != d1 || f2 == null || f2 != 255 - f1 || k2 != _secondCheck) {
      return null;
    }
    if (!c.mark(_unit) || !c.atGap(_gapUnits * _unit)) return null;
    return DecodedCommand(
      protocolId: id,
      params: {'D': d1, 'F': f1},
      consumed: c.index,
    );
  }
}

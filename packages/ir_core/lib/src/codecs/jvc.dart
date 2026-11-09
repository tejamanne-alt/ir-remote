/// JVC codec.
///
/// Written from published protocol descriptions; no code copied.
///
/// Sources:
/// - SB-Projects, "JVC Protocol",
///   https://www.sbprojects.net/knowledge/ir/jvc.php — 38 kHz carrier,
///   8.4 ms + 4.2 ms start burst sent only once, pulse-distance bits
///   (526 us mark; 0 = 1.05 ms period, 1 = 2.1 ms period), 8-bit address and
///   8-bit command LSB first, stop mark, repeats without the start burst.
/// - JP1 / hifi-remote DecodeIR protocol list (IRP notation),
///   http://www.hifi-remote.com/wiki/index.php/DecodeIR:
///   JVC {38k,525}<1,-1|1,-3>(16,-8,(D:8,F:8,1,-45)+)
library;

import '../signal/ir_signal.dart';
import 'protocol.dart';
import 'timing.dart';

const int _unit = 525;
const PulseCoding _coding = PulseCoding(
  zeroMarkUs: _unit,
  zeroSpaceUs: _unit,
  oneMarkUs: _unit,
  oneSpaceUs: 3 * _unit,
);

/// The JVC protocol.
final class Jvc extends IrProtocol {
  /// Creates the codec.
  const Jvc();

  @override
  String get id => 'JVC';

  @override
  int get carrierHz => 38000;

  @override
  List<ParamSpec> get params => const [
    ParamSpec('D', bits: 8, label: 'Address'),
    ParamSpec('F', bits: 8, label: 'Command'),
  ];

  List<int> _body(Map<String, int> p, {required bool header}) {
    final b = FrameBuilder();
    if (header) {
      b
        ..mark(16 * _unit)
        ..space(8 * _unit);
    }
    _coding
      ..write(b, p['D']!, 8)
      ..write(b, p['F']!, 8);
    b.mark(_unit);
    return b.build().frame;
  }

  @override
  IrSignal encodeNormalized(Map<String, int> p) => IrSignal(
    carrierHz: carrierHz,
    durationsUs: _body(p, header: true),
    repeat: RepeatSpec(
      frameUs: _body(p, header: false),
      leadInGapUs: 45 * _unit,
      gapUs: 45 * _unit,
    ),
  );

  @override
  DecodedCommand? decode(
    List<int> durationsUs, {
    TimingTolerance tolerance = const TimingTolerance(),
  }) {
    final c = DurationCursor(durationsUs, tolerance);
    final hasHeader = c.mark(16 * _unit);
    if (hasHeader && !c.space(8 * _unit)) return null;
    final d = _coding.read(c, 8);
    final f = _coding.read(c, 8);
    if (d == null || f == null || !c.mark(_unit)) return null;
    // A headerless frame is only a JVC repeat if nothing else follows within
    // the frame; the 16 data bits plus stop are exactly 33 durations.
    if (!c.atEnd && !tolerance.atLeast(c.peek()!, 8 * _unit)) return null;
    return DecodedCommand(
      protocolId: id,
      params: {'D': d, 'F': f},
      consumed: c.index,
      isRepeatFrame: !hasHeader,
    );
  }
}

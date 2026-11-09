/// Sony SIRC codecs: 12-, 15- and 20-bit variants.
///
/// Written from published protocol descriptions; no code copied.
///
/// Sources:
/// - SB-Projects, "Sony SIRC Protocol",
///   https://www.sbprojects.net/knowledge/ir/sirc.php — 40 kHz carrier,
///   600 us unit, 2.4 ms start mark, pulse-width coding (0 = 600 us mark,
///   1 = 1200 us mark, each followed by a 600 us space), 7-bit command
///   followed by the address, LSB first, 45 ms frame period, 12/15/20-bit
///   versions, and the note that a command is repeated while the key is held.
/// - JP1 / hifi-remote DecodeIR protocol list (IRP notation),
///   http://www.hifi-remote.com/wiki/index.php/DecodeIR:
///   Sony12 {40k,600}<1,-1|2,-1>(4,-1,F:7,D:5,^45m)+
///   Sony15 {40k,600}<1,-1|2,-1>(4,-1,F:7,D:8,^45m)+
///   Sony20 {40k,600}<1,-1|2,-1>(4,-1,F:7,D:5,S:8,^45m)+
///
/// Sony receivers commonly act only after the same frame arrives more than
/// once, so a single tap sends three frames (DECISIONS.md ADR-007).
library;

import '../signal/ir_signal.dart';
import 'protocol.dart';
import 'timing.dart';

const int _unit = 600;
const int _period = 45000;
const PulseCoding _coding = PulseCoding(
  zeroMarkUs: _unit,
  zeroSpaceUs: _unit,
  oneMarkUs: 2 * _unit,
  oneSpaceUs: _unit,
);

/// Sony SIRC with [deviceBits] device bits and an optional 8-bit extension.
final class SonySirc extends IrProtocol {
  const SonySirc._(this.id, this.deviceBits, this.extended);

  /// 12-bit SIRC.
  static const SonySirc sony12 = SonySirc._('Sony12', 5, false);

  /// 15-bit SIRC.
  static const SonySirc sony15 = SonySirc._('Sony15', 8, false);

  /// 20-bit SIRC.
  static const SonySirc sony20 = SonySirc._('Sony20', 5, true);

  /// Frames a single tap sends: the main frame plus two repeats.
  static const int framesPerTap = 3;

  @override
  final String id;

  /// Number of device (address) bits.
  final int deviceBits;

  /// Whether an 8-bit extension (`S`) follows the device.
  final bool extended;

  @override
  List<String> get aliases => switch (id) {
    'Sony12' => const ['SIRC', 'SIRC12', 'Sony'],
    'Sony15' => const ['SIRC15'],
    _ => const ['SIRC20'],
  };

  @override
  int get carrierHz => 40000;

  @override
  List<ParamSpec> get params => [
    ParamSpec('D', bits: deviceBits, label: 'Device'),
    if (extended) const ParamSpec('S', bits: 8, label: 'Extension'),
    const ParamSpec('F', bits: 7, label: 'Function'),
  ];

  @override
  IrSignal encodeNormalized(Map<String, int> p) {
    final b = FrameBuilder()
      ..mark(4 * _unit)
      ..space(_unit);
    _coding
      ..write(b, p['F']!, 7)
      ..write(b, p['D']!, deviceBits);
    if (extended) _coding.write(b, p['S']!, 8);
    final frame = b.build().frame;
    final len = frame.fold(0, (a, b) => a + b);
    return IrSignal(
      carrierHz: carrierHz,
      durationsUs: frame,
      repeat: RepeatSpec(
        frameUs: frame,
        leadInGapUs: _period - len,
        gapUs: _period - len,
        minRepeats: framesPerTap - 1,
      ),
    );
  }

  @override
  DecodedCommand? decode(
    List<int> durationsUs, {
    TimingTolerance tolerance = const TimingTolerance(),
  }) {
    final c = DurationCursor(durationsUs, tolerance);
    if (!c.mark(4 * _unit) || !c.space(_unit)) return null;
    final total = 7 + deviceBits + (extended ? 8 : 0);
    // The frame must end exactly after [total] bits: the next duration is the
    // inter-frame gap (or the end). This is what separates 12/15/20.
    final endIndex = c.index + 2 * total - 1;
    if (endIndex > durationsUs.length) return null;
    if (endIndex < durationsUs.length &&
        !tolerance.atLeast(durationsUs[endIndex], 4 * _unit)) {
      return null;
    }
    final f = _coding.read(c, 7);
    if (f == null) return null;
    final rest = deviceBits + (extended ? 8 : 0);
    final v = _coding.read(c, rest, lastSpaceMayMerge: true);
    if (v == null) return null;
    final d = v & ((1 << deviceBits) - 1);
    return DecodedCommand(
      protocolId: id,
      params: {'D': d, if (extended) 'S': v >> deviceBits, 'F': f},
      consumed: endIndex,
    );
  }
}

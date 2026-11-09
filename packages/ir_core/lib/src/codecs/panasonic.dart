/// Panasonic (Kaseikyo family, Panasonic manufacturer code) codec.
///
/// Written from published protocol descriptions; no code copied.
///
/// Sources:
/// - JP1 / hifi-remote DecodeIR protocol list (IRP notation),
///   http://www.hifi-remote.com/wiki/index.php/DecodeIR:
///   Panasonic {37k,432}<1,-1|1,-3>(8,-4,2:8,32:8,D:8,S:8,F:8,(D^S^F):8,1,-173)+
///   i.e. a 3.456 ms + 1.728 ms leader, pulse-distance bits on a 432 us unit,
///   48 data bits LSB first: the Panasonic manufacturer bytes 0x02 0x20, then
///   device, subdevice, function and their XOR checksum, a stop mark and a
///   173-unit gap.
/// - SB-Projects, "Japanese Format" (Kaseikyo),
///   https://www.sbprojects.net/knowledge/ir/kaseikyo.php — the 48-bit
///   frame layout with a 16-bit manufacturer code and the trailing parity
///   byte.
///
/// End of frame: the IRP ends every frame with a stop mark and a 173-unit
/// (74.7 ms) space, so the decoder requires that space (within the
/// tolerance) or the end of the capture after the stop mark. A data bit's
/// space there means the frame is the prefix of a longer Kaseikyo-style
/// frame (Panasonic and Daikin AC state frames share the leader).
library;

import '../signal/ir_signal.dart';
import 'protocol.dart';
import 'timing.dart';

const int _unit = 432;
const int _gapUnits = 173;
const PulseCoding _coding = PulseCoding(
  zeroMarkUs: _unit,
  zeroSpaceUs: _unit,
  oneMarkUs: _unit,
  oneSpaceUs: 3 * _unit,
);

/// Panasonic Kaseikyo with the 0x2002 manufacturer code.
final class Panasonic extends IrProtocol {
  /// Creates the codec.
  const Panasonic();

  @override
  String get id => 'Panasonic';

  @override
  List<String> get aliases => const ['Kaseikyo', 'Panasonic-Kaseikyo'];

  @override
  int get carrierHz => 37000;

  @override
  List<ParamSpec> get params => const [
    ParamSpec('D', bits: 8, label: 'Device'),
    ParamSpec('S', bits: 8, label: 'Subdevice'),
    ParamSpec('F', bits: 8, label: 'Function'),
  ];

  @override
  IrSignal encodeNormalized(Map<String, int> p) {
    final d = p['D']!;
    final s = p['S']!;
    final f = p['F']!;
    final b = FrameBuilder()
      ..mark(8 * _unit)
      ..space(4 * _unit);
    for (final byte in [2, 32, d, s, f, d ^ s ^ f]) {
      _coding.write(b, byte, 8);
    }
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
    if (!c.mark(8 * _unit) || !c.space(4 * _unit)) return null;
    final bytes = <int>[];
    for (var i = 0; i < 6; i++) {
      final v = _coding.read(c, 8);
      if (v == null) return null;
      bytes.add(v);
    }
    if (!c.mark(_unit) || !c.atGap(_gapUnits * _unit)) return null;
    if (bytes[0] != 2 || bytes[1] != 32) return null;
    if (bytes[5] != (bytes[2] ^ bytes[3] ^ bytes[4])) return null;
    return DecodedCommand(
      protocolId: id,
      params: {'D': bytes[2], 'S': bytes[3], 'F': bytes[4]},
      consumed: c.index,
    );
  }
}

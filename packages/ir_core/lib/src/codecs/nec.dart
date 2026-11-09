/// NEC family codecs: NEC1, NEC1-f16, NEC2, NECx1, NECx2 (Samsung32).
///
/// Written from published protocol descriptions; no code copied.
///
/// Sources:
/// - SB-Projects, "NEC Protocol",
///   https://www.sbprojects.net/knowledge/ir/nec.php — 38 kHz carrier,
///   562.5 us pulse unit, 9 ms + 4.5 ms leader, 0 = 1 unit mark + 1 unit
///   space, 1 = 1 unit mark + 3 units space, address/~address/command/
///   ~command LSB first, stop mark, 9 ms + 2.25 ms + stop repeat code,
///   108 ms frame period, extended (16-bit) addresses.
/// - JP1 / hifi-remote DecodeIR protocol list (IRP notation),
///   http://www.hifi-remote.com/wiki/index.php/DecodeIR — the variants:
///   NEC1  {38.4k,564}<1,-1|1,-3>(16,-8,D:8,S:8,F:8,~F:8,1,^108m,(16,-4,1,^108m)*)
///   NEC1-f16 {38.4k,564}<1,-1|1,-3>(16,-8,D:8,S:8,F:16,1,^108m,(16,-4,1,^108m)*)
///   NEC2  {38.4k,564}<1,-1|1,-3>(16,-8,D:8,S:8,F:8,~F:8,1,^108m)+
///   NECx2 {38.4k,564}<1,-1|1,-3>(8,-8,D:8,S:8,F:8,~F:8,1,^108m)+
/// - IrpTransmogrifier protocol list (IRP notation only), IrpProtocols.xml,
///   https://github.com/bengtmartensson/IrpTransmogrifier, checked
///   2026-11-09, the maintained successor of DecodeIR. It gives the NECx1
///   repeat as (8,-8,~D:1,1,^108m)* (complemented device bit) and S
///   defaulting to 255-D for every variant, NEC and NECx alike.
///
/// NECx2 is the protocol Samsung TVs use (Flipper calls it "Samsung32");
/// Samsung codes carry S explicitly (S = D).
library;

import '../signal/ir_signal.dart';
import 'protocol.dart';
import 'timing.dart';

const int _unit = 564;
const int _carrier = 38400;
const int _period = 108000;
const PulseCoding _coding = PulseCoding(
  zeroMarkUs: _unit,
  zeroSpaceUs: _unit,
  oneMarkUs: _unit,
  oneSpaceUs: 3 * _unit,
);

enum _Header { nec, necx }

enum _Repeat { ditto, fullFrame, necxDitto }

/// Shared implementation for the NEC family.
abstract base class _NecBase extends IrProtocol {
  const _NecBase(this.header, this.repeatKind, {this.f16 = false});

  final _Header header;
  final _Repeat repeatKind;
  final bool f16;

  int get _headerMark => header == _Header.nec ? 16 * _unit : 8 * _unit;

  @override
  int get carrierHz => _carrier;

  @override
  List<ParamSpec> get params => [
    const ParamSpec('D', bits: 8, label: 'Device'),
    ParamSpec(
      'S',
      bits: 8,
      label: 'Subdevice',
      defaultOf: (p) => 255 - p['D']!,
    ),
    ParamSpec('F', bits: f16 ? 16 : 8, label: 'Function'),
  ];

  List<int> _mainFrame(Map<String, int> p) {
    final b = FrameBuilder()
      ..mark(_headerMark)
      ..space(8 * _unit);
    _coding
      ..write(b, p['D']!, 8)
      ..write(b, p['S']!, 8);
    if (f16) {
      _coding.write(b, p['F']!, 16);
    } else {
      _coding
        ..write(b, p['F']!, 8)
        ..write(b, 255 - p['F']!, 8);
    }
    b.mark(_unit);
    return b.build().frame;
  }

  @override
  IrSignal encodeNormalized(Map<String, int> p) {
    final main = _mainFrame(p);
    final mainLen = main.fold(0, (a, b) => a + b);
    final List<int> repeatFrame;
    switch (repeatKind) {
      case _Repeat.ditto:
        repeatFrame = [16 * _unit, 4 * _unit, _unit];
      case _Repeat.necxDitto:
        final b = FrameBuilder()
          ..mark(8 * _unit)
          ..space(8 * _unit);
        _coding.write(b, (p['D']! & 1) ^ 1, 1); // ~D:1
        b.mark(_unit);
        repeatFrame = b.build().frame;
      case _Repeat.fullFrame:
        repeatFrame = main;
    }
    final repLen = repeatFrame.fold(0, (a, b) => a + b);
    return IrSignal(
      carrierHz: _carrier,
      durationsUs: main,
      repeat: RepeatSpec(
        frameUs: repeatFrame,
        leadInGapUs: _period - mainLen,
        gapUs: _period - repLen,
      ),
    );
  }

  @override
  DecodedCommand? decode(
    List<int> durationsUs, {
    TimingTolerance tolerance = const TimingTolerance(),
  }) {
    final c = DurationCursor(durationsUs, tolerance);
    if (!c.mark(_headerMark)) return null;
    // Repeat frames.
    if (repeatKind == _Repeat.ditto && c.space(4 * _unit)) {
      if (!c.mark(_unit)) return null;
      return DecodedCommand(
        protocolId: id,
        params: const {},
        consumed: c.index,
        isRepeatFrame: true,
      );
    }
    if (!c.space(8 * _unit)) return null;
    if (repeatKind == _Repeat.necxDitto) {
      // NECx1 repeat: header, one data bit (D:1), stop mark, then the gap.
      final i = c.index;
      final d = durationsUs;
      if (i + 2 < d.length &&
          tolerance.matches(d[i], _unit) &&
          (tolerance.matches(d[i + 1], _unit) ||
              tolerance.matches(d[i + 1], 3 * _unit)) &&
          tolerance.matches(d[i + 2], _unit) &&
          (i + 3 >= d.length || d[i + 3] > 8 * _unit)) {
        return DecodedCommand(
          protocolId: id,
          params: const {},
          consumed: i + 3,
          isRepeatFrame: true,
        );
      }
    }
    final d = _coding.read(c, 8);
    if (d == null) return null;
    final s = _coding.read(c, 8);
    if (s == null) return null;
    final int f;
    if (f16) {
      final v = _coding.read(c, 16);
      if (v == null) return null;
      f = v;
    } else {
      final f1 = _coding.read(c, 8);
      final f2 = _coding.read(c, 8);
      if (f1 == null || f2 == null || f2 != 255 - f1) return null;
      f = f1;
    }
    if (!c.mark(_unit)) return null;
    return DecodedCommand(
      protocolId: id,
      params: {'D': d, 'S': s, 'F': f},
      consumed: c.index,
    );
  }
}

/// NEC1: the common NEC protocol with a ditto repeat code.
final class Nec1 extends _NecBase {
  /// Creates the codec.
  const Nec1() : super(_Header.nec, _Repeat.ditto);

  @override
  String get id => 'NEC1';

  @override
  List<String> get aliases => const ['NEC'];
}

/// NEC1-f16: NEC1 with a 16-bit function and no inverted check byte.
final class Nec1F16 extends _NecBase {
  /// Creates the codec.
  const Nec1F16() : super(_Header.nec, _Repeat.ditto, f16: true);

  @override
  String get id => 'NEC1-f16';
}

/// NEC2: NEC timing, but the full frame repeats instead of a ditto.
final class Nec2 extends _NecBase {
  /// Creates the codec.
  const Nec2() : super(_Header.nec, _Repeat.fullFrame);

  @override
  String get id => 'NEC2';
}

/// NECx1: short (8-unit) leader with a one-bit ditto repeat.
final class NecX1 extends _NecBase {
  /// Creates the codec.
  const NecX1() : super(_Header.necx, _Repeat.necxDitto);

  @override
  String get id => 'NECx1';
}

/// NECx2: short leader, full-frame repeat. Samsung TVs use this.
final class NecX2 extends _NecBase {
  /// Creates the codec.
  const NecX2() : super(_Header.necx, _Repeat.fullFrame);

  @override
  String get id => 'NECx2';

  @override
  List<String> get aliases => const ['Samsung32', 'Samsung', 'NECx'];
}

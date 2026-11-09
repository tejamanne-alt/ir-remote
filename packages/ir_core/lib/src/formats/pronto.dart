/// Pronto Hex import and export.
///
/// Written from published format descriptions; no code copied.
///
/// Sources:
/// - Philips, "Pronto IR Formats" (format 0000 learned/modulated codes,
///   5000 RC5 and 6000 RC6 preset codes), as reproduced at
///   http://www.hifi-remote.com/infrared/prontoirformats.pdf
/// - Remote Central, "Pronto Hex" format notes by Barry Gordon,
///   http://www.remotecentral.com/features/irdisp2.htm — word 1 is the
///   carrier divisor (frequency = 1 / (N × 0.241246 µs)), word 2 the number
///   of burst pairs in the once sequence, word 3 the number in the repeat
///   sequence, then on/off pairs counted in carrier periods.
library;

import '../codecs/rc5.dart';
import '../codecs/rc6.dart';
import '../signal/ir_signal.dart';

/// Pronto Hex parsing and formatting.
abstract final class Pronto {
  /// Microseconds per Pronto clock tick.
  static const double tickUs = 0.241246;

  /// Longest input accepted, in characters.
  static const int maxInputLength = 64 * 1024;

  /// Lowest carrier a learned (0000) code may imply, in Hz.
  ///
  /// The divisor alone sets the carrier, so a corrupt divisor implies an
  /// absurd one: divisor 1 means 4.1 MHz, with 0.24 us bursts that round to
  /// 0 us. Consumer IR uses about 30 to 60 kHz, plus 455 kHz for Bang &
  /// Olufsen; 10 to 500 kHz (divisors 9 to 414) leaves room around both.
  static const int minCarrierHz = 10000;

  /// Highest carrier a learned (0000) code may imply, in Hz. See
  /// [minCarrierHz].
  static const int maxCarrierHz = 500000;

  /// Parses Pronto Hex text into a signal.
  ///
  /// Supports format 0000 (learned, modulated) and the RC5 (5000) and RC6
  /// (6000) preset formats. Throws [FormatException] for anything else,
  /// including a learned code whose carrier is outside [minCarrierHz] to
  /// [maxCarrierHz] or with a burst shorter than 1 us; it never throws other
  /// error types.
  static IrSignal parse(String text) {
    if (text.length > maxInputLength) {
      throw const FormatException('Pronto text is too long');
    }
    final tokens = text
        .trim()
        .split(RegExp(r'[\s,]+'))
        .where((t) => t.isNotEmpty);
    final words = <int>[];
    for (final t in tokens) {
      if (t.length > 4 || !RegExp(r'^[0-9a-fA-F]+$').hasMatch(t)) {
        throw FormatException('"$t" is not a 4-digit hex word');
      }
      words.add(int.parse(t, radix: 16));
    }
    if (words.length < 4) {
      throw const FormatException('Pronto code needs at least 4 words');
    }
    return switch (words[0]) {
      0x0000 => _parseLearned(words),
      0x5000 => _parseRc5(words),
      0x6000 => _parseRc6(words),
      final t => throw FormatException(
        'Pronto format ${t.toRadixString(16).padLeft(4, '0')} is not supported',
      ),
    };
  }

  static IrSignal _parseLearned(List<int> w) {
    final divisor = w[1];
    if (divisor == 0) throw const FormatException('carrier divisor is zero');
    final once = w[2];
    final rep = w[3];
    if (once == 0 && rep == 0) {
      throw const FormatException('Pronto code has no burst pairs');
    }
    final expected = 4 + 2 * (once + rep);
    if (w.length != expected) {
      throw FormatException(
        'Pronto code has ${w.length} words; header says $expected',
      );
    }
    final unit = divisor * tickUs;
    final carrier = (1e6 / unit).round();
    if (carrier < minCarrierHz || carrier > maxCarrierHz) {
      throw FormatException(
        'carrier divisor ${divisor.toRadixString(16).padLeft(4, '0')} '
        'implies $carrier Hz, outside $minCarrierHz to $maxCarrierHz Hz',
      );
    }
    List<int> seq(int start, int pairs) {
      final out = <int>[];
      for (var i = 0; i < pairs * 2; i++) {
        final v = w[start + i];
        if (v == 0) throw const FormatException('zero-length burst');
        final us = (v * unit).round();
        // Unreachable within the carrier range (a carrier period is at least
        // 2 us), kept so that no burst can reach the model as 0 us.
        if (us < 1) throw const FormatException('burst shorter than 1 us');
        out.add(us);
      }
      return out;
    }

    final onceSeq = seq(4, once);
    final repSeq = seq(4 + once * 2, rep);
    ({List<int> frame, int gap}) split(List<int> s) =>
        (frame: s.sublist(0, s.length - 1), gap: s.last);

    if (once == 0) {
      final r = split(repSeq);
      return IrSignal(
        carrierHz: carrier,
        durationsUs: r.frame,
        repeat: RepeatSpec(frameUs: r.frame, leadInGapUs: r.gap, gapUs: r.gap),
      );
    }
    final m = split(onceSeq);
    if (rep == 0) {
      return IrSignal(
        carrierHz: carrier,
        durationsUs: m.frame,
        repeat: RepeatSpec(frameUs: m.frame, leadInGapUs: m.gap, gapUs: m.gap),
      );
    }
    final r = split(repSeq);
    return IrSignal(
      carrierHz: carrier,
      durationsUs: m.frame,
      repeat: RepeatSpec(frameUs: r.frame, leadInGapUs: m.gap, gapUs: r.gap),
    );
  }

  static (int, int) _presetParams(
    List<int> w,
    String name,
    int maxD,
    int maxF,
  ) {
    if (w.length < 6) {
      throw FormatException('$name preset needs 6 words');
    }
    final d = w[4];
    final f = w[5];
    if (d > maxD || f > maxF) {
      throw FormatException('$name preset values out of range (D=$d, F=$f)');
    }
    return (d, f);
  }

  static IrSignal _parseRc5(List<int> w) {
    final (d, f) = _presetParams(w, 'RC5', 31, 127);
    return const Rc5().encode({'D': d, 'F': f});
  }

  static IrSignal _parseRc6(List<int> w) {
    final (d, f) = _presetParams(w, 'RC6', 255, 255);
    return const Rc6().encode({'D': d, 'F': f});
  }

  /// Formats [signal] as Pronto Hex format 0000.
  ///
  /// The once sequence is the main frame and its lead-in gap; the repeat
  /// sequence is the repeat frame and its gap. Throws [ArgumentError] for a
  /// carrier of zero or below.
  static String format(IrSignal signal) {
    if (signal.carrierHz <= 0) {
      throw ArgumentError.value(signal.carrierHz, 'carrierHz');
    }
    final divisor = (1e6 / (signal.carrierHz * tickUs)).round().clamp(
      1,
      0xFFFF,
    );
    final unit = divisor * tickUs;
    int ticks(int us) => (us / unit).round().clamp(1, 0xFFFF);
    final once = [
      ...signal.durationsUs,
      signal.leadInGapUs,
    ].map(ticks).toList();
    final r = signal.repeat;
    final rep = r == null
        ? <int>[]
        : [...r.frameUs, r.gapUs].map(ticks).toList();
    final words = [
      0,
      divisor,
      once.length ~/ 2,
      rep.length ~/ 2,
      ...once,
      ...rep,
    ];
    return words
        .map((v) => v.toRadixString(16).toUpperCase().padLeft(4, '0'))
        .join(' ');
  }
}

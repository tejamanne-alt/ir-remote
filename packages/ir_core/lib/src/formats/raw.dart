/// Plain raw-duration text, as pasted from capture tools.
library;

import '../signal/ir_signal.dart';

/// Parses and formats raw duration lists.
abstract final class RawFormat {
  /// Longest input accepted, in characters.
  static const int maxInputLength = 64 * 1024;

  /// Most durations accepted in one signal.
  static const int maxDurations = 10000;

  /// Parses durations separated by spaces or commas. Values may carry `+`
  /// (mark) and `-` (space) signs, as IrScrutinizer writes them; when signs
  /// are present they must alternate starting with `+`. A trailing space is
  /// taken as the gap after the frame.
  ///
  /// Throws [FormatException] on malformed input and nothing else.
  static IrSignal parse(String text, {int carrierHz = 38000}) {
    if (text.length > maxInputLength) {
      throw const FormatException('raw text is too long');
    }
    final tokens = text
        .trim()
        .split(RegExp(r'[\s,]+'))
        .where((t) => t.isNotEmpty)
        .toList();
    if (tokens.isEmpty) throw const FormatException('no durations');
    if (tokens.length > maxDurations) {
      throw const FormatException('too many durations');
    }
    final values = <int>[];
    for (var i = 0; i < tokens.length; i++) {
      final t = tokens[i];
      final m = RegExp(r'^([+-]?)(\d{1,7})$').firstMatch(t);
      if (m == null) throw FormatException('"$t" is not a duration');
      final sign = m.group(1)!;
      if (sign.isNotEmpty && (sign == '+') != i.isEven) {
        throw FormatException('duration ${i + 1} has the wrong sign');
      }
      final v = int.parse(m.group(2)!);
      if (v <= 0) throw FormatException('duration ${i + 1} is zero');
      values.add(v);
    }
    if (values.length.isEven) {
      final gap = values.removeLast();
      return IrSignal(
        carrierHz: carrierHz,
        durationsUs: values,
        repeat: RepeatSpec(frameUs: values, leadInGapUs: gap, gapUs: gap),
      );
    }
    return IrSignal(carrierHz: carrierHz, durationsUs: values);
  }

  /// Formats the main frame as signed durations (`+mark -space ...`).
  static String format(IrSignal signal) {
    final d = signal.durationsUs;
    return [for (var i = 0; i < d.length; i++) '${i.isEven ? '+' : '-'}${d[i]}']
        .join(' ');
  }
}

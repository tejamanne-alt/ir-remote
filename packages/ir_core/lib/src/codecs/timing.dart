/// Timing primitives shared by encoders and decoders: tolerance matching, a
/// frame builder that merges adjacent same-level durations, and a cursor for
/// reading captures.
library;

/// Tolerance used when matching captured durations to protocol timings.
///
/// The default is ±25% per duration, as required by the build contract. An
/// optional absolute floor helps with very short pulses that demodulators
/// stretch by a fixed amount.
final class TimingTolerance {
  /// Creates a tolerance.
  const TimingTolerance({this.relative = 0.25, this.absoluteUs = 0})
    : assert(relative >= 0 && relative < 1),
      assert(absoluteUs >= 0);

  /// Allowed relative deviation, for example 0.25 for ±25%.
  final double relative;

  /// Minimum allowed deviation in microseconds.
  final int absoluteUs;

  /// Whether [actualUs] matches [expectedUs].
  bool matches(int actualUs, num expectedUs) {
    final allowed = expectedUs * relative;
    final window = allowed > absoluteUs ? allowed : absoluteUs;
    return (actualUs - expectedUs).abs() <= window;
  }

  /// Whether [actualUs] is at least the lower bound of [expectedUs]. Used for
  /// a frame's final space, which may merge into the inter-frame gap.
  bool atLeast(int actualUs, num expectedUs) {
    final allowed = expectedUs * relative;
    final window = allowed > absoluteUs ? allowed : absoluteUs;
    return actualUs >= expectedUs - window;
  }
}

/// Builds a mark-first duration list, merging adjacent marks or spaces.
final class FrameBuilder {
  final List<int> _d = [];
  bool? _lastIsMark;
  int _leadingSpaceUs = 0;

  /// Appends a mark of [us] microseconds.
  void mark(int us) => _add(us, true);

  /// Appends a space of [us] microseconds.
  void space(int us) => _add(us, false);

  /// Appends a signed duration: positive for a mark, negative for a space.
  void signed(int us) => us >= 0 ? mark(us) : space(-us);

  void _add(int us, bool isMark) {
    if (us <= 0) throw ArgumentError.value(us, 'us', 'must be positive');
    if (_d.isEmpty && !isMark) {
      // A frame starts on its first mark; a leading space (RC5's start bit)
      // is absorbed into the previous gap.
      _leadingSpaceUs += us;
      return;
    }
    if (_lastIsMark == isMark) {
      _d[_d.length - 1] += us;
    } else {
      _d.add(us);
      _lastIsMark = isMark;
    }
  }

  /// Total length of what has been appended, including any leading space.
  int get elapsedUs => _leadingSpaceUs + _d.fold(0, (a, b) => a + b);

  /// Returns the frame (ending with a mark) and the trailing space that was
  /// removed so it can join the inter-frame gap.
  ({List<int> frame, int trailingSpaceUs}) build() {
    if (_d.isEmpty) throw StateError('frame has no marks');
    final frame = [..._d];
    var trailing = 0;
    if (_lastIsMark == false) trailing = frame.removeLast();
    return (frame: frame, trailingSpaceUs: trailing);
  }
}

/// Reads a capture one duration at a time. Even indices are marks.
final class DurationCursor {
  /// Creates a cursor over [durations].
  DurationCursor(this.durations, this.tolerance);

  /// The capture.
  final List<int> durations;

  /// Matching tolerance.
  final TimingTolerance tolerance;

  /// Index of the next duration.
  int index = 0;

  /// Whether every duration has been consumed.
  bool get atEnd => index >= durations.length;

  /// Whether the next duration is a mark.
  bool get atMark => index.isEven;

  /// Consumes a mark matching [us], or returns false without consuming.
  bool mark(num us) {
    if (atEnd || !atMark) return false;
    if (!tolerance.matches(durations[index], us)) return false;
    index++;
    return true;
  }

  /// Consumes a space matching [us], or returns false without consuming.
  bool space(num us) {
    if (atEnd || atMark) return false;
    if (!tolerance.matches(durations[index], us)) return false;
    index++;
    return true;
  }

  /// Consumes a frame-final space of at least [us], which may be merged into
  /// the following gap or absent at the end of the capture.
  bool finalSpace(num us) {
    if (atEnd) return true;
    if (atMark) return false;
    if (!tolerance.atLeast(durations[index], us)) return false;
    index++;
    return true;
  }

  /// Peeks at the next duration, or returns `null` at the end.
  int? peek() => atEnd ? null : durations[index];
}

/// Bit timing for pulse-distance and pulse-width protocols.
final class PulseCoding {
  /// Creates a coding from the mark and space of each bit value.
  const PulseCoding({
    required this.zeroMarkUs,
    required this.zeroSpaceUs,
    required this.oneMarkUs,
    required this.oneSpaceUs,
  });

  /// Mark of a 0 bit.
  final int zeroMarkUs;

  /// Space of a 0 bit.
  final int zeroSpaceUs;

  /// Mark of a 1 bit.
  final int oneMarkUs;

  /// Space of a 1 bit.
  final int oneSpaceUs;

  /// Appends [bits] bits of [value], least or most significant first.
  void write(FrameBuilder b, int value, int bits, {bool msbFirst = false}) {
    for (var i = 0; i < bits; i++) {
      final shift = msbFirst ? bits - 1 - i : i;
      final bit = (value >> shift) & 1;
      if (bit == 1) {
        b
          ..mark(oneMarkUs)
          ..space(oneSpaceUs);
      } else {
        b
          ..mark(zeroMarkUs)
          ..space(zeroSpaceUs);
      }
    }
  }

  /// Reads [bits] bits, or returns `null` on a timing mismatch. When
  /// [lastSpaceMayMerge] is true the final bit's space may be longer than
  /// nominal (merged into a gap) or absent; the bit is then decided by its
  /// mark alone, so the coding must distinguish values by mark length.
  int? read(
    DurationCursor c,
    int bits, {
    bool msbFirst = false,
    bool lastSpaceMayMerge = false,
  }) {
    var value = 0;
    for (var i = 0; i < bits; i++) {
      final isLast = i == bits - 1;
      final m = c.peek();
      if (m == null || !c.atMark) return null;
      final zeroMark = c.tolerance.matches(m, zeroMarkUs);
      final oneMark = c.tolerance.matches(m, oneMarkUs);
      if (!zeroMark && !oneMark) return null;
      c.index++;
      int bit;
      if (isLast && lastSpaceMayMerge) {
        if (zeroMark == oneMark) return null; // undecidable by mark alone
        bit = oneMark ? 1 : 0;
        if (!c.finalSpace(bit == 1 ? oneSpaceUs : zeroSpaceUs)) return null;
      } else {
        final s = c.peek();
        if (s == null) return null;
        final zero = zeroMark && c.tolerance.matches(s, zeroSpaceUs);
        final one = oneMark && c.tolerance.matches(s, oneSpaceUs);
        if (zero == one) return null; // neither, or ambiguous
        bit = one ? 1 : 0;
        c.index++;
      }
      final shift = msbFirst ? bits - 1 - i : i;
      value |= bit << shift;
    }
    return value;
  }
}

/// Expands a capture into half-bit levels for biphase (Manchester) decoding.
///
/// Returns one boolean per [unitUs] slot (true = mark) and the index of the
/// first duration not expanded, or `null` if a mark is not close to a whole
/// number of units between 1 and [maxUnits]. Expansion stops at a space
/// longer than [maxUnits] units (the inter-frame gap) or after
/// [maxLevels] slots; the gap itself is not consumed.
({List<bool> levels, int end})? expandToUnits(
  List<int> durations,
  int start,
  int unitUs,
  TimingTolerance tolerance, {
  int maxUnits = 3,
  int maxLevels = 1 << 16,
}) {
  final levels = <bool>[];
  var i = start;
  for (; i < durations.length && levels.length < maxLevels; i++) {
    final isMark = i.isEven;
    final d = durations[i];
    var matched = 0;
    for (var k = 1; k <= maxUnits; k++) {
      if (tolerance.matches(d, unitUs * k)) {
        matched = k;
        break;
      }
    }
    if (matched == 0) {
      if (!isMark && d > unitUs * maxUnits) break; // trailing gap
      return null;
    }
    for (var k = 0; k < matched; k++) {
      levels.add(isMark);
    }
  }
  return (levels: levels, end: i);
}

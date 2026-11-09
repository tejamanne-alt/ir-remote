/// The IR signal model shared by every codec, format and transport.
library;

/// Describes how a signal repeats while a key is held, and how many repeats a
/// single tap always sends.
///
/// Durations follow the same rule as [IrSignal.durationsUs]: alternating mark
/// and space, starting and ending with a mark. Gaps between frames live here,
/// never inside a frame's duration list.
final class RepeatSpec {
  /// Creates a repeat description.
  RepeatSpec({
    required List<int> frameUs,
    required this.leadInGapUs,
    required this.gapUs,
    this.minRepeats = 0,
  }) : frameUs = List.unmodifiable(frameUs) {
    if (minRepeats < 0) {
      throw ArgumentError.value(minRepeats, 'minRepeats', 'must be >= 0');
    }
    if (leadInGapUs <= 0 || gapUs <= 0) {
      throw ArgumentError(
        'Repeat gaps must be positive '
        '(leadInGapUs=$leadInGapUs, gapUs=$gapUs).',
      );
    }
  }

  /// The frame sent for each repeat. For protocols without a dedicated repeat
  /// frame this equals the main frame.
  final List<int> frameUs;

  /// Space between the end of the main frame and the start of the first
  /// repeat (or the end of transmission when no repeat follows).
  final int leadInGapUs;

  /// Space after each repeat frame.
  final int gapUs;

  /// Repeats always sent after the main frame on a single tap. Sony, for
  /// example, expects the frame at least three times.
  final int minRepeats;

  /// Sum of the repeat frame's durations, excluding gaps.
  int get frameLengthUs => frameUs.fold(0, (a, b) => a + b);

  /// JSON form used for snapshots, backups and fixtures.
  Map<String, Object?> toJson() => {
    'frameUs': frameUs,
    'leadInGapUs': leadInGapUs,
    'gapUs': gapUs,
    if (minRepeats != 0) 'minRepeats': minRepeats,
  };

  /// Parses [toJson] output. Throws [FormatException] on malformed input.
  static RepeatSpec fromJson(Object? json) {
    if (json is! Map) throw const FormatException('repeat must be an object');
    final frame = _intList(json['frameUs'], 'repeat.frameUs');
    final leadIn = _int(json['leadInGapUs'], 'repeat.leadInGapUs');
    final gap = _int(json['gapUs'], 'repeat.gapUs');
    final minRepeats = json['minRepeats'] == null
        ? 0
        : _int(json['minRepeats'], 'repeat.minRepeats');
    if (leadIn <= 0 || gap <= 0 || minRepeats < 0) {
      throw const FormatException('repeat gaps must be positive');
    }
    return RepeatSpec(
      frameUs: frame,
      leadInGapUs: leadIn,
      gapUs: gap,
      minRepeats: minRepeats,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is RepeatSpec &&
      other.leadInGapUs == leadInGapUs &&
      other.gapUs == gapUs &&
      other.minRepeats == minRepeats &&
      _listEquals(other.frameUs, frameUs);

  @override
  int get hashCode =>
      Object.hash(leadInGapUs, gapUs, minRepeats, Object.hashAll(frameUs));

  @override
  String toString() =>
      'RepeatSpec(frame: ${frameUs.length} durations, '
      'leadIn: $leadInGapUs us, gap: $gapUs us, minRepeats: $minRepeats)';
}

/// A modulated IR signal: a carrier frequency plus alternating mark and space
/// durations in whole microseconds.
///
/// [durationsUs] starts and ends with a mark, so its length is odd. The
/// constructor does not validate timing limits; use `SignalValidator` before
/// transmitting, because limits depend on the transport.
final class IrSignal {
  /// Creates a signal. Copies [durationsUs] into an unmodifiable list.
  IrSignal({
    required this.carrierHz,
    required List<int> durationsUs,
    this.repeat,
  }) : durationsUs = List.unmodifiable(durationsUs);

  /// Carrier frequency in Hz, for example 38000.
  final int carrierHz;

  /// Alternating mark and space durations in microseconds, mark first.
  final List<int> durationsUs;

  /// How the signal repeats while held; `null` means the main frame is sent
  /// once per tap with [defaultTrailingGapUs] of silence after it.
  final RepeatSpec? repeat;

  /// Silence assumed after a frame when no [repeat] is defined.
  static const int defaultTrailingGapUs = 100000;

  /// Sum of the main frame's durations, excluding the trailing gap.
  int get frameLengthUs => durationsUs.fold(0, (a, b) => a + b);

  /// Space after the main frame.
  int get leadInGapUs => repeat?.leadInGapUs ?? defaultTrailingGapUs;

  /// Repeats sent on a single tap, as required by the protocol.
  int get minRepeats => repeat?.minRepeats ?? 0;

  /// Returns the frames of one transmission as `(frame, gapAfter)` pairs: the
  /// main frame followed by `max(repeats, minRepeats)` repeat frames.
  List<({List<int> frame, int gapAfterUs})> frames({int repeats = 0}) {
    if (repeats < 0) {
      throw ArgumentError.value(repeats, 'repeats', 'must be >= 0');
    }
    final r = repeat;
    final count = r == null
        ? 0
        : (repeats > r.minRepeats ? repeats : r.minRepeats);
    final result = <({List<int> frame, int gapAfterUs})>[
      (frame: durationsUs, gapAfterUs: leadInGapUs),
    ];
    for (var i = 0; i < count; i++) {
      result.add((frame: r!.frameUs, gapAfterUs: r.gapUs));
    }
    return result;
  }

  /// Flattens the main frame and [repeats] repeat frames into one pattern,
  /// with inter-frame gaps as spaces. The result starts and ends with a mark.
  List<int> flatten({int repeats = 0}) {
    final out = <int>[];
    final fs = frames(repeats: repeats);
    for (var i = 0; i < fs.length; i++) {
      out.addAll(fs[i].frame);
      if (i != fs.length - 1) out.add(fs[i].gapAfterUs);
    }
    return out;
  }

  /// JSON form used for snapshots, backups, fixtures and the inspector.
  Map<String, Object?> toJson() => {
    'carrierHz': carrierHz,
    'durationsUs': durationsUs,
    if (repeat != null) 'repeat': repeat!.toJson(),
  };

  /// Parses [toJson] output. Throws [FormatException] on malformed input; it
  /// never throws other error types for any JSON-decoded value.
  static IrSignal fromJson(Object? json) {
    if (json is! Map) throw const FormatException('signal must be an object');
    final carrier = _int(json['carrierHz'], 'carrierHz');
    final durations = _intList(json['durationsUs'], 'durationsUs');
    final repeatJson = json['repeat'];
    return IrSignal(
      carrierHz: carrier,
      durationsUs: durations,
      repeat: repeatJson == null ? null : RepeatSpec.fromJson(repeatJson),
    );
  }

  /// Signals are equal when carrier, durations and repeat all match.
  @override
  bool operator ==(Object other) =>
      other is IrSignal &&
      other.carrierHz == carrierHz &&
      other.repeat == repeat &&
      _listEquals(other.durationsUs, durationsUs);

  @override
  int get hashCode =>
      Object.hash(carrierHz, repeat, Object.hashAll(durationsUs));

  @override
  String toString() =>
      'IrSignal($carrierHz Hz, ${durationsUs.length} durations, '
      '$frameLengthUs us${repeat == null ? '' : ', $repeat'})';
}

/// Maximum number of durations accepted from any external JSON source.
const int maxJsonDurations = 20000;

int _int(Object? v, String field) {
  if (v is int) return v;
  throw FormatException('$field must be an integer');
}

List<int> _intList(Object? v, String field) {
  if (v is! List) throw FormatException('$field must be a list');
  if (v.length > maxJsonDurations) {
    throw FormatException('$field has more than $maxJsonDurations entries');
  }
  final out = <int>[];
  for (final e in v) {
    if (e is! int) throw FormatException('$field must contain integers only');
    out.add(e);
  }
  return out;
}

bool _listEquals(List<int> a, List<int> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

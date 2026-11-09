/// Lookup of protocols by ID or alias, and protocol identification for
/// learned captures.
library;

import '../signal/ir_signal.dart';
import 'jvc.dart';
import 'lg.dart';
import 'nec.dart';
import 'panasonic.dart';
import 'protocol.dart';
import 'rc5.dart';
import 'rc6.dart';
import 'sharp.dart';
import 'sony.dart';
import 'timing.dart';

/// Every protocol the app can encode, in decode-preference order: when two
/// protocols match the same frame (NEC1 and NEC2 differ only in how they
/// repeat), the earlier one wins.
const List<IrProtocol> builtInProtocols = [
  Nec1(),
  Nec1F16(),
  Nec2(),
  NecX2(),
  NecX1(),
  SonySirc.sony12,
  SonySirc.sony15,
  SonySirc.sony20,
  Rc5(),
  Rc6(),
  Panasonic(),
  Jvc(),
  SharpFamily.sharp,
  SharpFamily.denon,
  Lg28(),
];

/// Thrown when a protocol name is not known.
final class UnknownProtocolException implements Exception {
  /// Creates the exception.
  const UnknownProtocolException(this.name);

  /// The unknown name.
  final String name;

  @override
  String toString() => 'UnknownProtocolException: "$name"';
}

/// Finds protocols by name and identifies captures.
final class ProtocolRegistry {
  /// Creates a registry over [protocols].
  ProtocolRegistry([List<IrProtocol> protocols = builtInProtocols])
    : _protocols = List.unmodifiable(protocols) {
    for (final p in _protocols) {
      for (final name in [p.id, ...p.aliases]) {
        final key = _key(name);
        if (_byName.containsKey(key)) {
          throw StateError('duplicate protocol name "$name"');
        }
        _byName[key] = p;
      }
    }
  }

  /// The default registry with every built-in protocol.
  static final ProtocolRegistry standard = ProtocolRegistry();

  final List<IrProtocol> _protocols;
  final Map<String, IrProtocol> _byName = {};

  /// All protocols in decode-preference order.
  List<IrProtocol> get protocols => _protocols;

  static String _key(String name) =>
      name.toLowerCase().replaceAll(RegExp(r'[\s_]'), '');

  /// Returns the protocol named [name] (ID or alias, case-insensitive), or
  /// `null`.
  IrProtocol? lookup(String name) => _byName[_key(name)];

  /// Returns the protocol named [name] or throws
  /// [UnknownProtocolException].
  IrProtocol require(String name) =>
      lookup(name) ?? (throw UnknownProtocolException(name));

  /// Encodes [params] with the protocol named [protocol].
  IrSignal encode(String protocol, Map<String, int> params) =>
      require(protocol).encode(params);

  /// Identifies the first frame of a capture. Leading noise is not skipped;
  /// learn mode already trims captures to start on a mark.
  ///
  /// Full frames win over repeat-only frames, and among full frames the
  /// earliest protocol in [protocols] wins, with one refinement: protocols
  /// that read the first frame identically (same parameters, same length)
  /// differ only in how they repeat, such as NEC1 (ditto) and NEC2 (full
  /// frame), or NECx2 (full frame) and NECx1 (one-bit repeat). When the
  /// capture goes on past the first frame's gap, the frame that follows
  /// decides: the first of those protocols whose own repeat frame for these
  /// parameters it is wins. With no second frame, or one that none of them
  /// would send, the earliest protocol wins as before.
  DecodedCommand? identify(
    List<int> durationsUs, {
    TimingTolerance tolerance = const TimingTolerance(),
  }) {
    DecodedCommand? repeatOnly;
    final full = <(IrProtocol, DecodedCommand)>[];
    for (final p in _protocols) {
      final r = _tryDecode(p, durationsUs, tolerance);
      if (r == null) continue;
      if (!r.isRepeatFrame) {
        full.add((p, r));
      } else {
        repeatOnly ??= r;
      }
    }
    if (full.isEmpty) return repeatOnly;
    final first = full.first.$2;
    final next = first.consumed + 1; // skip the gap
    if (next < durationsUs.length) {
      final same = [
        for (final f in full)
          if (f.$2.consumed == first.consumed &&
              _sameParams(f.$2.params, first.params))
            f,
      ];
      if (same.length > 1) {
        final rest = durationsUs.sublist(next);
        for (final (p, r) in same) {
          if (_sendsAsRepeat(p, r.params, rest, tolerance)) return r;
        }
      }
    }
    return first;
  }

  static DecodedCommand? _tryDecode(
    IrProtocol p,
    List<int> durationsUs,
    TimingTolerance tolerance,
  ) {
    try {
      return p.decode(durationsUs, tolerance: tolerance);
    } on RangeError {
      return null; // defensive: a decoder must never crash identification
    }
  }

  /// Whether [rest] starts with the repeat frame [p] sends for [params]: a
  /// repeat-only frame when [p] has a dedicated repeat frame, otherwise the
  /// same full frame again.
  static bool _sendsAsRepeat(
    IrProtocol p,
    Map<String, int> params,
    List<int> rest,
    TimingTolerance tolerance,
  ) {
    final signal = p.encodeNormalized(params);
    final repeat = signal.repeat;
    if (repeat == null) return false;
    final r = _tryDecode(p, rest, tolerance);
    if (r == null) return false;
    final dedicated = !_sameDurations(repeat.frameUs, signal.durationsUs);
    return dedicated
        ? r.isRepeatFrame
        : !r.isRepeatFrame && _sameParams(r.params, params);
  }

  static bool _sameParams(Map<String, int> a, Map<String, int> b) =>
      a.length == b.length && a.entries.every((e) => b[e.key] == e.value);

  static bool _sameDurations(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

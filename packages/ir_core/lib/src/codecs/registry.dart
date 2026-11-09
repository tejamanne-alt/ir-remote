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
  /// earliest protocol in [protocols] wins.
  DecodedCommand? identify(
    List<int> durationsUs, {
    TimingTolerance tolerance = const TimingTolerance(),
  }) {
    DecodedCommand? repeatOnly;
    for (final p in _protocols) {
      final DecodedCommand? r;
      try {
        r = p.decode(durationsUs, tolerance: tolerance);
      } on RangeError {
        continue; // defensive: a decoder must never crash identification
      }
      if (r == null) continue;
      if (!r.isRepeatFrame) return r;
      repeatOnly ??= r;
    }
    return repeatOnly;
  }
}

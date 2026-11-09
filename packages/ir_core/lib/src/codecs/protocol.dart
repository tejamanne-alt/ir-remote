/// The protocol (codec) contract and the shared parameter model.
library;

import '../signal/ir_signal.dart';
import 'timing.dart';

/// Thrown when protocol parameters are missing or out of range.
final class ProtocolParamException implements Exception {
  /// Creates the exception.
  const ProtocolParamException(this.protocolId, this.message);

  /// The protocol that rejected the parameters.
  final String protocolId;

  /// What is wrong.
  final String message;

  @override
  String toString() => 'ProtocolParamException($protocolId): $message';
}

/// One named protocol parameter, such as `D` (device) or `F` (function).
final class ParamSpec {
  /// Creates a parameter spec. [defaultOf] computes a default from the other
  /// parameters (for NEC1, `S` defaults to `255 - D`).
  const ParamSpec(
    this.name, {
    required this.bits,
    this.defaultValue,
    this.defaultOf,
    this.label,
  });

  /// Parameter name using IRP conventions: D device, S subdevice, F function,
  /// T toggle.
  final String name;

  /// Width in bits; values range over `0 .. 2^bits - 1`.
  final int bits;

  /// Constant default, if any.
  final int? defaultValue;

  /// Computed default, if any. Takes precedence over [defaultValue].
  final int Function(Map<String, int> params)? defaultOf;

  /// Human label for editors.
  final String? label;

  /// Largest allowed value.
  int get max => (1 << bits) - 1;

  /// Whether the parameter may be omitted.
  bool get hasDefault => defaultValue != null || defaultOf != null;
}

/// A successful decode of a captured signal.
final class DecodedCommand {
  /// Creates a decode result.
  const DecodedCommand({
    required this.protocolId,
    required this.params,
    required this.consumed,
    this.isRepeatFrame = false,
  });

  /// Canonical protocol ID.
  final String protocolId;

  /// Normalized parameters (every parameter present).
  final Map<String, int> params;

  /// Number of durations consumed from the start of the input, including the
  /// frame's final mark.
  final int consumed;

  /// Whether only a protocol repeat frame (for example an NEC ditto) matched.
  final bool isRepeatFrame;

  @override
  String toString() =>
      '$protocolId ${params.entries.map((e) => '${e.key}=${e.value}').join(' ')}'
      '${isRepeatFrame ? ' (repeat)' : ''}';
}

/// A protocol codec: a pure mapping from parameters to [IrSignal] and back.
abstract base class IrProtocol {
  /// Const constructor for subclasses.
  const IrProtocol();

  /// Canonical ID, following DecodeIR/IRP naming (for example `NEC1`).
  String get id;

  /// Other names this protocol goes by in code databases (irdb, Flipper).
  List<String> get aliases => const [];

  /// Nominal carrier frequency in Hz.
  int get carrierHz;

  /// The parameters this protocol takes.
  List<ParamSpec> get params;

  /// Whether the protocol carries a toggle bit `T` that flips per key press.
  bool get usesToggle => params.any((p) => p.name == 'T');

  /// Fills defaults and checks ranges. Unknown parameter names are rejected
  /// so that typos in imported data surface early.
  Map<String, int> normalize(Map<String, int> input) {
    final known = {for (final p in params) p.name};
    for (final k in input.keys) {
      if (!known.contains(k)) {
        throw ProtocolParamException(id, 'unknown parameter "$k"');
      }
    }
    final out = <String, int>{};
    // Constants and explicit values first, then computed defaults, so that a
    // computed default may refer to any explicit parameter.
    for (final p in params) {
      final v = input[p.name];
      if (v != null) {
        out[p.name] = v;
      } else if (p.defaultOf == null && p.defaultValue != null) {
        out[p.name] = p.defaultValue!;
      }
    }
    // Required parameters must be present before computed defaults run,
    // because a computed default may read them.
    for (final p in params) {
      if (!out.containsKey(p.name) && !p.hasDefault) {
        throw ProtocolParamException(id, 'missing parameter "${p.name}"');
      }
    }
    for (final p in params) {
      if (!out.containsKey(p.name) && p.defaultOf != null) {
        out[p.name] = p.defaultOf!(out);
      }
    }
    for (final p in params) {
      final v = out[p.name];
      if (v == null) {
        throw ProtocolParamException(id, 'missing parameter "${p.name}"');
      }
      if (v < 0 || v > p.max) {
        throw ProtocolParamException(
          id,
          'parameter ${p.name}=$v out of range 0..${p.max}',
        );
      }
    }
    return out;
  }

  /// Encodes [params] (normalized first) into a signal with its repeat rule.
  IrSignal encode(Map<String, int> params) =>
      encodeNormalized(normalize(params));

  /// Encodes already-normalized parameters.
  IrSignal encodeNormalized(Map<String, int> p);

  /// Decodes a frame at the start of [durationsUs], or returns `null`.
  /// [durationsUs] alternates mark and space starting with a mark; the final
  /// space of the frame may be missing or merged into a long gap.
  DecodedCommand? decode(
    List<int> durationsUs, {
    TimingTolerance tolerance = const TimingTolerance(),
  });
}

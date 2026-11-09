/// Code sets, their provenance, and the commands that resolve against them.
library;

import '../ac/ac_state.dart';
import '../codecs/protocol.dart';
import '../codecs/registry.dart';
import '../command/keys.dart';
import '../signal/ir_signal.dart';

/// Appliance categories, matching the coverage table in the build contract.
enum DeviceCategory {
  /// Television.
  tv,

  /// Set-top box (satellite, cable, IPTV).
  setTopBox,

  /// Air conditioner (state-frame engine).
  airConditioner,

  /// Fan.
  fan,

  /// Projector.
  projector,

  /// Soundbar or AV receiver.
  soundbar,

  /// Air purifier or cooler.
  airPurifier,

  /// User-defined remote with learned keys.
  generic;

  /// Parses [name] as produced by [Enum.name]; throws [FormatException].
  static DeviceCategory parse(String name) {
    for (final c in values) {
      if (c.name == name) return c;
    }
    throw FormatException('unknown category "$name"');
  }
}

/// Where a code set came from. Gate L1 requires every field.
final class Provenance {
  /// Creates a provenance record.
  const Provenance({
    required this.source,
    required this.sourceUrl,
    required this.sourceCommit,
    required this.license,
    required this.importedAt,
    this.path,
  });

  /// Short source name, for example `flipperdevices/irdb`.
  final String source;

  /// Repository or page URL.
  final String sourceUrl;

  /// Pinned commit (or `user` for user captures).
  final String sourceCommit;

  /// SPDX-style license identifier or licence name.
  final String license;

  /// ISO-8601 date the data was imported.
  final String importedAt;

  /// Path of the file inside the source, if any.
  final String? path;

  /// JSON form.
  Map<String, Object?> toJson() => {
    'source': source,
    'sourceUrl': sourceUrl,
    'sourceCommit': sourceCommit,
    'license': license,
    'importedAt': importedAt,
    if (path != null) 'path': path,
  };

  /// Parses [toJson] output; throws [FormatException] when any required
  /// field is missing or empty (gate L1).
  static Provenance fromJson(Object? json) {
    if (json is! Map) {
      throw const FormatException('provenance must be an object');
    }
    String req(String k) {
      final v = json[k];
      if (v is! String || v.isEmpty) {
        throw FormatException('provenance.$k is required');
      }
      return v;
    }

    final path = json['path'];
    return Provenance(
      source: req('source'),
      sourceUrl: req('sourceUrl'),
      sourceCommit: req('sourceCommit'),
      license: req('license'),
      importedAt: req('importedAt'),
      path: path is String ? path : null,
    );
  }
}

/// How one key of a code set is encoded.
sealed class KeyCode {
  const KeyCode();

  /// Resolves this code to a signal.
  IrSignal toSignal(ProtocolRegistry registry);

  /// JSON form.
  Map<String, Object?> toJson();

  /// Parses [toJson] output; throws [FormatException] on malformed input.
  static KeyCode fromJson(Object? json) {
    if (json is! Map) throw const FormatException('key code must be an object');
    if (json['protocol'] is String) {
      final params = json['params'];
      if (params is! Map) {
        throw const FormatException('params must be an object');
      }
      final out = <String, int>{};
      params.forEach((k, v) {
        if (k is! String || v is! int) {
          throw const FormatException('params must map names to integers');
        }
        out[k] = v;
      });
      return ProtocolKeyCode(json['protocol'] as String, out);
    }
    if (json['signal'] != null) {
      return RawKeyCode(IrSignal.fromJson(json['signal']));
    }
    throw const FormatException('key code needs "protocol" or "signal"');
  }
}

/// A key rendered by a protocol codec from parameters.
final class ProtocolKeyCode extends KeyCode {
  /// Creates a protocol key code.
  const ProtocolKeyCode(this.protocol, this.params);

  /// Protocol ID or alias.
  final String protocol;

  /// Protocol parameters.
  final Map<String, int> params;

  @override
  IrSignal toSignal(ProtocolRegistry registry) =>
      registry.encode(protocol, params);

  @override
  Map<String, Object?> toJson() => {'protocol': protocol, 'params': params};
}

/// A key stored as a raw capture.
final class RawKeyCode extends KeyCode {
  /// Creates a raw key code.
  const RawKeyCode(this.signal);

  /// The stored signal.
  final IrSignal signal;

  @override
  IrSignal toSignal(ProtocolRegistry registry) => signal;

  @override
  Map<String, Object?> toJson() => {'signal': signal.toJson()};
}

/// A set of key codes for one appliance family.
final class CodeSet {
  /// Creates a code set.
  CodeSet({
    required this.id,
    required this.brand,
    required this.category,
    required Map<String, KeyCode> keys,
    required this.provenance,
    this.label,
    this.rank = 0,
  }) : keys = Map.unmodifiable(keys);

  /// Stable ID, unique in the database.
  final String id;

  /// Brand as plain text.
  final String brand;

  /// Appliance category.
  final DeviceCategory category;

  /// Normalized key name to code.
  final Map<String, KeyCode> keys;

  /// Where the data came from.
  final Provenance provenance;

  /// Optional model or remote label from the source.
  final String? label;

  /// Matching order within a brand: lower is tried first.
  final int rank;

  /// The protocol shared by every protocol key, or `null` when mixed/raw.
  String? get protocol {
    String? p;
    for (final k in keys.values) {
      if (k is! ProtocolKeyCode) return null;
      if (p != null && p != k.protocol) return null;
      p = k.protocol;
    }
    return p;
  }

  /// The best key for a power test: discrete on, else toggle.
  String? get powerTestKey => keys.containsKey(Keys.power)
      ? Keys.power
      : (keys.containsKey(Keys.powerOn) ? Keys.powerOn : null);
}

/// A command the user issues, resolved to a signal by `ir_core`.
sealed class IrCommand {
  const IrCommand(this.codeSetId);

  /// The code set (or saved remote snapshot) the command belongs to.
  final String codeSetId;
}

/// Press of one key of a key-code remote.
final class KeyCommand extends IrCommand {
  /// Creates a key command.
  const KeyCommand(super.codeSetId, this.key);

  /// Normalized key name.
  final String key;
}

/// Full-state command for an air conditioner.
final class AcCommand extends IrCommand {
  /// Creates an AC command.
  const AcCommand(super.codeSetId, this.state);

  /// The complete state to send.
  final AcState state;
}

/// Thrown when a command cannot be resolved.
final class CommandResolutionException implements Exception {
  /// Creates the exception.
  const CommandResolutionException(this.message);

  /// What went wrong.
  final String message;

  @override
  String toString() => 'CommandResolutionException: $message';
}

/// Resolves a [KeyCommand] against a code set.
IrSignal resolveKey(CodeSet set, String key, {ProtocolRegistry? registry}) {
  final code = set.keys[key];
  if (code == null) {
    throw CommandResolutionException('code set ${set.id} has no key $key');
  }
  try {
    return code.toSignal(registry ?? ProtocolRegistry.standard);
  } on ProtocolParamException catch (e) {
    throw CommandResolutionException(
      'code set ${set.id} key $key: ${e.message}',
    );
  } on UnknownProtocolException catch (e) {
    throw CommandResolutionException(
      'code set ${set.id} key $key: unknown protocol ${e.name}',
    );
  }
}

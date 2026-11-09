/// App-level domain models built from database rows.
library;

import 'dart:math';

import 'package:ir_core/ir_core.dart';

/// Generates a random 128-bit hex ID.
String newId() {
  final r = Random.secure();
  return List.generate(
    16,
    (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

/// Where a saved key came from.
enum KeySource {
  /// The bundled code database.
  database,

  /// Captured from an original remote.
  learned,

  /// Imported from a file or a pasted code.
  imported,
}

/// One button of a saved remote: a snapshot of the resolved signal.
final class SavedKey {
  /// Creates a saved key.
  const SavedKey({
    required this.key,
    required this.signal,
    required this.source,
    this.toggled,
    this.label,
    this.protocol,
    this.params,
    this.position = 0,
  });

  /// Normalized key name or `custom:<label>`.
  final String key;

  /// Snapshot with toggle bit 0 (or the only snapshot).
  final IrSignal signal;

  /// Snapshot with toggle bit 1, for toggle protocols.
  final IrSignal? toggled;

  /// Origin of the key.
  final KeySource source;

  /// Display label for custom keys.
  final String? label;

  /// Protocol ID when known.
  final String? protocol;

  /// Protocol parameters when known.
  final Map<String, int>? params;

  /// Order in custom layouts.
  final int position;

  /// Whether presses must alternate between [signal] and [toggled].
  bool get hasToggle => toggled != null;
}

/// AC-specific data of a saved remote.
final class AcInfo {
  /// Creates AC info.
  const AcInfo({
    required this.protocolId,
    required this.capsVersion,
    this.lastState,
    this.lastSentAt,
  });

  /// Encoder protocol variant.
  final String protocolId;

  /// Capability descriptor version the remote was saved with.
  final int capsVersion;

  /// The last state sent from this phone (an assumption, never a reading).
  final AcState? lastState;

  /// When [lastState] was sent.
  final DateTime? lastSentAt;
}

/// A saved remote.
final class SavedDevice {
  /// Creates a saved device.
  const SavedDevice({
    required this.id,
    required this.name,
    required this.category,
    required this.createdAt,
    this.brand,
    this.codeSetId,
    this.roomId,
    this.transportId,
    this.favourite = false,
    this.lastUsedAt,
    this.keys = const {},
    this.ac,
  });

  /// Stable ID.
  final String id;

  /// User-visible name.
  final String name;

  /// Appliance category.
  final DeviceCategory category;

  /// Brand as plain text, if known.
  final String? brand;

  /// Code set the snapshot came from, if any.
  final String? codeSetId;

  /// Room, if any.
  final int? roomId;

  /// The user's chosen transport, or `null` for automatic.
  final String? transportId;

  /// Whether the remote is pinned to favourites.
  final bool favourite;

  /// Creation time.
  final DateTime createdAt;

  /// Last time a key was sent.
  final DateTime? lastUsedAt;

  /// Keys by name.
  final Map<String, SavedKey> keys;

  /// AC data for state-frame remotes.
  final AcInfo? ac;

  /// Returns a copy with the given fields replaced.
  SavedDevice copyWith({
    String? name,
    int? roomId,
    bool clearRoom = false,
    String? transportId,
    bool clearTransport = false,
    bool? favourite,
    DateTime? lastUsedAt,
    Map<String, SavedKey>? keys,
    AcInfo? ac,
  }) => SavedDevice(
    id: id,
    name: name ?? this.name,
    category: category,
    createdAt: createdAt,
    brand: brand,
    codeSetId: codeSetId,
    roomId: clearRoom ? null : (roomId ?? this.roomId),
    transportId: clearTransport ? null : (transportId ?? this.transportId),
    favourite: favourite ?? this.favourite,
    lastUsedAt: lastUsedAt ?? this.lastUsedAt,
    keys: keys ?? this.keys,
    ac: ac ?? this.ac,
  );
}

/// A room.
final class Room {
  /// Creates a room.
  const Room({required this.id, required this.name});

  /// Database ID.
  final int id;

  /// Name.
  final String name;
}

/// A hub the user added.
final class HubRecord {
  /// Creates a hub record.
  const HubRecord({
    required this.id,
    required this.kind,
    required this.name,
    required this.host,
    required this.port,
    this.token,
    this.extra = const {},
  });

  /// Transport ID.
  final String id;

  /// Hub family.
  final TransportKind kind;

  /// Display name.
  final String name;

  /// IP address or hostname.
  final String host;

  /// Port.
  final int port;

  /// Pairing token, if paired.
  final String? token;

  /// Kind-specific data.
  final Map<String, Object?> extra;
}

/// Builds a [SavedKey] snapshot from a code set key, including the toggled
/// variant for toggle protocols.
SavedKey snapshotKey(
  String key,
  KeyCode code, {
  ProtocolRegistry? registry,
  int position = 0,
}) {
  final reg = registry ?? ProtocolRegistry.standard;
  switch (code) {
    case ProtocolKeyCode(:final protocol, :final params):
      final p = reg.require(protocol);
      final normalized = p.normalize(params);
      return SavedKey(
        key: key,
        signal: p.encodeNormalized({...normalized, if (p.usesToggle) 'T': 0}),
        toggled: p.usesToggle
            ? p.encodeNormalized({...normalized, 'T': 1})
            : null,
        source: KeySource.database,
        protocol: p.id,
        params: normalized,
        position: position,
      );
    case RawKeyCode(:final signal):
      return SavedKey(
        key: key,
        signal: signal,
        source: KeySource.database,
        position: position,
      );
  }
}

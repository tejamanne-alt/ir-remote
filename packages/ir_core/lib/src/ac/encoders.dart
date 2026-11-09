/// The registry of clean-room AC encoders.
///
/// Gate L2: every encoder here is written from public protocol descriptions
/// and human captures, with a provenance note in its file header. An encoder
/// without human-captured fixtures reports `verified == false` and stays
/// behind a flag that is off in release builds.
///
/// No encoder ships yet: the v1 AC brands and their captures (human action,
/// docs/HARDWARE_TEST_PLAN.md) are pending. AC remotes work through learned
/// buttons until then.
library;

import 'ac_state.dart';

/// Looks up AC encoders by protocol ID.
final class AcEncoderRegistry {
  /// Creates a registry over [encoders].
  AcEncoderRegistry(List<AcEncoder> encoders)
    : _byId = {for (final e in encoders) e.protocolId: e};

  /// The registry of built-in encoders (empty until fixtures exist).
  static final AcEncoderRegistry standard = AcEncoderRegistry(const []);

  final Map<String, AcEncoder> _byId;

  /// Every encoder.
  List<AcEncoder> get all => List.unmodifiable(_byId.values);

  /// Encoders visible to the user: verified ones, plus unverified ones when
  /// [includeUnverified] is set (debug builds only).
  List<AcEncoder> available({required bool includeUnverified}) => [
    for (final e in _byId.values)
      if (e.verified || includeUnverified) e,
  ];

  /// The encoder for [protocolId], or `null`.
  AcEncoder? lookup(String protocolId) => _byId[protocolId];
}

/// Per-device toggle state for protocols with a toggle bit (RC5, RC6).
library;

import 'protocol.dart';

/// Tracks the toggle bit per device for the session.
///
/// A new key press flips the bit; hold-to-repeat keeps it. The state is kept
/// in memory only, as the contract requires ("per-device state for the
/// session").
final class ToggleTracker {
  final Map<String, int> _state = {};

  /// Returns parameters for a new press on [deviceKey]: the toggle flips.
  /// Parameters of protocols without a toggle are returned unchanged.
  Map<String, int> forNewPress(
    String deviceKey,
    IrProtocol protocol,
    Map<String, int> params,
  ) {
    if (!protocol.usesToggle) return params;
    final next = (_state[deviceKey] ?? 1) ^ 1;
    _state[deviceKey] = next;
    return {...params, 'T': next};
  }

  /// Returns parameters for a repeat of the current press: the toggle stays.
  Map<String, int> forRepeat(
    String deviceKey,
    IrProtocol protocol,
    Map<String, int> params,
  ) {
    if (!protocol.usesToggle) return params;
    return {...params, 'T': _state[deviceKey] ?? 0};
  }

  /// Forgets all state (for example when the app restarts a session).
  void reset() => _state.clear();
}

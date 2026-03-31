import 'package:flutter_riverpod/flutter_riverpod.dart';

/// In-memory privacy mode flag.
///
/// Wraps `get_privacy_mode()` / `set_privacy_mode()` from the Rust reputation
/// API.  UI reads and writes go through this provider so widgets can react
/// to changes without polling.
///
/// TODO(bridge): initialise from `get_privacy_mode()` once the bridge is wired
/// (Phase 18+).
final privacyModeProvider = StateNotifierProvider<PrivacyModeNotifier, bool>(
  (ref) => PrivacyModeNotifier(),
);

class PrivacyModeNotifier extends StateNotifier<bool> {
  PrivacyModeNotifier() : super(false);

  /// Set privacy mode to [enabled] and propagate to the Rust layer.
  void setPrivacyMode(bool enabled) {
    state = enabled;
    // TODO(bridge): call set_privacy_mode(enabled) via FFI (Phase 18+).
  }
}

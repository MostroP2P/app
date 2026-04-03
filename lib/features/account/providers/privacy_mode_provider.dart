import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mostro/src/rust/api/reputation.dart' as reputation_api;

/// In-memory privacy mode flag, initialised from the Rust layer on first use.
///
/// Wraps `get_privacy_mode()` / `set_privacy_mode()` from the Rust reputation
/// API.  UI reads and writes go through this provider so widgets can react
/// to changes without polling.
final privacyModeProvider = StateNotifierProvider<PrivacyModeNotifier, bool>(
  (ref) => PrivacyModeNotifier(),
);

class PrivacyModeNotifier extends StateNotifier<bool> {
  PrivacyModeNotifier() : super(false) {
    _init();
  }

  Future<void> _init() async {
    try {
      final current = await reputation_api.getPrivacyMode();
      if (mounted) state = current;
    } catch (_) {}
  }

  /// Set privacy mode to [enabled] and propagate to the Rust layer.
  void setPrivacyMode(bool enabled) {
    state = enabled;
    reputation_api.setPrivacyMode(enabled: enabled).ignore();
  }
}

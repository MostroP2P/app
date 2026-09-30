import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mostro/core/services/identity_service.dart';
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
  /// When [initialValue] is provided the Rust layer is not read, so widget
  /// tests can build the Account screen without the bridge. [setCore] and
  /// [persist] stand in for the Rust flag and the secure-storage copy.
  PrivacyModeNotifier({
    bool? initialValue,
    Future<void> Function(bool enabled)? setCore,
    Future<void> Function(bool enabled)? persist,
  }) : _setCore = setCore ?? _setRustFlag,
       _persist = persist ?? IdentityService.savePrivacyMode,
       super(initialValue ?? false) {
    if (initialValue == null) _init();
  }

  final Future<void> Function(bool enabled) _setCore;
  final Future<void> Function(bool enabled) _persist;

  static Future<void> _setRustFlag(bool enabled) =>
      reputation_api.setPrivacyMode(enabled: enabled);

  Future<void> _init() async {
    try {
      final current = await reputation_api.getPrivacyMode();
      if (mounted) state = current;
    } catch (_) {}
  }

  /// Set privacy mode to [enabled], in the Rust layer and in secure storage.
  ///
  /// The Rust flag lives in memory; the stored copy is what
  /// [IdentityService.loadExisting] hands back at the next launch. Optimistic
  /// update, rolled back on failure; a failed save also puts the Rust flag
  /// back, so the running session and the next launch agree.
  Future<void> setPrivacyMode(bool enabled) async {
    final previous = state;
    state = enabled;
    try {
      await _setCore(enabled);
    } catch (e) {
      if (mounted) state = previous;
      return;
    }
    try {
      await _persist(enabled);
    } catch (e) {
      try {
        await _setCore(previous);
      } catch (_) {}
      if (mounted) state = previous;
    }
  }
}

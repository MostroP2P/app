import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ── SessionState ──────────────────────────────────────────────────────────────

/// Dart-side mirror of the Rust Session struct.
///
/// Holds per-trade key material and peer identity needed by the UI.
/// Populated when a trade session is created; updated as actions arrive.
///
/// The actual ECDH key derivation lives exclusively in Rust (no crypto in
/// Dart). `sharedKey` and `adminSharedKey` are only set once the Rust bridge
/// confirms derivation succeeded.
@immutable
class SessionState {
  const SessionState({
    required this.orderId,
    required this.peerPubkey,
    this.sharedKey,
    this.adminSharedKey,
    this.adminPubkey,
  });

  /// The trade / order this session belongs to.
  final String orderId;

  /// Nostr public key (hex) of the counterparty.
  final String peerPubkey;

  /// ECDH-derived P2P shared key (hex); null until bridge confirms.
  final String? sharedKey;

  /// ECDH-derived admin shared key (hex); null until adminTookDispute.
  final String? adminSharedKey;

  /// Admin's Nostr public key (hex); set when adminTookDispute arrives.
  final String? adminPubkey;

  SessionState copyWith({
    String? peerPubkey,
    String? sharedKey,
    String? adminSharedKey,
    String? adminPubkey,
  }) {
    return SessionState(
      orderId: orderId,
      peerPubkey: peerPubkey ?? this.peerPubkey,
      sharedKey: sharedKey ?? this.sharedKey,
      adminSharedKey: adminSharedKey ?? this.adminSharedKey,
      adminPubkey: adminPubkey ?? this.adminPubkey,
    );
  }
}

// ── SessionNotifier ───────────────────────────────────────────────────────────

/// Manages the Dart-side mirror of per-trade session state.
///
/// When `adminTookDispute` arrives from the Rust bridge:
/// 1. The Rust layer derives the ECDH `adminSharedKey` via
///    `SessionManager::set_admin_shared_key()`.
/// 2. The bridge event propagates here via `setAdminSharedKey()`.
/// 3. `DisputeChatNotifier` observes `adminSharedKeyProvider` and begins
///    subscribing to admin messages once the key is available.
class SessionNotifier extends StateNotifier<SessionState?> {
  SessionNotifier() : super(null);

  /// Called when a trade session is created (taker or creator).
  void setSession(SessionState session) => state = session;

  /// Called when the ECDH P2P shared key is derived by Rust.
  void setSharedKey(String key) {
    final s = state;
    if (s == null) return;
    state = s.copyWith(sharedKey: key);
  }

  /// Called when `adminTookDispute` is received from the Rust bridge.
  ///
  /// Stores the admin pubkey and the Rust-derived ECDH admin shared key so
  /// the dispute chat can begin accepting admin messages.
  void setAdminSharedKey({
    required String adminPubkey,
    required String adminSharedKey,
  }) {
    final s = state;
    if (s == null) return;
    state = s.copyWith(
      adminPubkey: adminPubkey,
      adminSharedKey: adminSharedKey,
    );
  }

  /// Clear the session on trade completion or cancellation.
  void clearSession() => state = null;
}

// ── Providers ─────────────────────────────────────────────────────────────────

/// Source-of-truth provider for the active trade session.
///
/// `null` means no active trade session.
final sessionProvider =
    StateNotifierProvider<SessionNotifier, SessionState?>(
  (_) => SessionNotifier(),
);

/// The ECDH admin shared key for the active session, or `null` if not yet
/// available (admin has not taken the dispute yet).
///
/// Observed by `DisputeChatNotifier` to gate admin message subscriptions.
final adminSharedKeyProvider = Provider<String?>((ref) {
  return ref.watch(sessionProvider)?.adminSharedKey;
});

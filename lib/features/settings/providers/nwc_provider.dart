import 'package:flutter_riverpod/flutter_riverpod.dart';

// Sentinel for copyWith nullable fields.
const _unset = Object();

/// Wallet connection state held in memory.
///
/// `null`  → no wallet connected.
/// non-null → wallet connected; contains pubkey + relay URLs + optional balance.
class NwcWalletState {
  NwcWalletState({
    required this.walletPubkey,
    required List<String> relayUrls,
    this.walletName,
    this.balanceSats,
  }) : relayUrls = List.unmodifiable(relayUrls);

  final String walletPubkey;
  /// Immutable list of NWC relay URLs.
  final List<String> relayUrls;
  final String? walletName;
  final int? balanceSats;

  NwcWalletState copyWith({
    String? walletPubkey,
    List<String>? relayUrls,
    String? walletName,
    Object? balanceSats = _unset,
  }) =>
      NwcWalletState(
        walletPubkey: walletPubkey ?? this.walletPubkey,
        relayUrls: relayUrls ?? this.relayUrls,
        walletName: walletName ?? this.walletName,
        balanceSats: identical(balanceSats, _unset)
            ? this.balanceSats
            : balanceSats as int?,
      );
}

// ── Notifier ───────────────────────────────────────────────────────────────────

class NwcNotifier extends StateNotifier<NwcWalletState?> {
  NwcNotifier() : super(null);

  /// Store wallet state after a successful `connect_wallet` call.
  void setConnected(NwcWalletState wallet) => state = wallet;

  /// Clear wallet state after `disconnect_wallet`.
  void setDisconnected() => state = null;

  /// Update balance from a `get_balance` result.
  void updateBalance(int? sats) {
    final current = state;
    if (current == null) return;
    state = current.copyWith(balanceSats: sats);
  }
}

// ── Providers ─────────────────────────────────────────────────────────────────

/// Wallet connection state. `null` when no wallet is connected.
final nwcProvider =
    StateNotifierProvider<NwcNotifier, NwcWalletState?>((ref) => NwcNotifier());

/// Convenience: `true` when a wallet is connected.
final isWalletConnectedProvider = Provider<bool>(
  (ref) => ref.watch(nwcProvider) != null,
);

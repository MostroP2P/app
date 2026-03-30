import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Wallet connection state held in memory.
///
/// `null`  → no wallet connected.
/// non-null → wallet connected; contains pubkey + relay URLs + optional balance.
class NwcWalletState {
  const NwcWalletState({
    required this.walletPubkey,
    required this.relayUrls,
    this.walletName,
    this.balanceSats,
  });

  final String walletPubkey;
  final List<String> relayUrls;
  final String? walletName;
  final int? balanceSats;
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
    state = NwcWalletState(
      walletPubkey: current.walletPubkey,
      relayUrls: current.relayUrls,
      walletName: current.walletName,
      balanceSats: sats,
    );
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

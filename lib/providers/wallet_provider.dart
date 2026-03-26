/// NWC wallet provider stub.
///
/// Phase 8 T076 replaces this with a real implementation backed by
/// rust/src/api/wallet.rs.
library wallet_provider;

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Placeholder wallet info.
class WalletInfo {
  const WalletInfo({required this.id, required this.alias});

  final String id;
  final String? alias;
}

class WalletNotifier extends AsyncNotifier<WalletInfo?> {
  @override
  Future<WalletInfo?> build() async {
    // Phase 8: load active NWC wallet from Rust.
    return null;
  }
}

final walletProvider =
    AsyncNotifierProvider<WalletNotifier, WalletInfo?>(
  WalletNotifier.new,
);

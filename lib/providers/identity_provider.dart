/// Identity provider stub.
///
/// Phase 3 T031 replaces this with a real implementation backed by the
/// Rust identity API (rust/src/api/identity.rs).
library identity_provider;

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Placeholder identity info.  Phase 3 replaces with contracts/identity.md types.
class IdentityInfo {
  const IdentityInfo({
    required this.publicKey,
    required this.displayName,
  });

  final String publicKey;
  final String? displayName;
}

/// AsyncNotifier stub for identity state.
class IdentityNotifier extends AsyncNotifier<IdentityInfo?> {
  @override
  Future<IdentityInfo?> build() async {
    // Phase 3: call Rust identity API and return current identity or null.
    return null;
  }
}

/// Provider exposing the current [IdentityInfo] or null when no identity exists.
final identityProvider =
    AsyncNotifierProvider<IdentityNotifier, IdentityInfo?>(
  IdentityNotifier.new,
);

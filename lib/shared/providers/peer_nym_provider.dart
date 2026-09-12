import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mostro/src/rust/api/identity.dart' as identity_api;
import 'package:mostro/src/rust/api/types.dart' show NymIdentity;

/// The bridge call behind a seam, so [peerNymProvider] is testable without a
/// live Rust core.
final nymLookupProvider = Provider<Future<NymIdentity> Function(String)>(
  (ref) => (pubkeyHex) => identity_api.getNymIdentity(pubkeyHex: pubkeyHex),
);

/// The pseudonym and avatar seed of a counterparty's trade key, or null when
/// it cannot be derived. Cached per key: the lists ask for the same few
/// counterparties on every rebuild.
final peerNymProvider = FutureProvider.family<NymIdentity?, String>((
  ref,
  pubkeyHex,
) async {
  if (pubkeyHex.isEmpty) return null;
  try {
    return await ref.read(nymLookupProvider)(pubkeyHex);
  } catch (e) {
    debugPrint('[peer_nym] getNymIdentity failed: $e');
    return null;
  }
});

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mostro/src/rust/api/identity.dart' as identity_api;
import 'package:mostro/src/rust/api/reputation_transfer.dart' as rust;

/// The reputation portability calls the screens make, behind one seam so the
/// widget tests never reach the Rust core.
class ReputationApi {
  const ReputationApi();

  rust.ReputationSupportInfo support() => rust.getReputationSupport();

  rust.ReputationAttestationInfo parse(String json) =>
      rust.parseReputationAttestation(json: json);

  Future<rust.ReputationAttestationInfo> import(String json) =>
      rust.importReputation(attestationJson: json);

  Future<rust.ReputationAttestationInfo> export({
    String? destination,
    String? rebind,
  }) => rust.exportReputation(destination: destination, rebind: rebind);

  Future<String> signRebind({
    required String issuer,
    required String newIdentity,
  }) => rust.signReputationRebind(issuer: issuer, newIdentity: newIdentity);

  Future<rust.ReputationAttestationInfo?> pending() =>
      rust.getPendingReputationAttestation();

  /// The user's identity public key, hex, or null without one.
  Future<String?> identity() async =>
      (await identity_api.getIdentity())?.publicKey;
}

final reputationApiProvider = Provider<ReputationApi>(
  (ref) => const ReputationApi(),
);

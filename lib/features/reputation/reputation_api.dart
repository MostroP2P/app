import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:mostro/src/rust/api/identity.dart' as identity_api;
import 'package:mostro/src/rust/api/reputation.dart' as reputation_api;
import 'package:mostro/src/rust/api/reputation_transfer.dart' as rust;

/// The reputation portability calls the screens make, behind one seam so the
/// widget tests never reach the Rust core or the platform.
class ReputationApi {
  const ReputationApi();

  rust.ReputationSupportInfo support() => rust.getReputationSupport();

  rust.ReputationAttestationInfo parse(String json) =>
      rust.parseReputationAttestation(json: json);

  /// Every check an import makes before it is sent: the node imports, the
  /// attestation verifies, names the identity and comes from a trusted key.
  Future<rust.ReputationAttestationInfo> check(String json) =>
      rust.checkReputationImport(attestationJson: json);

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

  /// Whether full privacy mode is on: no identity key to move reputation with.
  Future<bool> privacyMode() => reputation_api.getPrivacyMode();

  /// The user's identity public key, hex, or null without one.
  Future<String?> identity() async =>
      (await identity_api.getIdentity())?.publicKey;

  /// Opens [uri] outside the app; false when nothing could open it.
  Future<bool> openExternal(Uri uri) async {
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }
}

final reputationApiProvider = Provider<ReputationApi>(
  (ref) => const ReputationApi(),
);

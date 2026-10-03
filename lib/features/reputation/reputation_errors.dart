import 'package:mostro/core/daemon_errors.dart';
import 'package:mostro/l10n/app_localizations.dart';

/// User-facing text for a failed reputation export or import: the markers
/// `api::reputation_transfer` raises, then the shared daemon markers
/// (`NoDaemonResponse`, node capability), then [fallback].
String localizedReputationError(
  AppLocalizations l10n,
  Object error, {
  String? fallback,
}) {
  final raw = error.toString();
  final byMarker = <String, String>{
    'PrivacyModeEnabled': l10n.reputationIdentityRequired,
    'ReputationIdentityRequired': l10n.reputationIdentityRequired,
    'ReputationExportUnsupported': l10n.reputationNodeDoesNotExport,
    'ReputationImportUnsupported': l10n.reputationNodeDoesNotImport,
    'NotEligibleForReputationExport': l10n.reputationNotEligible,
    'ReputationBoundToOtherIdentity': l10n.reputationBoundToOtherIdentity,
    'InvalidReputationRebind': l10n.reputationInvalidRebind,
    'ExpiredReputationAttestation': l10n.reputationExpiredAttestation,
    'UntrustedReputationIssuer': l10n.reputationUntrustedIssuer,
    'ReputationIdentityMismatch': l10n.reputationIdentityMismatch,
    'ReputationAlreadyImported': l10n.reputationAlreadyImported,
  };
  for (final entry in byMarker.entries) {
    if (raw.contains(entry.key)) return entry.value;
  }
  return localizedDaemonError(
    l10n,
    error,
    fallback: fallback ?? l10n.reputationInvalidAttestation,
  );
}

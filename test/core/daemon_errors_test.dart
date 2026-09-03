import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/daemon_errors.dart';
import 'package:mostro/l10n/app_localizations_en.dart';

/// PR #252 review (ermeme, supplemental): `UnsupportedNodeProtocol` is
/// reachable from every daemon action, not only create/take, and some Rust
/// wrappers prepend their own context while interpolating the inner error.
/// The central mapper must recognize the marker anywhere in the message so
/// invoice, cancel, fiat-sent, release, dispute, and rating flows all show
/// actionable node-selection guidance instead of a raw marker or an
/// unrelated generic failure.
void main() {
  final l10n = AppLocalizationsEn();

  test('maps the bare unsupported-protocol marker', () {
    expect(
      localizedDaemonError(l10n, 'UnsupportedNodeProtocol:1', fallback: 'x'),
      l10n.nodeProtocolUnsupported,
    );
  });

  test('finds the marker inside the dispute ProtocolError wrapper', () {
    expect(
      localizedDaemonError(
        l10n,
        'ProtocolError: could not build Dispute message: '
        'UnsupportedNodeProtocol:1',
        fallback: 'x',
      ),
      l10n.nodeProtocolUnsupported,
    );
  });

  test('finds the marker inside the rating RateUserDispatchFailed wrapper', () {
    expect(
      localizedDaemonError(
        l10n,
        'RateUserDispatchFailed: UnsupportedNodeProtocol:1',
        fallback: 'x',
      ),
      l10n.nodeProtocolUnsupported,
    );
  });

  test('maps the fail-closed capability-fetch marker', () {
    expect(
      localizedDaemonError(
        l10n,
        'NodeCapabilitiesUnknown: capabilities for node abc not fetched yet',
        fallback: 'x',
      ),
      l10n.nodeCapabilitiesUnknown,
    );
  });

  /// PR #275 review (Catrya): both `DisputeAlreadyOpen` refusals — the record
  /// that already exists and the single-flight guard this PR adds — reach the
  /// UI as the same marker and must not fall through to the generic failure.
  test('maps both DisputeAlreadyOpen refusals', () {
    expect(
      localizedDaemonError(
        l10n,
        'DisputeAlreadyOpen: dispute already exists for trade abc',
        fallback: 'x',
      ),
      l10n.disputeAlreadyOpen,
    );
    expect(
      localizedDaemonError(
        l10n,
        'DisputeAlreadyOpen: an open_dispute for trade abc is already in flight',
        fallback: 'x',
      ),
      l10n.disputeAlreadyOpen,
    );
  });

  /// PR #304 review (Catrya): the InvalidFiatCode preflight marker must map to
  /// its localized string like every other daemon-error marker, both bare and
  /// with the offending code as context.
  test('maps the InvalidFiatCode preflight marker (#175)', () {
    expect(
      localizedDaemonError(l10n, 'InvalidFiatCode', fallback: 'x'),
      l10n.invalidFiatCode,
    );
    expect(
      localizedDaemonError(
        l10n,
        "InvalidFiatCode: 'XYZ' must be exactly 3 uppercase ASCII letters (ISO 4217)",
        fallback: 'x',
      ),
      l10n.invalidFiatCode,
    );
  });

  test('maps timeout and storage markers, and falls back otherwise', () {
    expect(
      localizedDaemonError(l10n, 'NoDaemonResponse', fallback: 'x'),
      l10n.sessionTimeoutMessage,
    );
    expect(
      localizedDaemonError(l10n, 'StorageUnavailable: no db', fallback: 'x'),
      l10n.storageUnavailable,
    );
    expect(
      localizedDaemonError(l10n, 'CantDo: something else', fallback: 'generic'),
      'generic',
    );
  });
}

import 'package:flutter/foundation.dart';

/// Mortsom test-environment switch (see `docs/automation-contract.md`).
///
/// The test environment is enabled only when BOTH conditions hold:
///  1. the app was started through the `lib/main_mortsom.dart` entry point,
///     which is the only caller of [arm]; and
///  2. the build carried `--dart-define=MORTSOM_TEST_ENV=true`.
///
/// The production entry point (`lib/main.dart`) never arms it and the
/// release pipeline never passes the define, so a release build cannot enter
/// the test environment by accident.
///
/// Values passed as Dart defines are visible to build tooling, so only
/// non-secret data travels this way: the daemon public key (already
/// `MOSTRO_PUB_KEY`) and the local relay seed list (`MORTSOM_RELAYS`).
/// Secrets such as mnemonics or NWC URIs are entered through the UI.
class TestEnvironment {
  TestEnvironment._();

  static const bool _defineEnabled =
      bool.fromEnvironment('MORTSOM_TEST_ENV', defaultValue: false);
  static const String _relaysDefine =
      String.fromEnvironment('MORTSOM_RELAYS', defaultValue: '');
  static const String _mostroPubkeyDefine =
      String.fromEnvironment('MOSTRO_PUB_KEY', defaultValue: '');

  static bool _armed = false;

  /// Marks the process as started through the Mortsom entry point.
  ///
  /// Only `lib/main_mortsom.dart` may call this. Arming a release build that
  /// was not compiled with the define is a build mistake; the assertion says
  /// so in debug and profile builds, and [enabled] stays false regardless.
  static void arm() {
    assert(
      !kReleaseMode || _defineEnabled,
      'TestEnvironment.arm() called from a release build without MORTSOM_TEST_ENV',
    );
    _armed = true;
  }

  /// Test-only: clears the armed state between tests.
  @visibleForTesting
  static void disarm() {
    _armed = false;
  }

  /// True when the app runs in the Mortsom test environment.
  static bool get enabled => _armed && _defineEnabled;

  /// Whether the compile-time define is present (regardless of arming).
  @visibleForTesting
  static bool get defineEnabled => _defineEnabled;

  /// Local relay seed list, in the order given by `MORTSOM_RELAYS`
  /// (comma separated). Empty outside the test environment.
  ///
  /// In the test environment this list *replaces* the compiled-in defaults
  /// rather than extending them: a run must fail when its local relay is
  /// unreachable, never quietly succeed against a public one.
  static List<String> get seedRelays =>
      enabled ? parseRelays(_relaysDefine) : const [];

  /// Parses a comma-separated relay list, trimming and dropping blanks.
  @visibleForTesting
  static List<String> parseRelays(String csv) => csv
      .split(',')
      .map((r) => r.trim())
      .where((r) => r.isNotEmpty)
      .toList(growable: false);

  /// Public key of the daemon under test, from `MOSTRO_PUB_KEY`. Null when
  /// the define is absent or malformed, and outside the test environment.
  ///
  /// A run points the app at a locally managed daemon whose key is not the
  /// one compiled in. Without this the first subscriptions would target the
  /// production node, which cannot decrypt them, and the app would look
  /// silently idle until the harness reached settings.
  static String? get mostroPubkey =>
      enabled ? parsePubkey(_mostroPubkeyDefine) : null;

  /// Accepts a 64-character hex key, lowercased; null for anything else.
  ///
  /// A malformed define is a build mistake, and a malformed key reaches the
  /// Rust side as an error at a point where it reads as a bridge failure.
  /// Rejecting it here leaves the compiled default in place instead.
  @visibleForTesting
  static String? parsePubkey(String value) {
    final trimmed = value.trim().toLowerCase();
    return RegExp(r'^[0-9a-f]{64}$').hasMatch(trimmed) ? trimmed : null;
  }

  /// Local test relays are plain `ws://` on a private address (for example
  /// `ws://10.0.2.2:7000`), so the test environment accepts them where the
  /// app otherwise requires `wss://`.
  static bool get allowInsecureRelays => enabled;

  /// Copy of the visible environment marker.
  static const String markerLabel = 'TEST ENVIRONMENT · Mortsom';
}

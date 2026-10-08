@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the logger's init wiring (issue #555).
///
/// `init_app` carries `#[frb(init)]`, but the codegen only scans `crate::api`
/// (`rust_input` in `flutter_rust_bridge.yaml`): move the function anywhere
/// else and it silently drops out of `executeRustInitializers()`. The app then
/// runs with no logger installed — every `log::` record is discarded, nothing
/// reaches the platform console or the Logs screen, and nothing fails.
void main() {
  test('RustLib.init() installs the log bridge', () {
    // Arrange
    final generated = File('lib/src/rust/frb_generated.dart').readAsStringSync();

    // Act
    final body = RegExp(
      r'Future<void> executeRustInitializers\(\) async \{([^}]*)\}',
    ).firstMatch(generated)?.group(1);

    // Assert — the initializer must exist and call the api::logging init.
    expect(body, isNotNull);
    expect(
      body,
      contains('crateApiLoggingInitApp'),
      reason: 'executeRustInitializers() no longer calls init_app: '
          'the log bridge is never installed and the app logs nothing. '
          'Keep init_app inside rust/src/api/ and regenerate.',
    );
  });
}

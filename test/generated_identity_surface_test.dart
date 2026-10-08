@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the identity bridge surface (review of #573).
///
/// The codegen scans every item under `crate::api`, `#[frb(ignore)]` or not.
/// The identity slot and its deletion hooks are crate-internal, and their
/// trait methods could not be generated, so the header of the generated file
/// recorded them as codegen errors. They live outside `crate::api` instead.
void main() {
  test('the generated identity API records no codegen error', () {
    // Arrange
    final generated = File('lib/src/rust/api/identity.dart').readAsStringSync();

    // Act
    final errors = RegExp(
      r'^// These functions have error during generation.*$',
      multiLine: true,
    ).firstMatch(generated)?.group(0);

    // Assert
    expect(
      errors,
      isNull,
      reason:
          'a crate-internal item under rust/src/api/identity.rs reached the '
          'codegen; move it out of crate::api and regenerate',
    );
  });
}

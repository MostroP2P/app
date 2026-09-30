import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('relay pool init cannot abort startup before runApp', () {
    // Arrange: everything in bootstrapAndRun before runApp runs while the
    // native splash is on screen, so an escaping error there leaves the app
    // on it for good. A launch that reuses a live process — Android destroyed
    // the activity, not the process — calls initialize a second time, which
    // used to throw. A static guard, like the one on the identity init order:
    // the bootstrap needs the Rust core and cannot run in a host test.
    final source = File('lib/core/app_bootstrap.dart').readAsStringSync();

    // Act
    final call = source.indexOf('await nostr_api.initialize(');
    final runApp = source.indexOf('runApp(');
    final lastTry = source.lastIndexOf('try {', call);
    final lastStep = source.lastIndexOf('startup.optional(', call);

    // Assert
    expect(call, greaterThan(-1), reason: 'initialize call not found');
    expect(call, lessThan(runApp), reason: 'initialize runs before runApp');
    // Either form catches what initialize throws: a try whose catch is still
    // ahead of the call, or an optional startup step whose body is still open.
    final inTry =
        lastTry > -1 && !source.substring(lastTry, call).contains('} catch');
    final inOptionalStep =
        lastStep > -1 && !source.substring(lastStep, call).contains('});');
    expect(
      inTry || inOptionalStep,
      isTrue,
      reason: 'initialize is neither in a try nor in an optional startup step',
    );
  });
}

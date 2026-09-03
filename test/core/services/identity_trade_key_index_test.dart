import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/services/identity_service.dart';

void main() {
  test('bootstrap subscribes to the index stream before loading the identity',
      () {
    // Loading the identity publishes the reconciled counter when the database
    // is ahead of secure storage, and the Tokio broadcast channel drops a
    // value with no receiver — so subscribing after identity init silently
    // loses exactly the catch-up this mechanism exists for. Nothing at runtime
    // fails when the order is wrong, hence this static guard.
    //
    // Startup lives in app_bootstrap.dart, which both entry points call, so
    // the guard covers the production and the Mortsom test build alike.
    final source = File('lib/core/app_bootstrap.dart').readAsStringSync();

    final subscribe = source.indexOf('onTradeKeyIndexChanged');
    final identityInit = source.indexOf('IdentityService.initialize');

    expect(subscribe, greaterThan(-1), reason: 'subscription call not found');
    expect(identityInit, greaterThan(-1), reason: 'identity init not found');
    expect(
      subscribe,
      lessThan(identityInit),
      reason: 'subscribe to onTradeKeyIndexChanged before IdentityService.initialize',
    );
  });

  group('nextStoredTradeKeyIndex', () {
    test('writes the incoming index when nothing is stored yet', () {
      // Arrange / Act
      final next = IdentityService.nextStoredTradeKeyIndex(null, 21);

      // Assert
      expect(next, 21);
    });

    test('writes the incoming index when it is ahead of the stored one', () {
      expect(IdentityService.nextStoredTradeKeyIndex('21', 22), 22);
    });

    test('skips the write when the stored index already matches', () {
      // Avoids rewriting secure storage on every reconciliation.
      expect(IdentityService.nextStoredTradeKeyIndex('22', 22), isNull);
    });

    test('never moves the counter backwards', () {
      // A lower value would re-derive keys the daemon already registered,
      // which it rejects with InvalidTradeIndex.
      expect(IdentityService.nextStoredTradeKeyIndex('30', 22), isNull);
    });

    test('treats an unparsable stored value as nothing known', () {
      expect(IdentityService.nextStoredTradeKeyIndex('', 5), 5);
      expect(IdentityService.nextStoredTradeKeyIndex('corrupt', 5), 5);
    });
  });
}

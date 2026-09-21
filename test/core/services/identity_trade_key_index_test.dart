import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/services/identity_service.dart';

void main() {
  test('bootstrap subscribes to the index stream before loading the identity', () {
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
      reason:
          'subscribe to onTradeKeyIndexChanged before IdentityService.initialize',
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

  group('StoredIdentity.fromEntries', () {
    const mnemonic =
        'abandon abandon abandon abandon abandon abandon abandon abandon '
        'abandon abandon abandon about';

    test('is null when no mnemonic was ever stored', () {
      expect(StoredIdentity.fromEntries(const {}), isNull);
      expect(
        StoredIdentity.fromEntries(const {'mostro_identity_mnemonic': '  '}),
        isNull,
      );
    });

    test('reads every field from one snapshot of the store', () {
      // Arrange
      const entries = {
        'mostro_identity_mnemonic': ' $mnemonic ',
        'mostro_trade_key_index': '42',
        'mostro_privacy_mode': 'true',
        'mostro_identity_created_at': '1700000000000',
        'someone_elses_key': 'ignored',
      };

      // Act
      final stored = StoredIdentity.fromEntries(entries)!;

      // Assert
      expect(stored.words, hasLength(12));
      expect(stored.words.first, 'abandon');
      expect(stored.tradeKeyIndex, 42);
      expect(stored.privacyMode, isTrue);
      expect(stored.createdAtMillis, 1700000000000);
    });

    test('falls back to the defaults an install without those keys had', () {
      // Arrange / Act
      final stored =
          StoredIdentity.fromEntries(const {
            'mostro_identity_mnemonic': mnemonic,
            'mostro_trade_key_index': 'corrupt',
          })!;

      // Assert
      expect(stored.tradeKeyIndex, 0);
      expect(stored.privacyMode, isFalse);
      expect(stored.createdAtMillis, 0);
    });
  });

  test('the identity is loaded with one read of the secure store', () {
    // Each secure-storage read is a platform round trip — on Linux it parses
    // the whole keyring file — and four in a row were a quarter of the time
    // to the first frame. Nothing at runtime fails if they creep back in.
    final source =
        File('lib/core/services/identity_service.dart').readAsStringSync();
    final start = source.indexOf('static Future<List<String>> initialize()');
    final end = source.indexOf('static Future<List<String>> getMnemonicWords');
    final body = source.substring(start, end);

    expect('_storage.readAll('.allMatches(body), hasLength(1));
    expect('_storage.read('.allMatches(body), isEmpty);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/shared/providers/peer_nym_provider.dart';
import 'package:mostro/src/rust/api/types.dart' show NymIdentity;

import '../../support/provider_harness.dart';

void main() {
  const jaguar = NymIdentity(
    pseudonym: 'used-jaguar',
    iconIndex: 3,
    colorHue: 200,
  );

  test('an empty key has no pseudonym and asks nothing', () async {
    var asked = false;
    final c = createContainer(
      overrides: [
        nymLookupProvider.overrideWithValue((_) async {
          asked = true;
          return jaguar;
        }),
      ],
    );

    expect(await c.read(peerNymProvider('').future), isNull);
    expect(asked, isFalse);
  });

  test('a key resolves to its pseudonym', () async {
    final c = createContainer(
      overrides: [nymLookupProvider.overrideWithValue((_) async => jaguar)],
    );

    expect(await c.read(peerNymProvider('abc').future), jaguar);
  });

  test('a failed lookup reads as unknown rather than an error', () async {
    final c = createContainer(
      overrides: [
        nymLookupProvider.overrideWithValue(
          (_) async => throw StateError('bridge down'),
        ),
      ],
    );

    expect(await c.read(peerNymProvider('abc').future), isNull);
  });
}

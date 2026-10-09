import 'package:flutter_test/flutter_test.dart';

import 'package:mostro/features/cashu/providers/cashu_wallet_provider.dart';
import 'package:mostro/src/rust/api/types.dart';

import '../../../support/provider_harness.dart';

CashuWalletStatus _status({required bool connected, String? mint}) =>
    CashuWalletStatus(
      connected: connected,
      mintUrl: mint,
      balanceSats: BigInt.from(connected ? 500 : 0),
      missingCapabilities: const [],
    );

void main() {
  // What resetIdentityScopedState does: Rust stops serving a wallet built
  // from another identity's seed, but the stream only updates on a wallet
  // change, so the previous user's mint and balance would stay on screen.
  test('an identity change drops the previous wallet status', () async {
    // Arrange — the first subscription sees the previous user's wallet; Rust
    // answers the next one with no wallet bound.
    final answers = [
      _status(connected: true, mint: 'https://mint.example.com'),
      _status(connected: false),
    ];
    var subscriptions = 0;
    final container = createContainer(
      overrides: [
        cashuWalletProvider.overrideWith(
          (ref) => Stream.value(answers[subscriptions++]),
        ),
      ],
    );
    addTearDown(container.dispose);
    final before = await container.read(cashuWalletProvider.future);

    // Act
    container.invalidate(cashuWalletProvider);
    final after = await container.read(cashuWalletProvider.future);

    // Assert
    expect(before.connected, isTrue);
    expect(after.connected, isFalse);
    expect(after.mintUrl, isNull);
  });
}

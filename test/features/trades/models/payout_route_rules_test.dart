import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mostro/features/trades/models/payout_route_rules.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/src/rust/api/types.dart';

import '../../../support/fake_payout.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppLocalizations en;

  setUpAll(() async {
    en = await AppLocalizations.delegate.load(const Locale('en'));
  });

  group('which destination leads', () {
    test('the paid one, even when it is not the latest', () {
      // Arrange
      final route = fakeFailedThenPaidRoute().reversed.toList();

      // Act
      final lead = leadingDestination(route);

      // Assert
      expect(lead?.outcome, PayoutOutcome.paid);
      expect(earlierDestinations(route).single.outcome, PayoutOutcome.failed);
    });

    test('the latest one while nothing is paid, the rest newest first', () {
      final route = [
        fakePayoutDestination(outcome: PayoutOutcome.failed),
        fakePayoutDestination(
          destination: fakePayoutInvoice,
          source: PayoutSource.entered,
          outcome: PayoutOutcome.rejected,
        ),
        fakePayoutDestination(destination: 'bob@example.org'),
      ];

      expect(leadingDestination(route)?.destination, 'bob@example.org');
      expect(earlierDestinations(route).map((d) => d.outcome), [
        PayoutOutcome.rejected,
        PayoutOutcome.failed,
      ]);
    });

    test('none for a trade this device sent nothing for', () {
      expect(leadingDestination(const []), isNull);
      expect(earlierDestinations(const []), isEmpty);
    });
  });

  test('the payout starts at the release, or with news of a payment', () {
    final sent = [fakePayoutDestination()];
    expect(payoutHasStarted(OrderStatus.active, sent), isFalse);
    expect(payoutHasStarted(OrderStatus.fiatSent, sent), isFalse);
    expect(payoutHasStarted(null, sent), isFalse);
    expect(payoutHasStarted(OrderStatus.settledHoldInvoice, sent), isTrue);
    expect(payoutHasStarted(OrderStatus.success, sent), isTrue);
    // A new invoice asked for after a failure: started, whatever the status.
    expect(
      payoutHasStarted(OrderStatus.waitingBuyerInvoice, [
        fakePayoutDestination(outcome: PayoutOutcome.failed),
      ]),
      isTrue,
    );
  });

  test('a failure is unreplaced until another destination is sent', () {
    final failed = fakePayoutDestination(outcome: PayoutOutcome.failed);

    expect(unreplacedFailure([failed]), same(failed));
    expect(unreplacedFailure([failed, fakePayoutDestination()]), isNull);
    expect(unreplacedFailure(const []), isNull);
  });

  group('payoutSourceFor', () {
    test('the wallet when it made the invoice', () {
      expect(
        payoutSourceFor(
          fromWallet: true,
          submitted: fakePayoutInvoice,
          defaultAddress: 'alice@example.com',
        ),
        PayoutSource.nwcWallet,
      );
    });

    test('the default address when sent unchanged, whatever the case', () {
      expect(
        payoutSourceFor(
          fromWallet: false,
          submitted: ' Alice@Example.com ',
          defaultAddress: 'alice@example.com',
        ),
        PayoutSource.defaultLightningAddress,
      );
    });

    test('the default address when saved with its lightning: scheme', () {
      // The core saves `alice@example.com` and the invoice field pre-fills
      // it so, while Settings keeps what was typed (PR #824 review).
      expect(
        payoutSourceFor(
          fromWallet: false,
          submitted: 'alice@example.com',
          defaultAddress: 'lightning:alice@example.com',
        ),
        PayoutSource.defaultLightningAddress,
      );
    });

    test('the buyer for anything else', () {
      expect(
        payoutSourceFor(
          fromWallet: false,
          submitted: 'bob@example.org',
          defaultAddress: 'alice@example.com',
        ),
        PayoutSource.entered,
      );
      expect(
        payoutSourceFor(fromWallet: false, submitted: fakePayoutInvoice),
        PayoutSource.entered,
      );
    });
  });

  test('an invoice and a hash are shortened, never shown whole', () {
    expect(shortInvoice(fakePayoutInvoice), 'lnbc16770n1p…38fda3h7');
    expect(shortInvoice('lnbc1short'), 'lnbc1short');
    expect(
      shortPaymentHash(
        '0001020304050607080900010203040506070809000102030405060708090102',
      ),
      '00010203…08090102',
    );
  });

  test('a destination says where the sats go', () {
    expect(destinationLabel(en, fakePayoutDestination()), 'alice@example.com');
    expect(
      destinationLabel(
        en,
        fakePayoutDestination(
          destination: fakePayoutInvoice,
          source: PayoutSource.nwcWallet,
          walletName: 'Alby',
        ),
      ),
      'Alby (NWC)',
    );
    expect(
      destinationLabel(
        en,
        fakePayoutDestination(
          destination: fakePayoutInvoice,
          source: PayoutSource.nwcWallet,
        ),
      ),
      'Your NWC wallet',
    );
    expect(
      destinationLabel(
        en,
        fakePayoutDestination(
          destination: fakePayoutInvoice,
          source: PayoutSource.entered,
        ),
      ),
      'Invoice ${shortInvoice(fakePayoutInvoice)}',
    );
  });

  test('an outcome reads in words and as a machine word', () {
    expect(
      outcomeLabel(
        en,
        fakePayoutDestination(outcome: PayoutOutcome.failed, attempts: 3),
      ),
      'Failed after 3 attempts',
    );
    expect(
      outcomeLabel(en, fakePayoutDestination(outcome: PayoutOutcome.failed)),
      'Failed',
    );
    expect(PayoutOutcome.values.map(outcomeMachineName), [
      'submitted',
      'retrying',
      'failed',
      'rejected',
      'replaced',
      'paid',
      'maybe-paid',
    ]);
  });

  group('refusalOf (#941)', () {
    test('finds the refusal of the destination sent', () {
      // Arrange
      final route = [
        fakePayoutDestination(outcome: PayoutOutcome.failed, attempts: 2),
        fakePayoutDestination(
          destination: fakePayoutInvoice,
          source: PayoutSource.entered,
          outcome: PayoutOutcome.rejected,
          rejection: 'NotAllowedByStatus',
        ),
      ];

      // Act
      final refused = refusalOf(route, fakePayoutInvoice);

      // Assert
      expect(refused?.rejection, 'NotAllowedByStatus');
    });

    test('nothing while the destination sent is still waiting', () {
      // Arrange: the same invoice was refused once, then sent again.
      final route = [
        fakePayoutDestination(
          destination: fakePayoutInvoice,
          outcome: PayoutOutcome.rejected,
          rejection: 'NotAllowedByStatus',
        ),
        fakePayoutDestination(destination: fakePayoutInvoice),
      ];

      // Act / Assert: only the newest submission is the one waited on.
      expect(refusalOf(route, fakePayoutInvoice), isNull);
    });

    test('nothing for a refusal of another destination', () {
      final route = [
        fakePayoutDestination(
          outcome: PayoutOutcome.rejected,
          rejection: 'InvalidInvoice',
        ),
      ];

      expect(refusalOf(route, fakePayoutInvoice), isNull);
      expect(refusalOf(const [], fakePayoutInvoice), isNull);
      expect(refusalOf(route, ''), isNull);
    });

    test('an address matches as typed, case aside', () {
      final route = [
        fakePayoutDestination(
          destination: 'alice@example.com',
          outcome: PayoutOutcome.rejected,
          rejection: 'InvalidInvoice',
        ),
      ];

      expect(refusalOf(route, 'lightning:Alice@Example.com'), isNotNull);
    });
  });
}

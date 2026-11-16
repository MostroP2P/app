import 'package:mostro/src/rust/api/types.dart';

/// A BOLT11 invoice as the payout record keeps it; the content only matters
/// where a test reads it back.
const fakePayoutInvoice =
    'lnbc16770n1p4dq278dqqnp4qwpn62g900yjkkkaafl2ttjyanmc78m7gzr3v338fda3h7';

/// One payout destination (#823), sent at 1000 and still open unless told.
PayoutDestination fakePayoutDestination({
  String destination = 'alice@example.com',
  bool? isLightningAddress,
  PayoutSource source = PayoutSource.defaultLightningAddress,
  String? walletName,
  int? amountSats = 1677,
  String? paymentHash,
  PayoutOutcome outcome = PayoutOutcome.submitted,
  int? attempts,
  String? rejection,
}) => PayoutDestination(
  destination: destination,
  isLightningAddress: isLightningAddress ?? destination.contains('@'),
  source: source,
  walletName: walletName,
  submittedAt: 1000,
  amountSats: amountSats == null ? null : BigInt.from(amountSats),
  paymentHash: paymentHash,
  outcome: outcome,
  outcomeAt: outcome == PayoutOutcome.submitted ? null : 2000,
  attempts: attempts,
  rejection: rejection,
);

/// The staging trade behind #823: the default address failed three times,
/// the NWC wallet's invoice was paid.
List<PayoutDestination> fakeFailedThenPaidRoute() => [
  fakePayoutDestination(outcome: PayoutOutcome.failed, attempts: 3),
  fakePayoutDestination(
    destination: fakePayoutInvoice,
    source: PayoutSource.nwcWallet,
    walletName: 'Alby',
    paymentHash:
        '0001020304050607080900010203040506070809000102030405060708090102',
    outcome: PayoutOutcome.paid,
  ),
];

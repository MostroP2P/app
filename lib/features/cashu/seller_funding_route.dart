import 'package:mostro/core/app_routes.dart';

/// Where a seller funds a trade waiting on it (`waitingPayment`): the Cashu
/// escrow on a node that settles over Cashu, the hold invoice otherwise
/// (`docs/cashu/README.md`, phase C5).
///
/// One place for every entry point — the trade card, the trade screen, the
/// status listener, a notification, the end of the bond window — so none can
/// send a Cashu seller to a hold invoice that is never coming.
String sellerFundingPath(String orderId, {required bool cashu}) =>
    cashu ? AppRoute.lockEscrowPath(orderId) : AppRoute.payInvoicePath(orderId);

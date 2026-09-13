import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mostro/features/about/providers/mostro_node_provider.dart';
import 'package:mostro/features/order/models/invoice_rules.dart';
import 'package:mostro/features/trades/providers/trades_providers.dart'
    show tradeInfoProvider;
import 'package:mostro/shared/utils/platform_int64.dart';
import 'package:mostro/src/rust/api/invoice.dart' as invoice_api;

/// mostrod's default `expiration_seconds`, used while the node has not
/// advertised its own.
const kDefaultInvoiceStepSeconds = 900;

/// What the add-invoice screen asks about the buyer's input.
typedef InvoiceCheckRequest =
    ({
      String input,
      int? expectedSats,
      List<String> nodeNetworks,
      int? minRemainingSecs,
      int now,
    });

/// The Rust core's invoice judgement behind a seam, so the add-invoice
/// screen is testable without a live core. Throws when the core cannot
/// run; the screen then leaves the input to the daemon.
final invoiceCheckerProvider =
    Provider<Future<InvoiceCheck> Function(InvoiceCheckRequest)>(
      (ref) =>
          (request) async => invoiceCheckFromVerdict(
            await invoice_api.checkBuyerInvoice(
              input: request.input,
              expectedSats:
                  request.expectedSats == null
                      ? null
                      : BigInt.from(request.expectedSats!),
              nodeNetworks: request.nodeNetworks,
              minRemainingSecs:
                  request.minRemainingSecs == null
                      ? null
                      : BigInt.from(request.minRemainingSecs!),
              now: intToPlatformInt64(request.now),
            ),
          ),
    );

/// When the daemon moved the trade into its current step (unix seconds), or
/// null when that was not recorded. Behind a seam like the decoder.
final invoiceStepStartLookupProvider = Provider<Future<int?> Function(String)>(
  (ref) =>
      (orderId) async =>
          (await invoice_api.tradeStepStartedAt(orderId: orderId))?.toInt(),
);

/// When the current invoice step of [orderId] expires (unix seconds), or null
/// when it cannot be told.
///
/// mostrod cancels a waiting step `expiration_seconds` after `taken_at`, so
/// the deadline is the daemon message that opened the step plus the node's
/// window — not the 38383 `expires_at`, which is the pending order's
/// lifetime.
///
/// The step start is not always recorded: a taker's first reply is consumed
/// by the waiting `take_order` before any status cursor is written. A
/// taker's trade starts when they take, so its `started_at` stands in, with
/// the same node window — never the fixed `timeout_at`, which assumes 900 s.
/// A maker's `started_at` is when the order was created, so without a
/// recorded step start their deadline is unknown and no band is drawn.
final invoiceDeadlineProvider = FutureProvider.autoDispose.family<int?, String>(
  (ref, orderId) async {
    // Both dependencies are watched before the first await. Watched after
    // it, the autoDispose node provider would be left without a listener
    // during every rebuild — disposed, refetched, resolved, rebuilding this
    // one again, forever.
    final window =
        ref.watch(mostroNodeProvider).valueOrNull?.expirationSeconds ??
        kDefaultInvoiceStepSeconds;
    // Re-evaluated whenever the trade record changes, which is what a new
    // step does.
    final tradeFuture = ref.watch(tradeInfoProvider(orderId).future);
    final trade = await tradeFuture;
    try {
      final started = await ref.read(invoiceStepStartLookupProvider)(orderId);
      if (started != null) {
        // The cursor is in the node's clock, which the transport lets run up
        // to a minute ahead of ours; the countdown runs on ours. A start
        // "in the future" is clamped to now, so a fast node never adds time.
        final now = clock.now().millisecondsSinceEpoch ~/ 1000;
        return (started > now ? now : started) + window;
      }
    } catch (e) {
      debugPrint('[invoiceDeadline] step start unavailable: $e');
    }
    if (trade == null || trade.order.isMine) return null;
    return trade.startedAt.toInt() + window;
  },
);

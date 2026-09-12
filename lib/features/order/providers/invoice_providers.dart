import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mostro/features/about/providers/mostro_node_provider.dart';
import 'package:mostro/features/order/models/invoice_rules.dart';
import 'package:mostro/features/trades/providers/trades_providers.dart'
    show tradeInfoProvider;
import 'package:mostro/src/rust/api/invoice.dart' as invoice_api;

/// mostrod's default `expiration_seconds`, used while the node has not
/// advertised its own.
const kDefaultInvoiceStepSeconds = 900;

/// The local BOLT11 decoder behind a seam, so the add-invoice screen is
/// testable without a live Rust core. Resolves to null for an input that is
/// not a valid invoice; throws when the decoder itself cannot run.
final invoiceDecoderProvider =
    Provider<Future<DecodedInvoice?> Function(String)>(
      (ref) => (input) async {
        final summary = await invoice_api.decodeBolt11(invoice: input);
        if (summary == null) return null;
        return (
          amountSats: summary.amountSats?.toInt(),
          expiresAt: summary.expiresAt.toInt(),
        );
      },
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
/// lifetime. Without a recorded step start, the trade's own `timeout_at`
/// (set at take time) is the fallback.
final invoiceDeadlineProvider = FutureProvider.autoDispose.family<int?, String>(
  (ref, orderId) async {
    // Re-evaluated whenever the trade record changes, which is what a new
    // step does.
    final trade = await ref.watch(tradeInfoProvider(orderId).future);
    final window =
        ref.watch(mostroNodeProvider).valueOrNull?.expirationSeconds ??
        kDefaultInvoiceStepSeconds;
    try {
      final started = await ref.read(invoiceStepStartLookupProvider)(orderId);
      if (started != null) return started + window;
    } catch (e) {
      debugPrint('[invoiceDeadline] step start unavailable: $e');
    }
    return trade?.timeoutAt?.toInt();
  },
);

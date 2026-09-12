import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/widgets.dart';

import 'package:mostro/features/order/models/invoice_rules.dart';

/// The one ticker of an invoice screen: the time band, its pulse and the
/// expired state all read [invoiceRemaining], so they can never disagree.
///
/// Fed an absolute deadline (unix seconds) rather than a duration measured on
/// mount, so reopening the screen does not restart the clock.
mixin InvoiceClock<T extends StatefulWidget> on State<T> {
  /// Time left, or null while the deadline is unknown.
  final ValueNotifier<Duration?> invoiceRemaining = ValueNotifier(null);

  Timer? _invoiceTick;
  int? _invoiceDeadline;

  /// Points the clock at [expiresAt] (unix seconds); null stops it.
  void trackInvoiceDeadline(int? expiresAt) {
    if (expiresAt == _invoiceDeadline) return;
    _invoiceDeadline = expiresAt;
    _invoiceTick?.cancel();
    if (expiresAt == null) {
      invoiceRemaining.value = null;
      return;
    }
    _refreshInvoiceClock();
  }

  void _refreshInvoiceClock() {
    final deadline = _invoiceDeadline;
    if (deadline == null) return;
    final now = clock.now().millisecondsSinceEpoch ~/ 1000;
    final left = Duration(seconds: deadline > now ? deadline - now : 0);
    invoiceRemaining.value = left;
    if (left == Duration.zero) return;
    _invoiceTick = Timer(invoiceCountdownTick(left), () {
      if (mounted) _refreshInvoiceClock();
    });
  }

  @override
  void dispose() {
    _invoiceTick?.cancel();
    invoiceRemaining.dispose();
    super.dispose();
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mostro/core/automation/automation_id.dart';
import 'package:mostro/core/automation/automation_ids.dart';
import 'package:mostro/core/order_book_palette.dart';
import 'package:mostro/features/order/providers/trade_state_provider.dart';
import 'package:mostro/features/trades/providers/trades_providers.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/src/rust/api/types.dart'
    show CooperativeCancelState, OrderStatus;

/// The pending cooperative-cancel request on the trade screen (protocol
/// `cancel.md`, "Cancel cooperatively"). A request changes no status: the
/// trade goes on until the counterparty also cancels, so the row's
/// `cooperativeCancelState` is the only trace of it — Rust records it from
/// the daemon's `cooperative-cancel-initiated-by-{you,peer}`, and from this
/// side's own cancel before the daemon confirms. Shown while the trade is
/// still open; a settled trade has a status that says how it ended, and a
/// dispute supersedes the request. Nothing otherwise.
class CancelRequestNotice extends ConsumerWidget {
  const CancelRequestNotice({super.key, required this.orderId});

  final String orderId;

  /// Statuses the request is still open in. From `active` on only, and not
  /// once a dispute or an outcome took over.
  static bool requestIsOpen(OrderStatus status) => switch (status) {
    OrderStatus.active || OrderStatus.fiatSent => true,
    _ => false,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trade = ref.watch(tradeInfoProvider(orderId)).valueOrNull;
    final state = trade?.cooperativeCancelState;
    // The live status, as the rest of the screen reads it; the row's own
    // while it has not resolved.
    final status =
        ref.watch(tradeStatusProvider(orderId)).valueOrNull ??
        trade?.order.status;
    if (state == null || status == null || !requestIsOpen(status)) {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context);
    final book = OrderBookPalette.of(context);
    final (icon, text) = switch (state) {
      CooperativeCancelState.requestedByMe => (
        Icons.hourglass_top,
        l10n.tradeCancelRequestedByMeNotice,
      ),
      CooperativeCancelState.requestedByPeer => (
        Icons.cancel_outlined,
        l10n.tradeCancelRequestedByPeerNotice,
      ),
      // The daemon's acceptance moves the status, which hides this notice;
      // a row that remembers `accepted` on an open trade is a replay.
      CooperativeCancelState.accepted => (null, null),
    };
    if (text == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: book.textTertiary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                height: 1.5,
                color: book.textSecondary,
              ),
            ),
          ),
        ],
      ),
    ).withAutomationId(AutomationIds.tradeCancelRequest);
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mostro/core/automation/automation_id.dart';
import 'package:mostro/core/automation/automation_ids.dart';
import 'package:mostro/core/order_book_palette.dart';
import 'package:mostro/features/notifications/providers/notifications_provider.dart';
import 'package:mostro/features/order/models/invoice_rules.dart';
import 'package:mostro/features/trades/providers/trades_providers.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/src/rust/api/types.dart' show BondState, OrderStatus;

/// The durable line on the trade detail once the node slashed this user's
/// bond (docs/ANTI_ABUSE_BOND.md §8.3): the row keeps `bond.state = Slashed`
/// after the notice, so the fact outlives the notification. The cause reads
/// from the trade's status — an admin resolution is a dispute, anything
/// else a waiting-state timeout. The amount is the one the slash notice
/// carried when its notification is still stored (a partially filled range
/// order forfeits a slice, not the whole bond, §2.8), else the bond's.
/// Nothing without a slashed bond.
class BondSlashedNotice extends ConsumerWidget {
  const BondSlashedNotice({super.key, required this.orderId});

  final String orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trade = ref.watch(tradeInfoProvider(orderId)).valueOrNull;
    final bond = trade?.bond;
    if (trade == null || bond == null || bond.state != BondState.slashed) {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context);
    final book = OrderBookPalette.of(context);
    final reported =
        ref
            .watch(notificationsProvider)
            .where((n) => n.orderId == orderId)
            .map((n) => n.bondSlashedAmountSats)
            .whereType<int>()
            .firstOrNull;
    final sats = formatInvoiceSats(reported ?? bond.amountSats.toInt());
    final dispute = switch (trade.order.status) {
      OrderStatus.dispute ||
      OrderStatus.canceledByAdmin ||
      OrderStatus.settledByAdmin ||
      OrderStatus.completedByAdmin => true,
      _ => false,
    };
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.money_off, size: 16, color: book.textTertiary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              dispute
                  ? l10n.bondSlashedTradeNoticeDispute(sats)
                  : l10n.bondSlashedTradeNoticeTimeout(sats),
              style: TextStyle(
                fontSize: 12,
                height: 1.5,
                color: book.textSecondary,
              ),
            ),
          ),
        ],
      ),
    ).withAutomationId(
      AutomationIds.tradeBondSlashed,
      label: dispute ? 'dispute' : 'timeout',
    );
  }
}

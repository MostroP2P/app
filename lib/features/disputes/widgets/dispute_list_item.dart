import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:mostro/core/activity_palette.dart';
import 'package:mostro/core/app_routes.dart';
import 'package:mostro/core/order_book_palette.dart';
import 'package:mostro/features/chat/models/chat_list_rules.dart';
import 'package:mostro/features/chat/widgets/chat_list_item.dart'
    show ChatAvatar;
import 'package:mostro/features/disputes/providers/disputes_providers.dart';
import 'package:mostro/features/trades/models/trades_list_rules.dart';
import 'package:mostro/features/trades/widgets/trade_card.dart'
    show relativeTimeLabel;
import 'package:mostro/features/trades/widgets/trade_list_chip.dart';
import 'package:mostro/l10n/app_localizations.dart';

/// One dispute of the Disputes segment (handoff 11b): the conversation row's
/// structure, with the coral `En disputa` chip and who opened it and when.
class DisputeListItem extends ConsumerWidget {
  const DisputeListItem({
    super.key,
    required this.dispute,
    this.isLast = false,
  });

  final DisputeItem dispute;
  final bool isLast;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final book = OrderBookPalette.of(context);
    final pal = ActivityPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toString();
    final open = dispute.status != DisputeStatus.resolved;
    final handle = dispute.peerHandle ?? l10n.orderDispute;
    final opened = relativeTimeLabel(
      relativeTime(
        DateTime.fromMillisecondsSinceEpoch(dispute.openedAt * 1000),
        now: clock.now(),
      ),
      l10n,
      locale,
    );
    final contextLine =
        open
            ? (dispute.initiatedByMe
                ? l10n.disputeOpenedByYou(opened)
                : l10n.disputeOpenedByPeer(opened))
            : dispute.localizedDescription(l10n);

    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        ref.read(disputeNotifierProvider.notifier).markRead(dispute.id);
        context.push(AppRoute.disputeDetailsPath(dispute.id));
      },
      child: DecoratedBox(
        decoration: BoxDecoration(
          border:
              isLast ? null : Border(bottom: BorderSide(color: pal.rowDivider)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ChatAvatar(
                initial: handle,
                tone: open ? ChatAvatarTone.waiting : ChatAvatarTone.closed,
                showsActiveDot: false,
                dispute: open,
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            handle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: book.textPrimary,
                            ),
                          ),
                        ),
                        if (!dispute.isRead)
                          CircleAvatar(radius: 4, backgroundColor: pal.badgeBg),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      contextLine,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: book.textTertiary),
                    ),
                    if (open) ...[
                      const SizedBox(height: 6),
                      const TradeListChip(label: TradeChipLabel.dispute),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Localizes the summary line shown for a dispute in list items.
///
/// Kept out of [DisputeItem] so the model stays locale-independent; the
/// wording is resolved at render time from the dispute's status, resolution
/// and the viewing user's role.
extension DisputeItemL10n on DisputeItem {
  String localizedDescription(AppLocalizations l10n) {
    if (status == DisputeStatus.resolved) {
      return switch (resolution) {
        DisputeResolution.fundsToBuyer =>
          isSelling
              ? l10n.disputeDescResolvedBuyerFavour
              : l10n.disputeDescResolvedYourFavour,
        DisputeResolution.fundsToSeller =>
          isSelling
              ? l10n.disputeDescResolvedYourFavour
              : l10n.disputeDescResolvedSellerFavour,
        DisputeResolution.cooperativeCancel =>
          l10n.disputeDescCooperativeCancel,
        null => l10n.disputeDescResolved,
      };
    }
    return initiatedByMe
        ? l10n.disputeDescYouOpened
        : l10n.disputeDescCounterpartOpened;
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/chat/models/info_panel_rules.dart';
import 'package:mostro/features/chat/providers/chat_providers.dart';
import 'package:mostro/features/chat/widgets/trade_state_header.dart';
import 'package:mostro/features/order/providers/trade_state_provider.dart';
import 'package:mostro/features/order/widgets/order_detail_cards.dart';
import 'package:mostro/features/trades/models/trades_list_rules.dart';
import 'package:mostro/features/trades/providers/trades_providers.dart';
import 'package:mostro/features/trades/widgets/trade_list_chip.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/widgets/counterpart_reputation_row.dart';
import 'package:mostro/shared/widgets/nym_avatar.dart';
import 'package:mostro/src/rust/api/types.dart';

/// The share of the screen height a panel may take before it scrolls, so
/// the conversation under it keeps room at large text sizes.
const double _panelMaxHeightFraction = 0.35;

// ── TradeInformationTab ───────────────────────────────────────────────────────

/// The chat room's trade panel, opened from the app bar's info icon: order
/// id, fiat and sats amounts, status, payment method and creation date.
///
/// It reads the providers the sticky trade header reads, so the two never
/// disagree: the status is the header's ([tradePanelStatus]), and the figures
/// come from the trade row, then the order the header resolves
/// ([TradePanelFacts]). A figure the trade does not carry leaves its row
/// out rather than showing a placeholder.
class TradeInformationTab extends ConsumerWidget {
  const TradeInformationTab({super.key, required this.orderId});

  final String orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toString();
    final order = ref.watch(chatTradeOrderProvider(orderId)).valueOrNull;
    final trade = ref.watch(tradeInfoProvider(orderId)).valueOrNull;
    final live = ref.watch(tradeStatusProvider(orderId)).valueOrNull;
    final facts = TradePanelFacts.of(trade, order);
    final status = tradePanelStatus(live: live, order: order, trade: trade);
    final sats = facts?.sats;
    final paymentMethod = facts?.paymentMethod;

    return _PanelCard(
      title: l10n.tradeInformationTitle,
      children: [
        OrderIdRow(orderId: orderId),
        if (facts != null && facts.hasFiat)
          OrderDataRow(
            icon: Icons.payments_outlined,
            label: l10n.fiatAmountLabel,
            value: OrderDataValue(_fiat(facts, locale)),
          ),
        if (sats != null)
          OrderDataRow(
            icon: Icons.bolt_outlined,
            label: l10n.satsAmountLabel,
            value: OrderDataValue(
              l10n.satsAmount(formatSatsCount(sats, locale)),
            ),
          ),
        if (status != null) _StatusRow(status: status),
        if (paymentMethod != null)
          OrderPaymentMethodsRow(
            label: l10n.paymentMethodLabel,
            paymentMethod: paymentMethod,
          ),
        if (facts != null)
          OrderDataRow(
            icon: Icons.calendar_today_outlined,
            label: l10n.createdLabel,
            // The own-order and trade screens' date format.
            value: OrderDataValue(
              DateFormat.yMMMd(locale).add_Hm().format(facts.createdAt),
            ),
          ),
      ],
    );
  }

  /// `23.478 ARS`, or the range of an order not yet taken for one amount.
  static String _fiat(TradePanelFacts facts, String locale) {
    final amount = formatFiatAmount(
      amount: facts.fiatAmount,
      min: facts.fiatAmountMin,
      max: facts.fiatAmountMax,
      locale: locale,
    );
    return '$amount ${facts.fiatCode}';
  }
}

/// The status row: the header's word, in the trades list's chip.
class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.status});

  final OrderStatus status;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final filter = orderStatusToFilter(status);
    return OrderDataRow(
      icon: Icons.flag_outlined,
      label: l10n.statusLabel,
      // One line like every chip; a long translation at large text on a
      // narrow phone shrinks to the row instead of overflowing it.
      value: FittedBox(
        fit: BoxFit.scaleDown,
        child: TradeListChip.status(
          kind: tradePanelChipKind(filter),
          caption: filter.localizedLabel(l10n),
        ),
      ),
    );
  }
}

// ── UserInformationTab ────────────────────────────────────────────────────────

/// The chat room's user panel, opened from the app bar's user icon: the
/// alias and avatar this order's peer has in the chat header, and their
/// public reputation ([peerReputation]).
///
/// No key is shown here. The peer's trade key means nothing to a user, and
/// the chat's shared key never reaches Dart: it goes to a dispute's solver
/// from Rust (#415).
class UserInformationTab extends ConsumerWidget {
  const UserInformationTab({super.key, required this.room});

  /// The room the chat header renders, so alias and avatar are the same.
  final ChatRoomState room;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final book = OrderBookPalette.of(context);
    final textTheme = Theme.of(context).textTheme;
    final trade = ref.watch(tradeInfoProvider(room.orderId)).valueOrNull;
    final order = ref.watch(chatTradeOrderProvider(room.orderId)).valueOrNull;
    final reputation = peerReputation(trade, order);
    // The row's own role first; the room's until the row loads.
    final counterpartIsBuyer = switch (trade?.role) {
      TradeRole.seller => true,
      TradeRole.buyer => false,
      null => room.isSelling,
    };

    return _PanelCard(
      title: l10n.userInformationTitle,
      children: [
        // Avatar + handle, as the chat header shows them.
        Row(
          children: [
            NymAvatar(
              pseudonym: room.peerHandle,
              iconIndex: room.peerIconIndex,
              colorHue: room.peerColorHue,
              size: 56,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                room.displayHandle(l10n),
                style: textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: book.textPrimary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        if (reputation != null)
          CounterpartReputationRow(
            rating: reputation.rating,
            reviews: reputation.reviews,
            days: reputation.days,
            counterpartIsBuyer: counterpartIsBuyer,
          )
        else
          Text(
            l10n.peerReputationUnavailable,
            style: TextStyle(fontSize: 13, color: book.textSecondary),
          ),
      ],
    );
  }
}

// ── Private helpers ───────────────────────────────────────────────────────────

/// The frame both panels share, unchanged from before they were wired: a
/// card with the panel's title over its rows. Its content scrolls once it
/// outgrows [_panelMaxHeightFraction] of the screen, so the conversation
/// under it keeps room at large text sizes.
class _PanelCard extends StatelessWidget {
  const _PanelCard({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Card(
      margin: const EdgeInsets.all(AppSpacing.md),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight:
              MediaQuery.sizeOf(context).height * _panelMaxHeightFraction,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Section header
              Text(title, style: textTheme.headlineSmall),
              const SizedBox(height: AppSpacing.md),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

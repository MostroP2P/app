import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:mostro/core/activity_palette.dart';
import 'package:mostro/core/app_routes.dart';
import 'package:mostro/core/app_theme.dart' show AppFonts;
import 'package:mostro/core/automation/automation_id.dart';
import 'package:mostro/core/automation/automation_ids.dart';
import 'package:mostro/core/order_book_palette.dart';
import 'package:mostro/features/order/providers/exchange_rate_provider.dart';
import 'package:mostro/features/trades/models/trade_status.dart';
import 'package:mostro/features/trades/models/trades_list_rules.dart';
import 'package:mostro/features/trades/providers/trade_rows_provider.dart';
import 'package:mostro/features/trades/widgets/trade_list_chip.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/src/rust/api/types.dart' show OrderStatus;

/// One trade of My Trades (handoff 11a): direction and counterparty, the
/// amount as the headline, then the chip and — when the next step is the
/// user's — the verb that opens it.
class TradeCard extends ConsumerWidget {
  const TradeCard({super.key, required this.row});

  final TradeRow row;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final book = OrderBookPalette.of(context);
    final pal = ActivityPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toString();
    final needsAction = row.state.needsAction;

    return Material(
      color: book.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: needsAction ? pal.borderAction : book.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          context.push(_route());
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _DirectionRow(row: row, locale: locale),
              const SizedBox(height: 9),
              _AmountRow(row: row, locale: locale),
              const SizedBox(height: 9),
              DecoratedBox(
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: pal.rowDivider)),
                ),
                child: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    children: [
                      TradeListChip(label: row.state.chip),
                      if (row.claimBadge != TradeClaimBadge.none) ...[
                        const SizedBox(width: 6),
                        _ClaimBadge(badge: row.claimBadge),
                      ],
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          paymentMethodLabel(row.paymentMethod),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: book.textTertiary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (row.state.verb == TradeRowVerb.none)
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 14,
                          color: pal.chevronIdle,
                        )
                      else
                        _Verb(
                          label: verbText(row.state.verb, l10n),
                          onTap: () {
                            HapticFeedback.selectionClick();
                            context.push(_verbRoute());
                          },
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ).withAutomationId(AutomationIds.tradesItem(row.orderId));
  }

  /// Where the card opens: the maker's pending order and the maker's own
  /// Lightning step keep their screens; everything else is the trade screen.
  String _route() {
    // A claim with no trade behind it has nothing to open but the claim.
    if (row.claimOnly) return AppRoute.bondPayoutPath(row.orderId);
    if (row.isMaker) {
      if (row.status == OrderStatus.pending) {
        return AppRoute.myOrderPath(row.orderId);
      }
      if (row.status == OrderStatus.waitingPayment && row.isSelling) {
        return AppRoute.payInvoicePath(row.orderId);
      }
      if (row.status == OrderStatus.waitingBuyerInvoice && !row.isSelling) {
        return AppRoute.addInvoicePath(row.orderId);
      }
    }
    return AppRoute.tradeDetailPath(row.orderId);
  }

  /// The verb opens its step directly: the two Lightning steps have their own
  /// screens, the rest are the trade screen's primary button.
  String _verbRoute() => switch (row.state.verb) {
    TradeRowVerb.addInvoice => AppRoute.addInvoicePath(row.orderId),
    TradeRowVerb.payBond => AppRoute.payBondPath(row.orderId),
    TradeRowVerb.claimPayout => AppRoute.bondPayoutPath(row.orderId),
    TradeRowVerb.payInvoice => AppRoute.payInvoicePath(row.orderId),
    _ => AppRoute.tradeDetailPath(row.orderId),
  };

  static String verbText(TradeRowVerb verb, AppLocalizations l10n) =>
      switch (verb) {
        TradeRowVerb.addInvoice => l10n.tradeVerbAddInvoice,
        TradeRowVerb.payBond => l10n.tradeVerbPayBond,
        TradeRowVerb.claimPayout => l10n.tradeVerbClaimPayout,
        TradeRowVerb.payInvoice => l10n.tradeVerbPayInvoice,
        TradeRowVerb.sendPayment => l10n.tradeVerbSendPayment,
        TradeRowVerb.releaseSats => l10n.tradeVerbReleaseSats,
        TradeRowVerb.rate => l10n.tradeVerbRate,
        TradeRowVerb.none => '',
      };
}

/// `hace 1 h`, `ayer`, `lun`, `12 sep`.
String relativeTimeLabel(
  RelativeTime t,
  AppLocalizations l10n,
  String locale,
) => switch (t.kind) {
  RelativeTimeKind.now => l10n.relativeTimeNow,
  RelativeTimeKind.minutes => l10n.relativeTimeMinutes(t.count),
  RelativeTimeKind.hours => l10n.relativeTimeHours(t.count),
  RelativeTimeKind.yesterday => l10n.relativeTimeYesterday,
  RelativeTimeKind.weekday => DateFormat.E(locale).format(t.at!),
  RelativeTimeKind.date => DateFormat.MMMd(locale).format(t.at!),
};

class _DirectionRow extends StatelessWidget {
  const _DirectionRow({required this.row, required this.locale});

  final TradeRow row;
  final String locale;

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    final pal = ActivityPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final handle = row.peerHandle;
    final started = DateTime.fromMillisecondsSinceEpoch(row.startedAt * 1000);
    return Row(
      children: [
        Icon(
          row.isSelling
              ? Icons.arrow_upward_rounded
              : Icons.arrow_downward_rounded,
          size: 14,
          color: row.isSelling ? pal.sellArrow : pal.buyArrow,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text:
                      row.isSelling
                          ? l10n.tradesDirectionSell
                          : l10n.tradesDirectionBuy,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: book.textStrong,
                  ),
                ),
                if (handle != null)
                  TextSpan(
                    text:
                        ' ${row.isSelling ? l10n.tradesCounterpartyTo(handle) : l10n.tradesCounterpartyFrom(handle)}',
                    style: TextStyle(color: book.textTertiary),
                  ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          relativeTimeLabel(
            relativeTime(started, now: clock.now()),
            l10n,
            locale,
          ),
          style: TextStyle(
            fontFamily: AppFonts.figures,
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: book.textFaint,
          ),
        ),
      ],
    );
  }
}

class _AmountRow extends ConsumerWidget {
  const _AmountRow({required this.row, required this.locale});

  final TradeRow row;
  final String locale;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final book = OrderBookPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final fixed = (row.amountSats ?? 0) > 0;
    final cancelled =
        tradeStatusFromOrderStatus(row.status) == TradeStatus.cancelled;
    // Only a trade that still needs an estimate asks for the rate.
    final rate =
        fixed || cancelled || row.fiatCode.isEmpty
            ? null
            : ref.watch(exchangeRateProvider(row.fiatCode)).valueOrNull;
    final figure = satsFigure(
      status: row.status,
      amountSats: row.amountSats,
      fiat: row.fiatAmount ?? row.fiatAmountMin,
      rate: rate,
      premium: row.premium,
    );
    final sats = switch (figure.kind) {
      SatsFigureKind.exact => l10n.satsFigureExact(
        formatSatsCount(figure.sats!, locale),
      ),
      SatsFigureKind.estimate => l10n.satsFigureEstimate(
        formatSatsCount(figure.sats!, locale),
      ),
      SatsFigureKind.none => '—',
    };

    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              formatFiatAmount(
                amount: row.fiatAmount,
                min: row.fiatAmountMin,
                max: row.fiatAmountMax,
                locale: locale,
              ),
              maxLines: 1,
              style: TextStyle(
                fontFamily: AppFonts.figures,
                fontSize: 21,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.2,
                color: book.textPrimary,
              ),
            ),
          ),
        ),
        const SizedBox(width: 7),
        Text(
          row.fiatCode,
          style: TextStyle(fontSize: 12, color: book.textTertiary),
        ),
        const Spacer(),
        Text(
          sats,
          style: TextStyle(
            fontFamily: AppFonts.figures,
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: book.textMuted,
          ),
        ),
      ],
    );
  }
}

class _Verb extends StatelessWidget {
  const _Verb({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: book.limeInk,
              ),
            ),
            const SizedBox(width: 2),
            Icon(Icons.chevron_right_rounded, size: 13, color: book.limeIcon),
          ],
        ),
      ),
    );
  }
}

/// The payout badge next to the chip (docs/ANTI_ABUSE_BOND.md §8.3): the
/// dispute family's colours, since a claim only exists after a dispute or a
/// timeout went the user's way.
class _ClaimBadge extends StatelessWidget {
  const _ClaimBadge({required this.badge});

  final TradeClaimBadge badge;

  static String text(TradeClaimBadge badge, AppLocalizations l10n) =>
      switch (badge) {
        TradeClaimBadge.payoutPending => l10n.tradeBadgePayoutPending,
        TradeClaimBadge.payoutInProgress => l10n.tradeBadgePayoutInProgress,
        TradeClaimBadge.payoutPaid => l10n.tradeBadgePayoutPaid,
        TradeClaimBadge.none => '',
      };

  @override
  Widget build(BuildContext context) {
    final pal = ActivityPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final (bg, border, ink) =
        badge == TradeClaimBadge.payoutPaid
            ? (pal.chipDoneBg, pal.chipDoneBorder, pal.chipDoneInk)
            : (pal.chipDisputeBg, pal.chipDisputeBorder, pal.chipDisputeInk);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Text(
        text(badge, l10n).toUpperCase(),
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
          color: ink,
        ),
      ),
    );
  }
}

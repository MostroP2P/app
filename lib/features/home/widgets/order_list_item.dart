import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/core/automation/automation_id.dart';
import 'package:mostro/core/automation/automation_ids.dart';
import 'package:mostro/features/home/providers/home_order_providers.dart';
import 'package:mostro/features/home/providers/order_reason_provider.dart';
import 'package:mostro/l10n/app_localizations.dart';

const _cardRadius = BorderRadius.all(Radius.circular(18));

/// Vertical gap between the card's rows.
const double _rowGap = 12;

/// Premium points against the taker beyond which a premium reads as
/// expensive rather than merely above market (handoff 4b: `> 3%`).
const double _premiumHighThreshold = 3;

/// The number formatters an order card needs, built once per locale.
///
/// Building them inline meant several `NumberFormat` allocations per visible
/// row on every rebuild — and the order book rebuilds on every relay event.
///
/// Not because construction is dramatically more expensive than formatting: it
/// parses the pattern and reads locale data, but measured against warm locale
/// data it costs about 1.2–1.5× a `format()` call (~1 µs each). It is worth
/// doing for the allocations it stops making, and the honest size of the win
/// is small — the claim that construction dominates does not hold.
class OrderCardFormats {
  OrderCardFormats._(String locale)
      : premium = NumberFormat('+0.0;-0.0', locale),
        _unsignedPremium = NumberFormat('0.0', locale),
        rating = NumberFormat('0.##', locale),
        decimal = NumberFormat.decimalPattern(locale),
        fiat = NumberFormat('#,##0.##', locale);

  /// Premium, always signed: `+2.5` / `-2.5`.
  final NumberFormat premium;

  final NumberFormat _unsignedPremium;

  /// Raw ratings (4.9, 4.78): up to 2 decimals, no trailing zeros.
  final NumberFormat rating;

  /// Grouped integers: sats, trade count, days active.
  final NumberFormat decimal;

  /// Fiat amounts: grouped, up to two decimals, no trailing zeros.
  final NumberFormat fiat;

  static final Map<String, OrderCardFormats> _byLocale = {};

  /// Formatters for [locale]. The app ships a handful of locales, so the
  /// cache needs no eviction.
  static OrderCardFormats of(String locale) =>
      _byLocale.putIfAbsent(locale, () => OrderCardFormats._(locale));

  /// [value] at the one-decimal precision the card shows, so what reads as
  /// `0.0%` is also coloured as zero.
  static double shown(double value) => (value * 10).roundToDouble() / 10;

  /// `+5.0%`, `0.0%`, `-1.5%` — zero carries no sign.
  String premiumPercent(double value) {
    final rounded = shown(value);
    final text =
        rounded == 0 ? _unsignedPremium.format(0) : premium.format(rounded);
    return '$text%';
  }

  /// `832 – 5,000` for a range, `25` for a single amount.
  String amount(OrderItem order) =>
      order.isRange
          ? '${fiat.format(order.fiatAmountMin!)} – '
              '${fiat.format(order.fiatAmountMax!)}'
          : fiat.format(order.fiatAmount!);
}

/// Order-book card (order-book handoff, variant 4b).
///
/// Rows: currency chip + highlight chip + relative time · amount and its
/// caption beside the premium · payment methods (up to two lines) ·
/// reputation strip. The premium is plain coloured text — pills are reserved
/// for the highlight chips, which appear once per list — and its colour is
/// read from the taker's side: green in their favour or at market, amber up
/// to 3 points against them, orange beyond.
///
/// Nothing in the card has a fixed height, so it grows with the text scale.
class OrderListItem extends StatelessWidget {
  const OrderListItem({
    super.key,
    required this.order,
    this.onTap,
    this.currencyFlags = const {},
    this.reason,
  });

  final OrderItem order;
  final VoidCallback? onTap;
  final Map<String, String> currencyFlags;

  /// Highlight chip awarded to this card, if any. Computed across the visible
  /// list (see [orderReasonsProvider]) and passed in by the screen. The
  /// best-premium card also gets the highlight border.
  final OrderReason? reason;

  @override
  Widget build(BuildContext context) {
    final pal = OrderBookPalette.of(context);
    final formats = OrderCardFormats.of(
      Localizations.localeOf(context).toString(),
    );
    final isBestPremium = reason == OrderReason.bestPremium;

    // Material + InkWell (not GestureDetector) so each card is focusable,
    // keyboard-activatable and announced as a button; the border rides the
    // Material shape so the ripple clips to it. The card wraps exactly one
    // tap target, so merging is what keeps the tap action on the node that
    // carries the identifier.
    return Material(
      color: pal.surface,
      shape: RoundedRectangleBorder(
        borderRadius: _cardRadius,
        side: BorderSide(
          color: isBestPremium ? pal.borderHighlight : pal.border,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: _cardRadius,
        highlightColor: pal.pressed,
        splashColor: pal.pressed,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _HeaderRow(
                order: order,
                reason: reason,
                flag: currencyFlags[order.fiatCode] ?? '',
                palette: pal,
              ),
              const SizedBox(height: _rowGap),
              _AmountRow(order: order, formats: formats, palette: pal),
              const SizedBox(height: _rowGap),
              _PaymentMethodsRow(
                paymentMethod: order.paymentMethod,
                palette: pal,
              ),
              const SizedBox(height: _rowGap),
              _ReputationStrip(order: order, formats: formats, palette: pal),
            ],
          ),
        ),
      ),
    ).withAutomationId(AutomationIds.orderBookItem(order.id));
  }
}

// ── Row 1: chips and time ─────────────────────────────────────────────────────

class _HeaderRow extends StatelessWidget {
  const _HeaderRow({
    required this.order,
    required this.reason,
    required this.flag,
    required this.palette,
  });

  final OrderItem order;
  final OrderReason? reason;
  final String flag;
  final OrderBookPalette palette;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    // The card carries no buy/sell chip (the tabs already scope the side);
    // the only functional signal kept is "yours" on own orders.
    final mineLabel =
        order.isMine
            ? (order.kind == 'sell'
                ? l10n.orderPillYouAreSelling
                : l10n.orderPillYouAreBuying)
            : null;

    final highlight = switch (reason) {
      OrderReason.bestPremium => _Chip(
        label: l10n.reasonBestPremium,
        color: palette.limeInk,
        fill: palette.bestChipFill,
        border: palette.bestChipBorder,
      ),
      OrderReason.mostReputable => _Chip(
        label: l10n.reasonMostReputable,
        color: palette.yellowInk,
        fill: palette.reputableChipFill,
        border: palette.reputableChipBorder,
      ),
      null => null,
    };

    return LayoutBuilder(
      builder:
          (context, constraints) => Row(
            children: [
              // Chips keep their intrinsic width and wrap to a second run when
              // they don't fit beside the time — shrinking them ellipsized the
              // labels on small phones.
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _CurrencyChip(
                      flag: flag,
                      code: order.fiatCode,
                      palette: palette,
                    ),
                    // Own-order chip before the highlight: on an own order it
                    // must always be readable.
                    if (mineLabel != null)
                      _Chip(
                        label: mineLabel,
                        color: palette.textSecondary,
                        fill: palette.currencyChipFill,
                        border: palette.border,
                      ),
                    if (highlight != null) highlight,
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Flush right at its natural width, capped at half the row so a
              // long localized time at a large text scale wraps instead of
              // pushing the chips out.
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: constraints.maxWidth / 2),
                child: Text(
                  _relativeTime(order.createdAt, l10n),
                  textAlign: TextAlign.end,
                  style: TextStyle(fontSize: 11, color: palette.textFaint),
                ),
              ),
            ],
          ),
    );
  }
}

String _relativeTime(DateTime dt, AppLocalizations l10n) {
  final diff = clock.now().difference(dt);
  if (diff.isNegative || diff.inMinutes < 1) return l10n.justNow;
  if (diff.inMinutes < 60) return l10n.minutesAgo(diff.inMinutes);
  if (diff.inHours < 24) return l10n.hoursAgo(diff.inHours);
  return l10n.daysAgo(diff.inDays);
}

class _CurrencyChip extends StatelessWidget {
  const _CurrencyChip({
    required this.flag,
    required this.code,
    required this.palette,
  });

  final String flag;
  final String code;
  final OrderBookPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(7, 4, 9, 4),
      decoration: BoxDecoration(
        color: palette.currencyChipFill,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (flag.isNotEmpty) ...[
            Text(flag, style: const TextStyle(fontSize: 13)),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(
              code,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: palette.textStrong,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Uppercase capsule — the highlight chips and the own-order chip.
class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.color,
    required this.fill,
    required this.border,
  });

  final String label;
  final Color color;
  final Color fill;
  final Color border;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: fill,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label.toUpperCase(),
        semanticsLabel: label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.4,
          color: color,
        ),
      ),
    );
  }
}

// ── Row 2: amount and premium ─────────────────────────────────────────────────

class _AmountRow extends StatelessWidget {
  const _AmountRow({
    required this.order,
    required this.formats,
    required this.palette,
  });

  final OrderItem order;
  final OrderCardFormats formats;
  final OrderBookPalette palette;

  /// Green in the taker's favour or at market, amber up to 3 points against
  /// them, orange beyond.
  Color get _premiumColor {
    final against = -OrderCardFormats.shown(order.takerPremiumAdvantage);
    if (against <= 0) return palette.limeText;
    if (against <= _premiumHighThreshold) return palette.premiumMid;
    return palette.premiumHigh;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final captionStyle = TextStyle(fontSize: 11, color: palette.textTertiary);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Never truncated: a long range wraps at the spaces around
              // the dash instead.
              Text(
                formats.amount(order),
                style: TextStyle(
                  fontFamily: AppFonts.figures,
                  fontSize: 25,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.5,
                  height: 1,
                  color: palette.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              if (order.hasFixedSats)
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: l10n.orderFixedAmountPrefix),
                      TextSpan(
                        text: l10n.satsAmount(
                          formats.decimal.format(order.amountSats!.toInt()),
                        ),
                        style: TextStyle(
                          fontFamily: AppFonts.figures,
                          fontWeight: FontWeight.w600,
                          color: palette.limeInk,
                        ),
                      ),
                    ],
                  ),
                  style: captionStyle,
                )
              else
                Text(l10n.marketPriceCaption, style: captionStyle),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              formats.premiumPercent(order.premium),
              style: TextStyle(
                fontFamily: AppFonts.figures,
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: _premiumColor,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              l10n.orderCardPremiumCaption,
              style: TextStyle(fontSize: 10, color: palette.textFaint),
            ),
          ],
        ),
      ],
    );
  }
}

// ── Row 3: payment methods ────────────────────────────────────────────────────

class _PaymentMethodsRow extends StatelessWidget {
  const _PaymentMethodsRow({
    required this.paymentMethod,
    required this.palette,
  });

  final String paymentMethod;
  final OrderBookPalette palette;

  @override
  Widget build(BuildContext context) {
    final methods = paymentMethod
        .split(',')
        .map((method) => method.trim())
        .where((method) => method.isNotEmpty)
        .join(', ');

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(
            Icons.credit_card_outlined,
            size: 14,
            color: palette.textTertiary,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            methods,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              height: 1.45,
              color: palette.textMuted,
            ),
          ),
        ),
      ],
    );
  }
}

// ── Row 4: reputation ─────────────────────────────────────────────────────────

class _ReputationStrip extends StatelessWidget {
  const _ReputationStrip({
    required this.order,
    required this.formats,
    required this.palette,
  });

  final OrderItem order;
  final OrderCardFormats formats;
  final OrderBookPalette palette;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isNew = order.tradeCount == 0;
    final separator = Text('|', style: TextStyle(color: palette.divider));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: palette.inset,
        borderRadius: BorderRadius.circular(12),
      ),
      child: DefaultTextStyle.merge(
        style: TextStyle(fontSize: 12, color: palette.textSecondary),
        child: Wrap(
          spacing: 10,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Icon(
              Icons.star_rounded,
              size: 14,
              color: order.rating > 0 ? palette.yellow : palette.starEmpty,
            ),
            if (isNew)
              Text(
                l10n.reputationNew,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: palette.textNew,
                ),
              )
            else
              Text(
                formats.rating.format(order.rating),
                style: TextStyle(
                  fontFamily: AppFonts.figures,
                  fontWeight: FontWeight.w600,
                  color: palette.textStrong,
                ),
              ),
            separator,
            if (isNew)
              Text(l10n.reputationNoTrades)
            else
              _Stat(
                value: formats.decimal.format(order.tradeCount),
                label: l10n.reputationTradesLabel(order.tradeCount),
                palette: palette,
              ),
            separator,
            _Stat(
              value: formats.decimal.format(order.daysActive),
              label: l10n.reputationDaysLabel(order.daysActive),
              palette: palette,
            ),
          ],
        ),
      ),
    );
  }
}

/// Figure + unit ("16 trades") in the reputation strip.
class _Stat extends StatelessWidget {
  const _Stat({
    required this.value,
    required this.label,
    required this.palette,
  });

  final String value;
  final String label;
  final OrderBookPalette palette;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: value,
            style: TextStyle(
              color: palette.textBody,
              fontWeight: FontWeight.w500,
            ),
          ),
          TextSpan(text: ' $label'),
        ],
      ),
    );
  }
}

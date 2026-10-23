import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/core/automation/automation_id.dart';
import 'package:mostro/core/automation/automation_ids.dart';
import 'package:mostro/features/home/providers/home_order_providers.dart';
import 'package:mostro/features/home/providers/order_reason_provider.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/utils/abbreviated_figure.dart';
import 'package:mostro/shared/utils/rating_format.dart';
import 'package:mostro/shared/utils/reputation_age.dart';
import 'package:mostro/shared/widgets/currency_mark.dart';
import 'package:mostro/shared/widgets/counterpart_reputation_row.dart'
    show highlightFigures;

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
  OrderCardFormats._(this._locale)
    : premium = NumberFormat('+0.0;-0.0', _locale),
      _unsignedPremium = NumberFormat('0.0', _locale),
      rating = ratingFormat(_locale),
      decimal = NumberFormat.decimalPattern(_locale),
      fiat = NumberFormat('#,##0.##', _locale);

  final String _locale;

  /// Premium, always signed: `+2.5` / `-2.5`.
  final NumberFormat premium;

  final NumberFormat _unsignedPremium;

  /// Ratings as every screen shows them (DS-L10N-5): `4.97`, `4.9`, `5`.
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

  /// The price per BTC a fixed-sats order stands for, in its own currency,
  /// abbreviated with the same k/M/B suffixes in every locale (`61.2k`,
  /// `112M`, `10B`; `61,2k` in Spanish) because it spans tens of thousands of
  /// EUR to billions of LBP. Exact: it comes from the order's two
  /// figures, not from an exchange rate. Null for a market-price order.
  String? fixedPricePerBtc(OrderItem order) {
    final fiatAmount = order.fiatAmount;
    if (!order.hasFixedSats || fiatAmount == null) return null;
    final price = fiatAmount * 1e8 / order.amountSats!.toDouble();
    return abbreviateFigure(price, _locale);
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
/// to 3 points against them, orange beyond. A fixed-sats order has no
/// premium, so it shows its price per BTC there instead, in a neutral colour.
///
/// Nothing in the card has a fixed height, so it grows with the text scale.
class OrderListItem extends StatelessWidget {
  const OrderListItem({
    super.key,
    required this.order,
    this.onTap,
    this.reason,
  });

  final OrderItem order;
  final VoidCallback? onTap;

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
              _HeaderRow(order: order, reason: reason, palette: pal),
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
    required this.palette,
  });

  final OrderItem order;
  final OrderReason? reason;
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
                    _CurrencyChip(code: order.fiatCode, palette: palette),
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

/// Mark (flag, or a stablecoin's coin: DS-TYP-9) + code.
class _CurrencyChip extends StatelessWidget {
  const _CurrencyChip({required this.code, required this.palette});

  final String code;
  final OrderBookPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      decoration: BoxDecoration(
        color: palette.currencyChipFill,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CurrencyMarkGap(code: code, size: 13, gap: 6),
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
    // A fixed-sats order has no premium: its right-hand figure is the price
    // per BTC it stands for.
    final String? figure;
    final String caption;
    final Color figureColor;
    if (order.hasFixedSats) {
      final price = formats.fixedPricePerBtc(order);
      figure = price == null ? null : '$price ${order.fiatCode}/BTC';
      caption = l10n.orderCardPriceCaption;
      figureColor = palette.textBody;
    } else {
      figure = formats.premiumPercent(order.premium);
      caption = l10n.orderCardPremiumCaption;
      figureColor = _premiumColor;
    }

    return LayoutBuilder(
      builder:
          (context, constraints) => Row(
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
                        fontSize: 26,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.5,
                        height: 1,
                        color: palette.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (order.hasFixedSats)
                      _FixedSatsCaption(
                        sats: formats.decimal.format(order.amountSats!.toInt()),
                        style: captionStyle,
                        palette: palette,
                      )
                    else
                      Text(l10n.marketPriceCaption, style: captionStyle),
                  ],
                ),
              ),
              if (figure != null) ...[
                const SizedBox(width: 10),
                // Capped at half the row: a premium never comes near it, but a
                // price per BTC (`61,2k EUR/BTC`) at a large text scale wraps
                // instead of pushing the row past the card.
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: constraints.maxWidth / 2,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        figure,
                        textAlign: TextAlign.end,
                        style: TextStyle(
                          fontFamily: AppFonts.figures,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: figureColor,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        caption,
                        textAlign: TextAlign.end,
                        style: TextStyle(
                          fontSize: 10,
                          color: palette.textFaint,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
    );
  }
}

/// "Fixed amount · for 4,000 sats", with the figure set in the figures face.
///
/// One sentence with a placeholder rather than a prefix glued to the figure,
/// so a locale can put the figure wherever its word order needs; the styled
/// span is found by splitting around it. A translation that drops the
/// placeholder still reads, just unstyled.
class _FixedSatsCaption extends StatelessWidget {
  const _FixedSatsCaption({
    required this.sats,
    required this.style,
    required this.palette,
  });

  /// The grouped sats figure, without its unit.
  final String sats;
  final TextStyle style;
  final OrderBookPalette palette;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final figure = l10n.satsAmount(sats);
    final caption = l10n.orderFixedAmount(figure);
    final at = caption.indexOf(figure);
    if (at < 0) return Text(caption, style: style);

    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: caption.substring(0, at)),
          TextSpan(
            text: figure,
            style: TextStyle(
              fontFamily: AppFonts.figures,
              fontWeight: FontWeight.w600,
              color: palette.limeInk,
            ),
          ),
          TextSpan(text: caption.substring(at + figure.length)),
        ],
      ),
      style: style,
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: palette.inset,
        borderRadius: BorderRadius.circular(12),
      ),
      child: DefaultTextStyle.merge(
        style: TextStyle(fontSize: 12, color: palette.textSecondary),
        // Rating and count on the left, the age on the right; on a strip too
        // narrow for both (`desde mar 2023` at 360 dp in Spanish) the age
        // takes its own line instead of following a dangling separator.
        child: SizedBox(
          width: double.infinity,
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 12,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Icon(
                    Icons.star_rounded,
                    size: 14,
                    color:
                        order.rating > 0 ? palette.yellow : palette.starEmpty,
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
                  _Stat(
                    text: l10n.reputationRatingsCount(order.tradeCount),
                    palette: palette,
                  ),
                ],
              ),
              _Stat(
                text: reputationSinceText(l10n, order.makerFirstTrade),
                palette: palette,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One reputation figure in the strip (`16 ratings`, `since Mar 2025`),
/// its digits set apart as on every reputation row.
class _Stat extends StatelessWidget {
  const _Stat({required this.text, required this.palette});

  final String text;
  final OrderBookPalette palette;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        children: highlightFigures(
          text,
          TextStyle(color: palette.textBody, fontWeight: FontWeight.w500),
        ),
      ),
    );
  }
}

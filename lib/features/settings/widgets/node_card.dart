import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shimmer/shimmer.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/core/automation/automation_id.dart';
import 'package:mostro/core/automation/automation_ids.dart';
import 'package:mostro/core/node_selector_palette.dart';
import 'package:mostro/features/settings/models/node_display.dart';
import 'package:mostro/features/settings/models/node_selector_rules.dart';
import 'package:mostro/features/settings/providers/mostro_nodes_provider.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/src/rust/api/node_stats.dart';
import 'package:mostro/src/rust/api/types.dart';

/// One node of the selector (handoff 9a). Four rows: identity, accepted
/// currencies, the metrics strip (liquidity · fee · range) and the trust line
/// (custody · bond). The whole card selects; the pubkey copies.
///
/// [stats] is `null` while loading ([statsLoading]) or when the fetch failed:
/// the strip then shows skeletons or `—`, and the card stays selectable —
/// missing data is never a verdict.
class NodeCard extends StatelessWidget {
  const NodeCard({
    super.key,
    required this.entry,
    required this.stats,
    required this.statsLoading,
    required this.myFiat,
    required this.flags,
    required this.btcPrice,
    required this.selected,
    required this.now,
    required this.onSelect,
    required this.onBlocked,
    required this.onCopyPubkey,
    this.onLongPress,
  });

  final MostroNodeEntry entry;
  final MostroNodeStats? stats;
  final bool statsLoading;

  /// The user's preferred fiat code, or `null` for "all currencies".
  final String? myFiat;

  /// Fiat code → flag emoji.
  final Map<String, String> flags;

  /// Price of one BTC in [myFiat], for the range's fiat equivalent.
  final double? btcPrice;

  /// Active node, or the one just tapped while the sheet closes.
  final bool selected;
  final DateTime now;
  final VoidCallback onSelect;
  final ValueChanged<NodeBlocker> onBlocked;
  final VoidCallback onCopyPubkey;
  final VoidCallback? onLongPress;

  static const double _radius = 18;

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    final pal = NodeSelectorPalette.of(context);
    final s = stats;
    final blocker = blockerOf(s, myFiat, now);
    final accepts = s == null ? null : acceptsMyFiat(s, myFiat);
    final dim = dimFactorOf(blocker, accepts);

    final body = Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(_radius),
        border: Border.all(
          color: dimmed(selected ? pal.borderSelected : pal.border, dim),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _IdentityRow(
            entry: entry,
            stats: s,
            myFiat: myFiat,
            now: now,
            selected: selected,
            dim: dim,
            onCopyPubkey: onCopyPubkey,
          ),
          const SizedBox(height: 11),
          _CurrencyRow(stats: s, myFiat: myFiat, flags: flags, dim: dim),
          const SizedBox(height: 11),
          _MetricsStrip(
            stats: s,
            loading: statsLoading,
            myFiat: myFiat,
            btcPrice: btcPrice,
            dim: dim,
          ),
          const SizedBox(height: 11),
          _TrustRow(stats: s, dim: dim),
        ],
      ),
    );

    // A blocked card has no ink: a tap only explains why. Dimming touches
    // the fill, borders, chips and indicators — never the text.
    final Widget tappable =
        blocker == null
            ? Material(
              color: dimmed(book.surface, dim),
              borderRadius: BorderRadius.circular(_radius),
              child: InkWell(
                onTap: onSelect,
                onLongPress: onLongPress,
                borderRadius: BorderRadius.circular(_radius),
                child: body,
              ),
            )
            : GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onBlocked(blocker),
              onLongPress: onLongPress,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: dimmed(book.surface, dim),
                  borderRadius: BorderRadius.circular(_radius),
                ),
                child: body,
              ),
            );

    return tappable.withAutomationId(
      AutomationIds.nodeItem(entry.pubkey),
      merge: false,
    );
  }
}

/// [color] with its alpha scaled by [dim] — how decorative surfaces fade on a
/// dimmed card while the text on them stays fully opaque.
Color dimmed(Color color, double dim) =>
    dim >= 1 ? color : color.withValues(alpha: color.a * dim);

// ── Row 1 · identity ──────────────────────────────────────────────────────────

class _IdentityRow extends StatelessWidget {
  const _IdentityRow({
    required this.entry,
    required this.stats,
    required this.myFiat,
    required this.now,
    required this.selected,
    required this.dim,
    required this.onCopyPubkey,
  });

  final MostroNodeEntry entry;
  final MostroNodeStats? stats;
  final String? myFiat;
  final DateTime now;
  final bool selected;
  final double dim;
  final VoidCallback onCopyPubkey;

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    final pal = NodeSelectorPalette.of(context);
    final l10n = AppLocalizations.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _NodeAvatar(entry: entry, dim: dim),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      nodeDisplayName(entry),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: book.textPrimary,
                      ),
                    ),
                  ),
                  if (entry.isTrusted) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: dimmed(pal.trustedBg, dim),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: dimmed(pal.trustedBorder, dim),
                        ),
                      ),
                      child: Text(
                        l10n.trustedBadgeLabel.toUpperCase(),
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.36,
                          color: pal.trustedInk,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 2),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  Clipboard.setData(ClipboardData(text: entry.pubkey));
                  HapticFeedback.selectionClick();
                  onCopyPubkey();
                },
                child: Text(
                  truncatePubkey(entry.pubkey),
                  style: TextStyle(
                    fontFamily: AppFonts.figures,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: book.textFaint,
                  ),
                ),
              ),
              if (stats != null) ...[
                const SizedBox(height: 4),
                _AvailabilityLine(stats: stats!, myFiat: myFiat, now: now),
              ],
            ],
          ),
        ),
        const SizedBox(width: 10),
        _Radio(selected: selected, dim: dim),
      ],
    );
  }
}

class _NodeAvatar extends StatelessWidget {
  const _NodeAvatar({required this.entry, required this.dim});

  final MostroNodeEntry entry;
  final double dim;
  static const double _size = 32;

  @override
  Widget build(BuildContext context) {
    final pal = NodeSelectorPalette.of(context);
    final name = nodeDisplayName(entry);
    final initial = name.isEmpty ? '?' : name.characters.first.toUpperCase();
    // Tint derived from the name, never a generated identicon.
    final lime = name.codeUnits.fold<int>(0, (a, b) => a + b).isEven;
    final fallback = Container(
      width: _size,
      height: _size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: dimmed(lime ? pal.avatarLimeBg : pal.avatarYellowBg, dim),
        shape: BoxShape.circle,
      ),
      child: Text(
        initial,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: lime ? pal.avatarLimeInk : pal.avatarYellowInk,
        ),
      ),
    );
    final picture = entry.picture;
    if (picture == null) return fallback;
    return ClipOval(
      child: Image.network(
        picture,
        width: _size,
        height: _size,
        fit: BoxFit.cover,
        cacheWidth: (_size * 3).round(),
        errorBuilder: (_, __, ___) => fallback,
      ),
    );
  }
}

class _Radio extends StatelessWidget {
  const _Radio({required this.selected, required this.dim});

  final bool selected;
  final double dim;

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    final pal = NodeSelectorPalette.of(context);
    return AnimatedScale(
      scale: selected ? 1 : 0.9,
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 20,
        height: 20,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: selected ? dimmed(book.lime, dim) : Colors.transparent,
          border:
              selected
                  ? null
                  : Border.all(color: dimmed(pal.radioBorder, dim), width: 1.5),
        ),
        child:
            selected ? Icon(Icons.check, size: 14, color: book.onLime) : null,
      ),
    );
  }
}

class _AvailabilityLine extends StatelessWidget {
  const _AvailabilityLine({
    required this.stats,
    required this.myFiat,
    required this.now,
  });

  final MostroNodeStats stats;
  final String? myFiat;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    final pal = NodeSelectorPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final availability = availabilityOf(stats, myFiat, now);
    final (dot, text) = switch (availability) {
      NodeAvailability.online => (
        pal.dotOnline,
        l10n.nodeStatusOnline(stats.totalOrders),
      ),
      NodeAvailability.noUsefulOrders => (
        pal.dotWarn,
        l10n.nodeStatusNoUsefulOrders,
      ),
      NodeAvailability.unreachable => (
        pal.dotOffline,
        _unreachableText(l10n, lastSignalAt(stats)),
      ),
    };
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: book.textSecondary),
          ),
        ),
      ],
    );
  }

  String _unreachableText(AppLocalizations l10n, DateTime? last) {
    if (last == null) return l10n.nodeStatusUnreachableNoSignal;
    final d = now.difference(last);
    final ago =
        d.inMinutes < 60
            ? l10n.minutesAgo(d.inMinutes.clamp(1, 59))
            : d.inHours < 24
            ? l10n.hoursAgo(d.inHours)
            : l10n.daysAgo(d.inDays);
    return l10n.nodeStatusUnreachable(ago);
  }
}

// ── Row 2 · currencies ────────────────────────────────────────────────────────

class _CurrencyRow extends StatelessWidget {
  const _CurrencyRow({
    required this.stats,
    required this.myFiat,
    required this.flags,
    required this.dim,
  });

  final MostroNodeStats? stats;
  final String? myFiat;
  final Map<String, String> flags;
  final double dim;

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    final pal = NodeSelectorPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final s = stats;
    if (s == null || s.acceptedCurrencies.isEmpty) {
      return Text('—', style: TextStyle(fontSize: 11, color: book.textFaint));
    }
    final mine = myFiat?.toUpperCase();
    final accepts = acceptsMyFiat(s, mine);
    final chips = currencyChips(s.acceptedCurrencies, mine);

    Widget chip({
      required String text,
      String? flag,
      required Color bg,
      Color? border,
      required Color ink,
    }) {
      return Container(
        padding: const EdgeInsets.fromLTRB(6, 3, 8, 3),
        decoration: BoxDecoration(
          color: dimmed(bg, dim),
          borderRadius: BorderRadius.circular(8),
          border:
              border == null ? null : Border.all(color: dimmed(border, dim)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (flag != null) ...[
              Text(flag, style: const TextStyle(fontSize: 11)),
              const SizedBox(width: 4),
            ],
            Text(
              text,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: ink,
              ),
            ),
          ],
        ),
      );
    }

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        if (accepts == false && mine != null)
          chip(
            text: l10n.nodeMissingCurrencyChip(mine),
            bg: pal.warnBg,
            border: pal.warnBorder,
            ink: pal.warnInk,
          ),
        for (final code in chips.shown)
          code == mine
              ? chip(
                text: code,
                flag: flags[code],
                bg: pal.chipMineBg,
                border: pal.chipMineBorder,
                ink: pal.chipMineInk,
              )
              : chip(
                text: code,
                flag: flags[code],
                bg: pal.chipNeutralBg,
                ink: pal.chipNeutralInk,
              ),
        if (chips.overflow > 0)
          chip(
            text: '+${chips.overflow}',
            bg: pal.chipNeutralBg,
            ink: pal.chipNeutralInk,
          ),
      ],
    );
  }
}

// ── Row 3 · metrics ───────────────────────────────────────────────────────────

class _MetricsStrip extends StatelessWidget {
  const _MetricsStrip({
    required this.stats,
    required this.loading,
    required this.myFiat,
    required this.btcPrice,
    required this.dim,
  });

  final MostroNodeStats? stats;
  final bool loading;
  final String? myFiat;
  final double? btcPrice;
  final double dim;

  /// Below this width (at the current text scale) the three columns wrap
  /// into two rows (2 + 1) instead of squeezing the figures.
  static const double _minRowWidth = 260;

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    final pal = NodeSelectorPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toString();
    final s = stats;
    final mine = myFiat?.toUpperCase();

    // Liquidity — the only lime figure: it is the one that decides.
    final total = s?.totalOrders ?? 0;
    final inMine = s == null || mine == null ? null : ordersIn(s, mine);
    final liquidity = _Metric(
      figure: s == null ? '—' : '$total',
      figureColor:
          s == null
              ? book.textFaint
              : total == 0
              ? book.textTertiary
              : pal.figureLime,
      unit: inMine == null ? null : l10n.nodeOrdersInCurrency(inMine, mine!),
      unitColor: inMine == 0 && total > 0 ? pal.warnInk : book.textTertiary,
      label:
          s != null && total == 0
              ? l10n.nodeNoOrdersLabel
              : l10n.nodeOrdersNowLabel,
    );

    final fee = s?.feePct;
    final feeMetric = _Metric(
      figure: fee == null ? '—' : formatFeePct(fee, locale),
      figureColor: fee == null ? pal.stripText : book.textStrong,
      unit: fee == null ? null : '%',
      unitColor: pal.stripText,
      label: l10n.nodeFeeLabel,
      tooltip: l10n.nodeFeeTooltip,
    );

    final range = satsRange(s?.minOrderAmount, s?.maxOrderAmount, locale);
    final equivalent =
        mine == null
            ? null
            : fiatEquivalent(
              s?.minOrderAmount,
              s?.maxOrderAmount,
              btcPrice,
              locale,
            );
    final rangeMetric = _Metric(
      figure: range ?? '—',
      figureColor: range == null ? pal.stripText : book.textStrong,
      unit: range == null ? null : l10n.satsUnitLabel,
      unitColor: pal.stripText,
      label: l10n.nodePerTradeLabel,
      secondLine: equivalent == null ? null : '$equivalent $mine',
    );

    final columns = [liquidity, feeMetric, rangeMetric];
    final divider = Container(width: 1, color: dimmed(pal.colDivider, dim));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: dimmed(pal.inset, dim),
        borderRadius: BorderRadius.circular(12),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final scale = MediaQuery.textScalerOf(context).scale(1);
          final oneRow = constraints.maxWidth >= _minRowWidth * scale;
          Widget cell(_Metric m) =>
              Expanded(child: _MetricCell(metric: m, loading: loading));
          if (oneRow) {
            return IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  cell(columns[0]),
                  const SizedBox(width: 12),
                  divider,
                  const SizedBox(width: 12),
                  cell(columns[1]),
                  const SizedBox(width: 12),
                  divider,
                  const SizedBox(width: 12),
                  cell(columns[2]),
                ],
              ),
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    cell(columns[0]),
                    const SizedBox(width: 12),
                    divider,
                    const SizedBox(width: 12),
                    cell(columns[1]),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Container(height: 1, color: dimmed(pal.colDivider, dim)),
              const SizedBox(height: 10),
              _MetricCell(metric: columns[2], loading: loading),
            ],
          );
        },
      ),
    );
  }
}

class _Metric {
  const _Metric({
    required this.figure,
    required this.figureColor,
    required this.unit,
    required this.unitColor,
    required this.label,
    this.tooltip,
    this.secondLine,
  });

  final String figure;
  final Color figureColor;
  final String? unit;
  final Color unitColor;
  final String label;
  final String? tooltip;
  final String? secondLine;
}

class _MetricCell extends StatelessWidget {
  const _MetricCell({required this.metric, required this.loading});

  final _Metric metric;
  final bool loading;

  /// Height of the Manrope 16/700 figure line; the skeleton matches it so a
  /// loaded figure never shifts the layout.
  static const double _figureHeight = 20;

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    final pal = NodeSelectorPalette.of(context);
    final l10n = AppLocalizations.of(context);

    final Widget figure =
        loading
            ? Semantics(
              label: l10n.nodeStatsLoading,
              child: Shimmer.fromColors(
                baseColor: Color.alphaBlend(pal.chipNeutralBg, book.surface),
                highlightColor: Color.alphaBlend(book.chipBorder, book.surface),
                period: const Duration(milliseconds: 1800),
                child: Container(
                  width: 44,
                  height: _figureHeight - 4,
                  margin: const EdgeInsets.symmetric(vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            )
            : Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Flexible(
                  child: Text(
                    metric.figure,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: AppFonts.figures,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      height: _figureHeight / 16,
                      color: metric.figureColor,
                    ),
                  ),
                ),
                if (metric.unit != null) ...[
                  const SizedBox(width: 3),
                  Flexible(
                    child: Text(
                      metric.unit!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 10, color: metric.unitColor),
                    ),
                  ),
                ],
              ],
            );

    final label = Text(
      metric.label,
      style: TextStyle(fontSize: 10, color: pal.stripText),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 150),
          child: KeyedSubtree(
            key: ValueKey('${loading}_${metric.figure}_${metric.unit}'),
            child: figure,
          ),
        ),
        const SizedBox(height: 2),
        if (metric.tooltip != null)
          Tooltip(
            message: metric.tooltip!,
            triggerMode: TooltipTriggerMode.tap,
            child: label,
          )
        else
          label,
        if (metric.secondLine != null && !loading)
          Text(
            metric.secondLine!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 10, color: pal.stripText),
          ),
      ],
    );
  }
}

// ── Row 4 · trust ─────────────────────────────────────────────────────────────

class _TrustRow extends StatelessWidget {
  const _TrustRow({required this.stats, required this.dim});

  final MostroNodeStats? stats;
  final double dim;

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    final pal = NodeSelectorPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final s = stats;

    final custody = switch (s?.escrowMode) {
      'lightning' => l10n.nodeCustodyLightning,
      'cashu' => l10n.nodeCustodyCashu(_mintHost(s?.cashuMintUrl)),
      _ => l10n.nodeCustodyUnknown,
    };

    final (String? bond, Color bondColor) = switch (s?.bondRequired) {
      true => (l10n.nodeBondUnsupported, pal.warnInk),
      false => (l10n.nodeBondNone, book.textSecondary),
      null => (null, book.textSecondary),
    };

    return Container(
      padding: const EdgeInsets.only(top: 10),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: dimmed(pal.rowDivider, dim))),
      ),
      child: Row(
        children: [
          Icon(Icons.shield_outlined, size: 13, color: book.textTertiary),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              custody,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: book.textSecondary),
            ),
          ),
          if (bond != null) ...[
            const SizedBox(width: 8),
            Text(bond, style: TextStyle(fontSize: 11, color: bondColor)),
          ],
        ],
      ),
    );
  }

  /// `https://mint.cashu.space/` → `mint.cashu.space`. The mint changes who
  /// holds the sats, so it is always shown; a malformed URL is shown raw.
  static String _mintHost(String? url) {
    if (url == null) return '—';
    final host = Uri.tryParse(url)?.host;
    return (host == null || host.isEmpty) ? url : host;
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/src/rust/api/orders.dart' as orders_api;
import 'package:mostro/src/rust/api/types.dart';

/// Presets offered at the top of the create-order form.
enum OrderPreset { express, conservative, custom }

/// Currently selected preset in the create-order form.
final selectedOrderPresetProvider =
    StateProvider<OrderPreset>((_) => OrderPreset.custom);

/// Statuses that mean the trade finished successfully.
const _successStatuses = {
  OrderStatus.success,
  OrderStatus.settledHoldInvoice,
  OrderStatus.settledByAdmin,
  OrderStatus.completedByAdmin,
};

/// The user's most recent successful trade order, or `null` if none exists.
///
/// Used as the data source for the Express preset — its card is hidden
/// when this resolves to `null`.
final lastSuccessfulOrderProvider =
    FutureProvider.autoDispose<OrderInfo?>((ref) async {
  try {
    final trades = await orders_api.listTrades();
    final successful = trades
        .where((t) =>
            t.outcome == TradeOutcome.success ||
            _successStatuses.contains(t.order.status))
        .toList()
      ..sort((a, b) => (b.completedAt ?? b.startedAt)
          .compareTo(a.completedAt ?? a.startedAt));
    return successful.isEmpty ? null : successful.first.order;
  } catch (e) {
    debugPrint('[order presets] listTrades failed: $e');
    return null;
  }
});

/// "Start from a preset" section — Express / Conservative / Custom cards.
///
/// Presets only prefill the existing form fields via [onSelect]; the user
/// can still review and edit everything before submitting.
class OrderPresetSelector extends ConsumerWidget {
  const OrderPresetSelector({super.key, required this.onSelect});

  /// Called when a preset card is tapped. For Express, `expressSource` is
  /// the order to copy values from; it is `null` for the other presets.
  final void Function(OrderPreset preset, OrderInfo? expressSource) onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<AppColors>();
    final green = colors?.mostroGreen ?? const Color(0xFF8CC63F);
    final blue = colors?.blueAccent ?? const Color(0xFF60A5FA);
    final purple = colors?.purpleButton ?? const Color(0xFF8359C2);
    final cardBg = colors?.backgroundCard ?? const Color(0xFF1E2230);
    final selected = ref.watch(selectedOrderPresetProvider);
    final lastOrder = ref.watch(lastSuccessfulOrderProvider).valueOrNull;
    final l10n = AppLocalizations.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.startFromPreset,
          style: TextStyle(
            fontSize: 11,
            letterSpacing: 1,
            color: colors?.textSubtle,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        if (lastOrder != null) ...[
          _PresetCard(
            cardBg: cardBg,
            iconData: Icons.bolt,
            iconColor: green,
            title: l10n.presetExpressTitle,
            subtitle: _expressSubtitle(lastOrder, l10n),
            tag: l10n.recommendedTag,
            tagColor: green,
            selected: selected == OrderPreset.express,
            highlightColor: green,
            onTap: () => onSelect(OrderPreset.express, lastOrder),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        _PresetCard(
          cardBg: cardBg,
          iconData: Icons.shield_outlined,
          iconColor: blue,
          title: l10n.presetConservativeTitle,
          subtitle: l10n.presetConservativeSubtitle,
          selected: selected == OrderPreset.conservative,
          highlightColor: green,
          onTap: () => onSelect(OrderPreset.conservative, null),
        ),
        const SizedBox(height: AppSpacing.sm),
        _PresetCard(
          cardBg: cardBg,
          iconData: Icons.settings,
          iconColor: purple,
          title: l10n.presetCustomTitle,
          subtitle: l10n.presetCustomSubtitle,
          selected: selected == OrderPreset.custom,
          highlightColor: green,
          onTap: () => onSelect(OrderPreset.custom, null),
        ),
      ],
    );
  }

  /// "Same as your last successful order — 50 ARS, MP, 0% premium".
  static String _expressSubtitle(OrderInfo order, AppLocalizations l10n) {
    final parts = <String>[];
    if (order.fiatAmount != null) {
      parts.add('${_formatNum(order.fiatAmount!)} ${order.fiatCode}');
    } else if (order.fiatAmountMin != null && order.fiatAmountMax != null) {
      parts.add('${_formatNum(order.fiatAmountMin!)}–'
          '${_formatNum(order.fiatAmountMax!)} ${order.fiatCode}');
    } else {
      parts.add(order.fiatCode);
    }
    final firstMethod = order.paymentMethod
        .split(',')
        .map((m) => m.trim())
        .where((m) => m.isNotEmpty)
        .firstOrNull;
    if (firstMethod != null) parts.add(firstMethod);
    final p = order.premium;
    parts.add(l10n.expressPremiumSuffix('${p > 0 ? '+' : ''}${_formatNum(p)}'));
    return l10n.expressPresetSubtitle(parts.join(', '));
  }

  static String _formatNum(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();
}

class _PresetCard extends StatelessWidget {
  const _PresetCard({
    required this.cardBg,
    required this.iconData,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.highlightColor,
    required this.onTap,
    this.tag,
    this.tagColor,
  });

  final Color cardBg;
  final IconData iconData;
  final Color iconColor;
  final String title;
  final String subtitle;
  final String? tag;
  final Color? tagColor;
  final bool selected;
  final Color highlightColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>();

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(
            color: selected ? highlightColor : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(iconData, size: 20, color: iconColor),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (tag != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: (tagColor ?? highlightColor)
                          .withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(AppRadius.chip),
                    ),
                    child: Text(
                      tag!,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: tagColor ?? highlightColor,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 12,
                height: 1.5,
                color: colors?.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

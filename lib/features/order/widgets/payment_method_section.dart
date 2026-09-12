import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mostro/core/automation/automation_id.dart';
import 'package:mostro/core/automation/automation_ids.dart';
import 'package:mostro/core/create_order_palette.dart';
import 'package:mostro/core/order_book_palette.dart';
import 'package:mostro/features/order/providers/payment_methods_provider.dart';
import 'package:mostro/features/order/screens/payment_method_picker_screen.dart';
import 'package:mostro/features/order/widgets/currency_section.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/widgets/dashed_border.dart';

/// Catalogue payment methods chosen for the order being created.
final selectedPaymentMethodsProvider = StateProvider<List<String>>((_) => []);

/// Free-text payment methods the user added themselves. Kept apart from the
/// catalogue ones so a currency change prunes only the latter.
final customPaymentMethodsProvider = StateProvider<List<String>>((_) => []);

/// Every method the order will carry, catalogue first.
final allPaymentMethodsProvider = Provider<List<String>>(
  (ref) => [
    ...ref.watch(selectedPaymentMethodsProvider),
    ...ref.watch(customPaymentMethodsProvider),
  ],
);

/// Characters a free-text method may not carry: the wire joins methods with
/// commas, and brackets, braces and quotes would break a naive reader.
final _forbiddenInCustomMethod = RegExp(r'[,"\\\[\]{}]');

/// The custom method as it will be sent: forbidden characters and runs of
/// whitespace collapsed to one space, trimmed. Empty when nothing is left.
String sanitizeCustomMethod(String raw) =>
    raw
        .replaceAll(_forbiddenInCustomMethod, ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

/// "Payment methods" card: the chosen methods as lime chips plus a dashed
/// `Add` chip that opens [PaymentMethodPickerScreen]. Only what the user
/// needs to review before publishing is on the main screen.
class PaymentMethodSection extends ConsumerWidget {
  const PaymentMethodSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // When the currency changes, drop any catalogue methods that are not
    // valid for the new currency (custom entries are left untouched).
    ref.listen<String>(selectedFiatCodeProvider, (_, next) {
      // Don't prune while the asset is still loading: the provider returns an
      // empty list during load, which would wipe every selection.
      if (!ref.read(paymentMethodsDataProvider).hasValue) return;
      final valid = ref.read(paymentMethodsForCurrencyProvider(next)).toSet();
      final current = ref.read(selectedPaymentMethodsProvider);
      final pruned = current.where(valid.contains).toList();
      if (pruned.length != current.length) {
        ref.read(selectedPaymentMethodsProvider.notifier).state = pruned;
      }
    });

    final selected = ref.watch(selectedPaymentMethodsProvider);
    final custom = ref.watch(customPaymentMethodsProvider);
    final palette = OrderBookPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final count = selected.length + custom.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.paymentMethodsLabel,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: palette.textStrong,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              l10n.paymentMethodsChosenCount(count),
              style: TextStyle(fontSize: 11, color: palette.textFaint),
            ),
          ],
        ),
        const SizedBox(height: 11),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final method in selected)
              _ChosenMethodChip(
                label: method,
                onRemove:
                    () =>
                        ref
                                .read(selectedPaymentMethodsProvider.notifier)
                                .state =
                            selected.where((m) => m != method).toList(),
              ),
            for (final method in custom)
              _ChosenMethodChip(
                label: method,
                onRemove:
                    () =>
                        ref.read(customPaymentMethodsProvider.notifier).state =
                            custom.where((m) => m != method).toList(),
              ),
            _AddMethodChip(
              onTap:
                  () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const PaymentMethodPickerScreen(),
                    ),
                  ),
            ).withAutomationId(AutomationIds.orderCreatePaymentMethodAdd),
          ],
        ),
      ],
    );
  }
}

/// A confirmed method: lime tint, like everything else the user has chosen.
class _ChosenMethodChip extends StatelessWidget {
  const _ChosenMethodChip({required this.label, required this.onRemove});

  final String label;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final palette = OrderBookPalette.of(context);

    return Semantics(
      container: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 2, 4, 2),
        decoration: BoxDecoration(
          color: palette.bestChipFill,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: palette.bestChipBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: palette.limeInk,
              ),
            ),
            const SizedBox(width: 2),
            // The glyph is 12dp; the tappable area around it is larger and
            // announced on its own, apart from the chip's label.
            Semantics(
              button: true,
              label: AppLocalizations.of(context).removePaymentMethod(label),
              child: InkWell(
                onTap: onRemove,
                borderRadius: BorderRadius.circular(999),
                child: SizedBox(
                  width: 28,
                  height: 28,
                  child: Icon(Icons.close, size: 12, color: palette.limeText),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Dashed `+ Add` chip.
class _AddMethodChip extends StatelessWidget {
  const _AddMethodChip({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = OrderBookPalette.of(context);
    final create = CreateOrderPalette.of(context);
    final l10n = AppLocalizations.of(context);

    return CustomPaint(
      foregroundPainter: DashedBorderPainter(
        color: create.dashedBorder,
        radius: null,
      ),
      child: Material(
        color: palette.chipFill,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.add, size: 12, color: palette.limeIcon),
                const SizedBox(width: 6),
                Text(
                  l10n.paymentMethodAdd,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: palette.textBody,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

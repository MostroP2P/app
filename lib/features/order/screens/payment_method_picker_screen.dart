import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/core/automation/automation_id.dart';
import 'package:mostro/core/automation/automation_ids.dart';
import 'package:mostro/core/create_order_palette.dart';
import 'package:mostro/features/order/providers/payment_methods_provider.dart';
import 'package:mostro/features/order/widgets/currency_section.dart';
import 'package:mostro/features/order/widgets/payment_method_section.dart';
import 'package:mostro/features/order/widgets/underline_amount_field.dart';
import 'package:mostro/l10n/app_localizations.dart';

/// Full-screen payment-method picker for the create-order form.
///
/// A screen and not a sheet because the per-currency list is long and the
/// custom-method field needs the keyboard open without the sheet resizing
/// under it. Every tap writes straight to the form's providers, so going
/// back always keeps what was chosen.
class PaymentMethodPickerScreen extends ConsumerStatefulWidget {
  const PaymentMethodPickerScreen({super.key});

  @override
  ConsumerState<PaymentMethodPickerScreen> createState() =>
      _PaymentMethodPickerScreenState();
}

class _PaymentMethodPickerScreenState
    extends ConsumerState<PaymentMethodPickerScreen> {
  final _customController = TextEditingController();
  String _query = '';
  String _customDraft = '';

  @override
  void dispose() {
    _customController.dispose();
    super.dispose();
  }

  void _toggle(String method) {
    final notifier = ref.read(selectedPaymentMethodsProvider.notifier);
    final current = notifier.state;
    notifier.state = current.contains(method)
        ? current.where((m) => m != method).toList()
        : [...current, method];
  }

  void _removeCustom(String method) {
    final notifier = ref.read(customPaymentMethodsProvider.notifier);
    notifier.state = notifier.state.where((m) => m != method).toList();
  }

  void _addCustom() {
    final sanitized = sanitizeCustomMethod(_customController.text);
    if (sanitized.isEmpty) return;
    final notifier = ref.read(customPaymentMethodsProvider.notifier);
    if (!notifier.state.contains(sanitized)) {
      notifier.state = [...notifier.state, sanitized];
    }
    _customController.clear();
    setState(() => _customDraft = '');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = OrderBookPalette.of(context);
    final create = CreateOrderPalette.of(context);
    final fiatCode = ref.watch(selectedFiatCodeProvider);
    final catalogue = ref.watch(paymentMethodsForCurrencyProvider(fiatCode));
    final selected = ref.watch(selectedPaymentMethodsProvider);
    final custom = ref.watch(customPaymentMethodsProvider);

    final query = _query.trim().toLowerCase();
    final visible = query.isEmpty
        ? catalogue
        : catalogue.where((m) => m.toLowerCase().contains(query)).toList();
    final canAddCustom = sanitizeCustomMethod(_customDraft).isNotEmpty;

    return Scaffold(
      backgroundColor: palette.bg,
      appBar: AppBar(
        backgroundColor: palette.bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, size: 22, color: palette.textBody),
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        titleSpacing: 0,
        title: Text(
          l10n.paymentMethodsLabel,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
            color: palette.textPrimary,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 4, 18, 32),
        children: [
          Material(
            color: create.inset,
            borderRadius: BorderRadius.circular(12),
            child: TextField(
              autocorrect: false,
              enableSuggestions: false,
              style: TextStyle(fontSize: 14, color: palette.textPrimary),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                hintText: l10n.paymentMethodSearchHint,
                hintStyle: TextStyle(fontSize: 14, color: palette.textFaint),
                prefixIcon: Icon(Icons.search, size: 18, color: palette.sortLabel),
              ),
              onChanged: (v) => setState(() => _query = v),
            ).withAutomationId(AutomationIds.orderCreatePaymentMethodSearch),
          ),
          const SizedBox(height: 8),
          for (final method in visible)
            _MethodRow(
              label: method,
              isSelected: selected.contains(method),
              onTap: () => _toggle(method),
            ).withAutomationId(
              AutomationIds.orderCreatePaymentMethodOption(method),
            ),
          for (final method in custom)
            _MethodRow(
              label: method,
              isSelected: true,
              onTap: () => _removeCustom(method),
            ),
          const SizedBox(height: 24),
          Text(
            l10n.customPaymentMethodLabel,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: palette.textStrong,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: UnderlineAmountField(
                  controller: _customController,
                  valueFontSize: 19,
                  keyboardType: TextInputType.text,
                  textInputAction: TextInputAction.done,
                  hintText: l10n.customPaymentMethodHint,
                  onChanged: (v) => setState(() => _customDraft = v),
                  onSubmitted: (_) => _addCustom(),
                ).withAutomationId(AutomationIds.orderCreatePaymentMethod),
              ),
              const SizedBox(width: 12),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: FilledButton(
                  onPressed: canAddCustom ? _addCustom : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: palette.lime,
                    foregroundColor: palette.onLime,
                    disabledBackgroundColor: create.ctaDisabledBg,
                    disabledForegroundColor: create.ctaDisabledInk,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    minimumSize: Size.zero,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999),
                    ),
                    textStyle: const TextStyle(
                      fontFamily: AppFonts.ui,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  child: Text(l10n.paymentMethodAdd),
                ).withAutomationId(
                  AutomationIds.orderCreatePaymentMethodCustomAdd,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MethodRow extends StatelessWidget {
  const _MethodRow({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = OrderBookPalette.of(context);

    return Semantics(
      selected: isSelected,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    color: isSelected ? palette.limeInk : palette.textBody,
                  ),
                ),
              ),
              if (isSelected)
                Icon(Icons.check, size: 18, color: palette.limeText),
            ],
          ),
        ),
      ),
    );
  }
}

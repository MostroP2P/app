import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/core/automation/automation_id.dart';
import 'package:mostro/core/automation/automation_ids.dart';
import 'package:mostro/core/create_order_palette.dart';
import 'package:mostro/features/order/providers/payment_methods_provider.dart';
import 'package:mostro/features/order/widgets/currency_section.dart';
import 'package:mostro/features/order/widgets/payment_method_section.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/widgets/mostro_modal.dart';
import 'package:mostro/shared/widgets/dashed_border.dart';

/// Full-screen payment-method picker for the create-order form (handoff 18a).
///
/// A screen and not a sheet because the per-currency list is long and the
/// custom-method sheet needs the keyboard open without a sheet resizing under
/// it. Selection is a **draft**: taps write to local state, `Confirm methods`
/// is the only path back into the form's providers and the back arrow
/// cancels — asking first when there is something to lose.
class PaymentMethodPickerScreen extends ConsumerStatefulWidget {
  const PaymentMethodPickerScreen({super.key});

  @override
  ConsumerState<PaymentMethodPickerScreen> createState() =>
      _PaymentMethodPickerScreenState();
}

class _PaymentMethodPickerScreenState
    extends ConsumerState<PaymentMethodPickerScreen> {
  /// Catalogue methods and free-text ones, kept apart exactly as the
  /// providers keep them: a currency change prunes only the former.
  late List<String> _selected;
  late List<String> _custom;
  late List<String> _initialSelected;
  late List<String> _initialCustom;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _initialSelected = ref.read(selectedPaymentMethodsProvider);
    _initialCustom = ref.read(customPaymentMethodsProvider);
    _selected = [..._initialSelected];
    _custom = [..._initialCustom];
  }

  int get _count => _selected.length + _custom.length;

  bool get _isDirty =>
      !listEquals(_selected, _initialSelected) ||
      !listEquals(_custom, _initialCustom);

  void _toggle(String method) {
    HapticFeedback.selectionClick();
    setState(() {
      _selected =
          _selected.contains(method)
              ? _selected.where((m) => m != method).toList()
              : [..._selected, method];
    });
  }

  void _removeCustom(String method) {
    HapticFeedback.selectionClick();
    setState(() => _custom = _custom.where((m) => m != method).toList());
  }

  /// Drops [method] from whichever of the two drafts holds it, so the summary
  /// chip's "×" needs no knowledge of where the method came from.
  void _remove(String method) {
    if (_custom.contains(method)) {
      _removeCustom(method);
    } else {
      _toggle(method);
    }
  }

  void _confirm() {
    ref.read(selectedPaymentMethodsProvider.notifier).state = _selected;
    ref.read(customPaymentMethodsProvider.notifier).state = _custom;
    Navigator.of(context).pop();
  }

  Future<void> _openCustomSheet() async {
    final added = await showMostroSheet<String>(
      context: context,
      builder: (_) => const _CustomMethodSheet(),
    );
    if (added == null || !mounted) return;
    _addCustom(added);
  }

  /// A name the catalogue already has selects that entry instead of adding a
  /// look-alike custom row: two "Zelle" rows would behave differently on tap
  /// and the order would carry the method twice.
  void _addCustom(String sanitized) {
    final fiatCode = ref.read(selectedFiatCodeProvider);
    final catalogue = ref.read(paymentMethodsForCurrencyProvider(fiatCode));
    final match = catalogue.cast<String?>().firstWhere(
      (m) => m!.toLowerCase() == sanitized.toLowerCase(),
      orElse: () => null,
    );
    setState(() {
      if (match != null) {
        if (!_selected.contains(match)) _selected = [..._selected, match];
      } else if (!_custom.any(
        (m) => m.toLowerCase() == sanitized.toLowerCase(),
      )) {
        _custom = [..._custom, sanitized];
      }
    });
  }

  /// Back — arrow or system gesture — cancels. Returns true when the screen
  /// may close: either nothing changed or the user chose to discard.
  Future<bool> _confirmDiscard() async {
    if (!_isDirty) return true;
    final l10n = AppLocalizations.of(context);
    final discard = await showMostroDialog<bool>(
      context: context,
      builder:
          (dialogContext) => MostroDialog(
            title: l10n.paymentMethodsDiscardTitle,
            secondary: ModalAction(
              label: l10n.paymentMethodsKeepEditing,
              onPressed: () => Navigator.of(dialogContext).pop(false),
            ),
            primary: ModalAction(
              label: l10n.paymentMethodsDiscardConfirm,
              onPressed: () => Navigator.of(dialogContext).pop(true),
            ),
          ),
    );
    return discard ?? false;
  }

  Future<void> _back() async {
    if (await _confirmDiscard() && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = OrderBookPalette.of(context);
    final create = CreateOrderPalette.of(context);
    final fiatCode = ref.watch(selectedFiatCodeProvider);
    final catalogue = ref.watch(paymentMethodsForCurrencyProvider(fiatCode));

    final query = _query.trim().toLowerCase();
    // Filtering narrows the list only: what is already chosen stays visible
    // in the summary above and in the count below.
    final visible =
        query.isEmpty
            ? catalogue
            : catalogue.where((m) => m.toLowerCase().contains(query)).toList();
    final visibleCustom =
        query.isEmpty
            ? _custom
            : _custom.where((m) => m.toLowerCase().contains(query)).toList();
    final chosen = [..._selected, ..._custom];

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        backgroundColor: palette.bg,
        appBar: AppBar(
          backgroundColor: palette.bg,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: Icon(Icons.arrow_back, size: 22, color: palette.textBody),
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            onPressed: _back,
          ).withAutomationId(AutomationIds.appBarBack),
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
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 16),
          children: [
            _SearchField(
              onChanged: (v) => setState(() => _query = v),
            ).withAutomationId(AutomationIds.orderCreatePaymentMethodSearch),
            // With nothing chosen the whole block goes, label included.
            if (chosen.isNotEmpty) ...[
              const SizedBox(height: 14),
              _ChosenSummary(methods: chosen, onRemove: _remove),
            ],
            const SizedBox(height: 14),
            // Keyed, or the list reconciles by position: filtering the row
            // above away would hand a method's 120ms tint animation to a
            // different one. The prefix keeps a custom method apart from a
            // catalogue entry of the same name — a currency switch can put
            // both in the list, and two equal keys throw.
            for (final method in visible)
              Padding(
                key: ValueKey(method),
                padding: const EdgeInsets.only(bottom: 6),
                child: _MethodRow(
                  label: method,
                  isSelected: _selected.contains(method),
                  onTap: () => _toggle(method),
                ).withAutomationId(
                  AutomationIds.orderCreatePaymentMethodOption(method),
                ),
              ),
            for (final method in visibleCustom)
              Padding(
                key: ValueKey('custom-$method'),
                padding: const EdgeInsets.only(bottom: 6),
                child: _MethodRow(
                  label: method,
                  isSelected: true,
                  onTap: () => _removeCustom(method),
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: _AddCustomRow(onTap: _openCustomSheet).withAutomationId(
                AutomationIds.orderCreatePaymentMethodCustomOpen,
              ),
            ),
          ],
        ),
        bottomNavigationBar: DecoratedBox(
          decoration: BoxDecoration(
            color: palette.surfaceNav,
            border: Border(top: BorderSide(color: palette.navBorder)),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l10n.paymentMethodsSelectedCount(_count),
                    style: TextStyle(
                      fontSize: 12,
                      color: palette.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: _count == 0 ? null : _confirm,
                    style: FilledButton.styleFrom(
                      backgroundColor: palette.lime,
                      foregroundColor: palette.onLime,
                      disabledBackgroundColor: create.ctaDisabledBg,
                      disabledForegroundColor: create.ctaDisabledInk,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      textStyle: const TextStyle(
                        fontFamily: AppFonts.ui,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    child: Text(l10n.paymentMethodsConfirm),
                  ).withAutomationId(
                    AutomationIds.orderCreatePaymentMethodsConfirm,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Rounded search box that filters the list by name as it is typed.
class _SearchField extends StatelessWidget {
  const _SearchField({required this.onChanged});

  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = OrderBookPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: palette.border),
    );

    return Material(
      color: palette.surface,
      borderRadius: BorderRadius.circular(14),
      child: TextField(
        autocorrect: false,
        enableSuggestions: false,
        style: TextStyle(fontSize: 14, color: palette.textPrimary),
        decoration: InputDecoration(
          isDense: true,
          border: border,
          enabledBorder: border,
          focusedBorder: border,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 13,
            vertical: 11,
          ),
          hintText: l10n.paymentMethodSearchHint,
          hintStyle: TextStyle(fontSize: 13.5, color: palette.textFaint),
          prefixIcon: Icon(Icons.search, size: 16, color: palette.textTertiary),
        ),
        onChanged: onChanged,
      ),
    );
  }
}

/// `Chosen` + one lime chip per method, each removable. Hidden altogether
/// when nothing is chosen.
class _ChosenSummary extends StatelessWidget {
  const _ChosenSummary({required this.methods, required this.onRemove});

  final List<String> methods;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    final palette = OrderBookPalette.of(context);
    final l10n = AppLocalizations.of(context);

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          l10n.paymentMethodsChosenLabel,
          style: TextStyle(fontSize: 12, color: palette.textSecondary),
        ),
        for (final method in methods)
          Container(
            padding: const EdgeInsets.fromLTRB(9, 5, 4, 5),
            decoration: BoxDecoration(
              color: palette.bestChipFill,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: palette.bestChipBorder),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  method,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: palette.limeInk,
                  ),
                ),
                // The glyph is 11dp; the tappable area around it is larger
                // and announced on its own, apart from the chip's label.
                Semantics(
                  container: true,
                  button: true,
                  label: l10n.removePaymentMethod(method),
                  child: InkWell(
                    onTap: () => onRemove(method),
                    borderRadius: BorderRadius.circular(999),
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: Icon(
                        Icons.close,
                        size: 11,
                        color: palette.limeText,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// One method in the list: a checkbox and its name, the whole row tappable.
class _MethodRow extends StatelessWidget {
  const _MethodRow({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  static const _transition = Duration(milliseconds: 120);

  @override
  Widget build(BuildContext context) {
    final palette = OrderBookPalette.of(context);
    final create = CreateOrderPalette.of(context);

    return Semantics(
      checked: isSelected,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: _transition,
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: isSelected ? create.pickerRowSelectedBg : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color:
                  isSelected
                      ? create.pickerRowSelectedBorder
                      : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              AnimatedContainer(
                duration: _transition,
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: isSelected ? palette.lime : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color:
                        isSelected ? palette.lime : create.pickerCheckboxBorder,
                    width: 1.5,
                  ),
                ),
                child:
                    isSelected
                        ? Icon(Icons.check, size: 13, color: palette.onLime)
                        : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    color: isSelected ? palette.textPrimary : palette.textBody,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Dashed row closing the list: opens the free-text sheet.
class _AddCustomRow extends StatelessWidget {
  const _AddCustomRow({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = OrderBookPalette.of(context);
    final create = CreateOrderPalette.of(context);
    final l10n = AppLocalizations.of(context);

    return CustomPaint(
      foregroundPainter: DashedBorderPainter(
        color: create.dashedBorder,
        radius: 14,
      ),
      child: Material(
        color: create.inset,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            constraints: const BoxConstraints(minHeight: 44),
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
            child: Row(
              children: [
                Icon(Icons.add, size: 15, color: palette.textSecondary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    l10n.paymentMethodAddCustom,
                    style: TextStyle(
                      fontSize: 13.5,
                      color: palette.textSecondary,
                    ),
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

/// Bottom sheet that turns free text into a method. Pops the sanitized name,
/// or null when nothing usable was typed.
class _CustomMethodSheet extends StatefulWidget {
  const _CustomMethodSheet();

  @override
  State<_CustomMethodSheet> createState() => _CustomMethodSheetState();
}

class _CustomMethodSheetState extends State<_CustomMethodSheet> {
  final _controller = TextEditingController();
  String _draft = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final sanitized = sanitizeCustomMethod(_controller.text);
    if (sanitized.isEmpty) return;
    Navigator.of(context).pop(sanitized);
  }

  @override
  Widget build(BuildContext context) {
    final palette = OrderBookPalette.of(context);
    final create = CreateOrderPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final canAdd = sanitizeCustomMethod(_draft).isNotEmpty;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: palette.border),
    );

    return MostroSheet(
      title: l10n.customPaymentMethodLabel,
      content: TextField(
        controller: _controller,
        autofocus: true,
        autocorrect: false,
        enableSuggestions: false,
        textInputAction: TextInputAction.done,
        style: TextStyle(fontSize: 15, color: palette.textPrimary),
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: create.inset,
          border: border,
          enabledBorder: border,
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: palette.lime),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 13,
            vertical: 13,
          ),
          hintText: l10n.customPaymentMethodHint,
          hintStyle: TextStyle(fontSize: 14, color: palette.textFaint),
        ),
        onChanged: (v) => setState(() => _draft = v),
        onSubmitted: (_) => _submit(),
      ).withAutomationId(AutomationIds.orderCreatePaymentMethod),
      primary: ModalAction(
        label: l10n.paymentMethodAdd,
        onPressed: canAdd ? _submit : null,
        automationId: AutomationIds.orderCreatePaymentMethodCustomAdd,
      ),
    );
  }
}

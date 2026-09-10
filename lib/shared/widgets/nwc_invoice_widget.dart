import 'package:flutter/material.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/core/automation/automation_id.dart';
import 'package:mostro/core/automation/automation_ids.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/src/rust/api/nwc.dart' as nwc_api;

/// Auto-generates a Lightning invoice via NWC when wallet is connected.
///
/// Shows loading state while generating. Calls [onInvoiceConfirmed] when
/// the invoice is ready, or [onFallbackToManual] on failure.
class NwcInvoiceWidget extends StatefulWidget {
  const NwcInvoiceWidget({
    super.key,
    required this.amountSats,
    required this.onInvoiceConfirmed,
    required this.onFallbackToManual,
    this.generateInvoice,
  });

  final int amountSats;
  final ValueChanged<String> onInvoiceConfirmed;
  final VoidCallback onFallbackToManual;

  /// Asks the connected wallet for an invoice. Defaults to NWC; injected by
  /// tests, which have no bridge to call.
  final Future<String> Function(int amountSats)? generateInvoice;

  @override
  State<NwcInvoiceWidget> createState() => _NwcInvoiceWidgetState();
}

class _NwcInvoiceWidgetState extends State<NwcInvoiceWidget> {
  bool _loading = true;
  bool _hasError = false;

  /// The generated invoice, kept only so the `invoice.nwc.text` readout can
  /// expose it. It is already on its way to the daemon by then; automation
  /// reads it to correlate the payment it is about to observe.
  String? _bolt11;

  @override
  void initState() {
    super.initState();
    _generateInvoice();
  }

  Future<void> _generateInvoice() async {
    try {
      final generate = widget.generateInvoice ?? _makeInvoiceOverNwc;
      final bolt11 = await generate(widget.amountSats);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _bolt11 = bolt11;
      });
      widget.onInvoiceConfirmed(bolt11);
    } catch (e) {
      debugPrint('NWC invoice generation failed: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _hasError = true;
        // Submitting can throw after the invoice was generated. Nothing
        // reached the daemon then, so there is nothing to read back — and a
        // readout left behind would report a success that did not happen.
        _bolt11 = null;
      });
      widget.onFallbackToManual();
    }
  }

  static Future<String> _makeInvoiceOverNwc(int amountSats) =>
      nwc_api.makeInvoice(
        amountSats: BigInt.from(amountSats),
        description: null,
      );

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>();
    final green = colors?.mostroGreen ?? const Color(0xFF8CC63F);

    if (_loading) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: green),
          const SizedBox(height: AppSpacing.md),
          Text(
            AppLocalizations.of(context).generatingInvoiceNwc,
            style: TextStyle(color: colors?.textSecondary),
          ),
        ],
      );
    }

    // Checked before the readout: an error is the state that must win, so a
    // future path that forgets to clear the invoice still cannot render a
    // success that did not happen.
    if (_hasError) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.warning_amber, color: colors?.destructiveRed, size: 32),
          const SizedBox(height: AppSpacing.sm),
          Text(
            AppLocalizations.of(context).unableToGenerateInvoice,
            style: TextStyle(color: colors?.textSecondary, fontSize: 12),
          ),
        ],
      );
    }

    final bolt11 = _bolt11;
    if (bolt11 != null) {
      // Nothing is drawn: the screen is already leaving. The node exists so a
      // driver can read the invoice it just submitted.
      return const SizedBox.shrink().withAutomationId(
        AutomationIds.invoiceNwcText,
        label: bolt11,
      );
    }

    return const SizedBox.shrink();
  }
}

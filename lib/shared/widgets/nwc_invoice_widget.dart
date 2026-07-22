import 'package:flutter/material.dart';

import 'package:mostro/core/app_theme.dart';
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
  });

  final int amountSats;
  final ValueChanged<String> onInvoiceConfirmed;
  final VoidCallback onFallbackToManual;

  @override
  State<NwcInvoiceWidget> createState() => _NwcInvoiceWidgetState();
}

class _NwcInvoiceWidgetState extends State<NwcInvoiceWidget> {
  bool _loading = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _generateInvoice();
  }

  Future<void> _generateInvoice() async {
    try {
      final bolt11 = await nwc_api.makeInvoice(
        amountSats: BigInt.from(widget.amountSats),
        description: null,
      );
      if (!mounted) return;
      setState(() => _loading = false);
      widget.onInvoiceConfirmed(bolt11);
    } catch (e) {
      debugPrint('NWC invoice generation failed: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _hasError = true;
      });
      widget.onFallbackToManual();
    }
  }

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

    return const SizedBox.shrink();
  }
}

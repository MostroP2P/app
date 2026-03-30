import 'package:flutter/material.dart';

import 'package:mostro/core/app_theme.dart';

/// Auto-generates a Lightning invoice via NWC when wallet is connected.
///
/// Shows loading state while generating. Calls [onInvoiceConfirmed] when
/// the invoice is ready, or [onFallbackToManual] on failure.
///
/// TODO: Wire to NWC wallet bridge in Phase 14.
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
  String? _error;

  @override
  void initState() {
    super.initState();
    _generateInvoice();
  }

  Future<void> _generateInvoice() async {
    try {
      // TODO: Call NWC make_invoice(amount_sats) via Rust bridge.
      // When wired, this will await the actual NWC response.

      if (!mounted) return;

      // NWC not configured — fall back to manual entry immediately.
      setState(() => _loading = false);
      widget.onFallbackToManual();
    } catch (e, stack) {
      debugPrint('NWC invoice generation failed: $e\n$stack');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Unable to generate invoice automatically';
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
            'Generating invoice via NWC...',
            style: TextStyle(color: colors?.textSecondary),
          ),
        ],
      );
    }

    if (_error != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.warning_amber, color: colors?.destructiveRed, size: 32),
          const SizedBox(height: AppSpacing.sm),
          Text(
            _error!,
            style: TextStyle(color: colors?.textSecondary, fontSize: 12),
          ),
        ],
      );
    }

    return const SizedBox.shrink();
  }
}

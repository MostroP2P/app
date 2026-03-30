import 'package:flutter/material.dart';

import 'package:mostro/core/app_theme.dart';

/// NWC auto-pay widget — single "Pay with Wallet" button.
///
/// Calls NWC pay_invoice(bolt11) via Rust bridge.
/// On success → [onPaymentSuccess]. On failure → [onFallbackToManual].
///
/// TODO: Wire to NWC wallet bridge in Phase 14.
class NwcPaymentWidget extends StatefulWidget {
  const NwcPaymentWidget({
    super.key,
    required this.bolt11,
    required this.amountSats,
    required this.onPaymentSuccess,
    required this.onFallbackToManual,
  });

  final String bolt11;
  final int amountSats;
  final VoidCallback onPaymentSuccess;
  final VoidCallback onFallbackToManual;

  @override
  State<NwcPaymentWidget> createState() => _NwcPaymentWidgetState();
}

class _NwcPaymentWidgetState extends State<NwcPaymentWidget> {
  bool _paying = false;

  Future<void> _pay() async {
    setState(() => _paying = true);
    try {
      // TODO: Call nwc_api.pay_invoice(bolt11) via Rust bridge.
      await Future.delayed(const Duration(seconds: 1));

      if (!mounted) return;
      // Placeholder — fall back to manual until NWC is wired.
      widget.onFallbackToManual();
    } catch (e) {
      debugPrint('NWC payment failed: $e');
      if (!mounted) return;
      widget.onFallbackToManual();
    } finally {
      if (mounted) setState(() => _paying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>();
    final green = colors?.mostroGreen ?? const Color(0xFF8CC63F);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _paying ? null : _pay,
            icon: _paying
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.account_balance_wallet, size: 20),
            label: Text(_paying ? 'Paying...' : 'Pay with Wallet'),
            style: FilledButton.styleFrom(
              backgroundColor: green,
              foregroundColor: Colors.black,
              minimumSize: const Size(0, 56),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.button),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          '${widget.amountSats} sats',
          style: TextStyle(
            color: colors?.textSecondary,
            fontSize: 13,
          ),
        ),
      ],
    );
  }
}

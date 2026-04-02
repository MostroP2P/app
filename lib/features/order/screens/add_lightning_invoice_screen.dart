import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:mostro/core/app_routes.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/order/providers/trade_state_provider.dart';
import 'package:mostro/features/settings/providers/nwc_provider.dart';
import 'package:mostro/shared/widgets/nwc_invoice_widget.dart';
import 'package:mostro/src/rust/api/orders.dart' as orders_api;

/// Add Lightning Invoice screen — Route `/add_invoice/:orderId`.
///
/// Buyer enters a Lightning invoice (or it's pre-filled from settings).
/// Shown when NWC is NOT configured.
class AddLightningInvoiceScreen extends ConsumerStatefulWidget {
  const AddLightningInvoiceScreen({
    super.key,
    required this.orderId,
    this.amountSats,
  });

  final String orderId;
  /// Sats amount for the invoice. `null` until the trade provider resolves it.
  final int? amountSats;

  @override
  ConsumerState<AddLightningInvoiceScreen> createState() =>
      _AddLightningInvoiceScreenState();
}

class _AddLightningInvoiceScreenState
    extends ConsumerState<AddLightningInvoiceScreen> {
  final _invoiceController = TextEditingController();
  bool _submitting = false;
  /// `true` when NWC is connected but generation failed → show manual form.
  bool _manualMode = false;

  @override
  void dispose() {
    _invoiceController.dispose();
    super.dispose();
  }

  BigInt? _resolvedSats(WidgetRef ref) {
    final fromProvider = ref.watch(tradeAmountProvider(widget.orderId)).valueOrNull;
    if (fromProvider != null) return fromProvider;
    final fallback = widget.amountSats;
    return fallback != null ? BigInt.from(fallback) : null;
  }

  bool _isLnAddress(String text) => text.contains('@');

  bool _isValid(WidgetRef ref) {
    final text = _invoiceController.text.trim();
    if (text.isEmpty) return false;
    // Lightning Address requires a known sats amount before submission.
    if (_isLnAddress(text) && _resolvedSats(ref) == null) return false;
    return true;
  }

  Future<void> _submit(WidgetRef ref) async {
    if (_submitting) return;
    final input = _invoiceController.text.trim();
    // For Lightning Addresses, the sats amount must be resolved before sending —
    // the Rust side uses it to resolve the address. Bolt11 invoices encode
    // their own amount so BigInt.one is an acceptable non-zero placeholder.
    final resolvedSats = _resolvedSats(ref);
    if (_isLnAddress(input) && resolvedSats == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Waiting for trade amount — please try again shortly.')),
      );
      return;
    }
    final sats = resolvedSats ?? BigInt.one;
    setState(() => _submitting = true);

    try {
      await orders_api.sendInvoice(
        orderId: widget.orderId,
        invoiceOrAddress: _invoiceController.text.trim(),
        amountSats: sats,
      );

      if (!mounted) return;
      context.go(AppRoute.tradeDetailPath(widget.orderId));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>();
    final green = colors?.mostroGreen ?? const Color(0xFF8CC63F);
    final cardBg = colors?.backgroundCard ?? const Color(0xFF1E2230);
    final inputBg = colors?.backgroundInput ?? const Color(0xFF252A3A);

    final isWalletConnected = ref.watch(isWalletConnectedProvider);

    // Resolve sats: provider first (live polling), fall back to constructor param.
    final sats = _resolvedSats(ref);

    // When NWC is connected, we need the sats amount to auto-generate an invoice.
    // Show a loading indicator only in that case. Manual entry is always available.
    if (isWalletConnected && sats == null && !_manualMode) {
      return Scaffold(
        appBar: AppBar(title: const Text('Add Invoice')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Fetching trade amount…',
                style: TextStyle(color: Theme.of(context).extension<AppColors>()?.textSecondary),
              ),
              const SizedBox(height: AppSpacing.md),
              TextButton(
                onPressed: () => setState(() => _manualMode = true),
                child: const Text('Enter invoice manually'),
              ),
            ],
          ),
        ),
      );
    }

    // If NWC wallet is connected, amount is known, and we haven't fallen back
    // to manual, show the auto-invoice widget instead of the manual form.
    if (isWalletConnected && !_manualMode && sats != null && sats > BigInt.zero) {
      return Scaffold(
        appBar: AppBar(title: const Text('Add Invoice')),
        body: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Center(
            child: NwcInvoiceWidget(
              amountSats: sats.toInt(),
              onInvoiceConfirmed: (invoice) {
                _invoiceController.text = invoice;
                _submit(ref);
              },
              onFallbackToManual: () => setState(() => _manualMode = true),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Add Invoice')),
      body: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          children: [
            // Info card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(AppRadius.card),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.bolt, color: green, size: 24),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          'Enter a Lightning Invoice to receive your sats',
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),

                  // Invoice text input
                  TextField(
                    controller: _invoiceController,
                    maxLines: 4,
                    autocorrect: false,
                    enableSuggestions: false,
                    enableIMEPersonalizedLearning: false,
                    decoration: InputDecoration(
                      hintText: 'lnbc...',
                      floatingLabelBehavior: FloatingLabelBehavior.auto,
                      labelText: 'Lightning Invoice',
                      filled: true,
                      fillColor: inputBg,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.input),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    style: (theme.textTheme.bodySmall ?? const TextStyle()).copyWith(
                      fontFamily: 'monospace',
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ],
              ),
            ),
            const Spacer(),

            // Buttons
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => context.pop(),
                    child: Text(
                      'Cancel',
                      style: TextStyle(color: colors?.textSecondary),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: FilledButton(
                    onPressed: _isValid(ref) ? () => _submit(ref) : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: green,
                      foregroundColor: Colors.black,
                      disabledBackgroundColor: green.withValues(alpha: 0.3),
                      minimumSize: const Size(0, 48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.button),
                      ),
                    ),
                    child: _submitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Submit'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

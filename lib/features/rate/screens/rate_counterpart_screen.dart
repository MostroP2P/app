import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/rate/widgets/star_rating.dart';

/// Rate counterpart screen — Route `/rate_user/:orderId`.
///
/// Prompted after trade completion:
///   - Seller: prompted at `SettledHoldInvoice` (after releasing funds)
///   - Buyer:  prompted at `Success` (after payment confirmed)
///
/// Layout:
///   - "RATE" header label (uppercase, gray)
///   - Green double-lightning-bolt success indicator + "Successful order" text
///   - [StarRating] widget (5 tappable stars)
///   - "X / 5" score display
///   - SUBMIT button (green filled, disabled until rating > 0)
///   - CLOSE button (green outline, skips rating)
class RateCounterpartScreen extends ConsumerStatefulWidget {
  const RateCounterpartScreen({super.key, required this.orderId});

  final String orderId;

  @override
  ConsumerState<RateCounterpartScreen> createState() =>
      _RateCounterpartScreenState();
}

class _RateCounterpartScreenState
    extends ConsumerState<RateCounterpartScreen> {
  int _rating = 0;
  bool _isSubmitting = false;

  Future<void> _submit() async {
    if (_rating == 0) return;
    setState(() => _isSubmitting = true);
    try {
      // TODO(bridge): Call reputation.submit_rating(widget.orderId, _rating)
      // via Rust bridge once FFI bindings are generated.
      await Future.delayed(const Duration(milliseconds: 300));
      if (mounted) context.pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Rating failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>();
    assert(colors != null, 'AppColors theme extension must be registered');
    if (colors == null) return const SizedBox.shrink();

    final textTheme = Theme.of(context).textTheme;
    final green = colors.mostroGreen;

    return Scaffold(
      backgroundColor: colors.backgroundDark,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: Column(
            children: [
              const SizedBox(height: AppSpacing.xl),

              // ── "RATE" header ─────────────────────────────────────────
              Text(
                'RATE',
                style: textTheme.labelMedium?.copyWith(
                  color: colors.textSubtle,
                  letterSpacing: 2,
                  fontWeight: FontWeight.w600,
                ),
              ),

              const SizedBox(height: AppSpacing.xl),

              // ── Success indicator ─────────────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.bolt, color: green, size: 32),
                  Icon(Icons.bolt, color: green, size: 32),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Successful order',
                style: textTheme.titleMedium?.copyWith(
                  color: green,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: AppSpacing.xl),

              // ── Star rating ───────────────────────────────────────────
              StarRating(
                rating: _rating,
                onChanged: (value) => setState(() => _rating = value),
              ),

              const SizedBox(height: AppSpacing.md),

              // ── "X / 5" display ───────────────────────────────────────
              Text(
                '$_rating / 5',
                style: textTheme.headlineSmall?.copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const Spacer(),

              // ── SUBMIT button ─────────────────────────────────────────
              FilledButton(
                onPressed: (_rating > 0 && !_isSubmitting) ? _submit : null,
                style: FilledButton.styleFrom(
                  backgroundColor: green,
                  foregroundColor: Colors.black,
                  disabledBackgroundColor: green.withValues(alpha: 0.35),
                  disabledForegroundColor: Colors.black54,
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.button),
                  ),
                ),
                child: _isSubmitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.black54,
                        ),
                      )
                    : const Text(
                        'SUBMIT',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
              ),

              const SizedBox(height: AppSpacing.sm),

              // ── CLOSE button (skip rating) ────────────────────────────
              OutlinedButton(
                onPressed: () => context.pop(),
                style: OutlinedButton.styleFrom(
                  foregroundColor: green,
                  side: BorderSide(color: green),
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.button),
                  ),
                ),
                child: const Text(
                  'CLOSE',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),

              const SizedBox(height: AppSpacing.lg),
            ],
          ),
        ),
      ),
    );
  }
}

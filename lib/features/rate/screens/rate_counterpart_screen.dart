import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/core/automation/automation_id.dart';
import 'package:mostro/core/automation/automation_ids.dart';
import 'package:mostro/core/daemon_errors.dart';
import 'package:mostro/features/account/providers/privacy_mode_provider.dart';
import 'package:mostro/features/rate/providers/rating_providers.dart';
import 'package:mostro/features/order/providers/trade_state_provider.dart';
import 'package:mostro/features/trades/screens/trade_detail_screen.dart';
import 'package:mostro/features/rate/widgets/star_rating.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/src/rust/api/types.dart' show OrderStatus;
import 'package:mostro/src/rust/api/reputation.dart' as reputation_api;

/// Rate counterpart screen — Route `/rate_user/:orderId`.
///
/// The buyer may rate once the payout completes; the seller as soon as they
/// have released (#586) — the daemon accepts the seller's rating at
/// `settled-hold-invoice`. An early notification or direct route shows the
/// live trade screen until the user's rating step.
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

class _RateCounterpartScreenState extends ConsumerState<RateCounterpartScreen> {
  int _rating = 0;
  bool _isSubmitting = false;

  bool get _canRate =>
      _atRatingStep(
        ref.read(tradeStatusProvider(widget.orderId)).valueOrNull,
        _isBuyer(read: true),
      ) &&
      !ref.read(ratedByMeProvider(widget.orderId)) &&
      !ref.read(privacyModeProvider);

  /// The user's role, `null` until known. Unknown counts as the buyer: then
  /// only `success` opens the rating, which the daemon accepts from either
  /// side — never offer a rating it would refuse.
  bool? _isBuyer({bool read = false}) {
    final roles =
        read ? ref.read(tradeRoleProvider) : ref.watch(tradeRoleProvider);
    if (roles.containsKey(widget.orderId)) return roles[widget.orderId];
    final db = tradeRoleFromDbProvider(widget.orderId);
    return (read ? ref.read(db) : ref.watch(db)).valueOrNull;
  }

  static bool _atRatingStep(OrderStatus? status, bool? isBuyer) =>
      status != null &&
      tradeStatusFor(status, isBuyer: isBuyer ?? true) ==
          TradeStatus.pendingRating;

  Future<void> _submit() async {
    if (_rating == 0 || !_canRate) return;
    setState(() => _isSubmitting = true);
    try {
      await reputation_api.submitRating(
        tradeId: widget.orderId,
        score: _rating,
      );
      // submitRating awaits a real relay publish, so the screen may have
      // been disposed by now — and ref, like context, must not be touched
      // after that.
      if (!mounted) return;
      // The screen underneath buckets a successful trade as "rate me" until a
      // local rating exists, so refresh it before popping back (#327).
      ref.invalidate(tradeRatingProvider(widget.orderId));
      context.pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            localizedDaemonError(
              AppLocalizations.of(context),
              e,
              fallback: AppLocalizations.of(context).ratingFailed,
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(tradeStatusProvider(widget.orderId)).valueOrNull;
    // A rating already sent sends the user to the trade screen, which shows
    // it: the seller's rating step can last as long as a retrying payout
    // (#586), and a second submit would only meet `AlreadyRated`. Until the
    // local rating has been read, that screen's own `loading` stands in —
    // no flash of a form that is about to go away. Privacy mode sends no
    // rating at all (Rust refuses it), so it gets the trade screen too, which
    // withholds the rating the same way.
    final rating = ref.watch(tradeRatingProvider(widget.orderId));
    if (!_atRatingStep(status, _isBuyer()) ||
        (rating.isLoading && !rating.hasValue) ||
        ref.watch(ratedByMeProvider(widget.orderId)) ||
        ref.watch(privacyModeProvider)) {
      return TradeDetailScreen(orderId: widget.orderId);
    }
    final colors = Theme.of(context).extension<AppColors>();
    if (colors == null) {
      throw StateError('AppColors theme extension must be registered');
    }

    final textTheme = Theme.of(context).textTheme;
    final green = colors.mostroGreen;
    final l10n = AppLocalizations.of(context);

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
                l10n.rateScreenHeader,
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
                l10n.successfulOrder,
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
                child:
                    _isSubmitting
                        ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.black54,
                          ),
                        )
                        : Text(
                          l10n.submitUppercaseButton,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
              ).withAutomationId(AutomationIds.tradeRateSubmit),

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
                child: Text(
                  l10n.closeRatingButton,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ).withAutomationId(AutomationIds.tradeRateClose),

              const SizedBox(height: AppSpacing.lg),
            ],
          ),
        ),
      ),
    );
  }
}

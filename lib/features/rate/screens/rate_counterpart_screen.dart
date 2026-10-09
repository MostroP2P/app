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
import 'package:mostro/features/order/widgets/invoice_widgets.dart';
import 'package:mostro/features/trades/screens/trade_detail_screen.dart';
import 'package:mostro/features/rate/widgets/star_rating.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/mascot/mascot_cues.dart';
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
///   - Lime double-lightning-bolt success indicator + "Successful order" text
///   - [StarRating] widget (5 tappable stars)
///   - "X / 5" score display
///   - SUBMIT button (the lime call to action, disabled until rating > 0)
///   - CLOSE link (neutral, skips rating)
/// Screen content inset from the side edges (DS-SPC-1).
const double _sideInset = 18;

/// An in-page call to action and its outlined sibling (DS-CMP-3, DS-CMP-4).
const double _ctaRadius = 16;

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
      ref.read(mascotCueProvider.notifier).rated(_rating);
      // The screen underneath buckets a successful trade as "rate me" until a
      // local rating exists, so refresh it before popping back (#327).
      ref.invalidate(tradeRatingProvider(widget.orderId));
      context.pop();
    } catch (e) {
      if (!mounted) return;
      ref.read(mascotCueProvider.notifier).daemonRefused(e);
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
    final book = OrderBookPalette.of(context);
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: book.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: _sideInset),
          child: Column(
            children: [
              const SizedBox(height: AppSpacing.xl),

              // ── "RATE" header ─────────────────────────────────────────
              Text(
                l10n.rateScreenHeader,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.6,
                  color: book.textTertiary,
                ),
              ),

              const SizedBox(height: AppSpacing.xl),

              // ── Success indicator ─────────────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.bolt, color: book.limeIcon, size: 32),
                  Icon(Icons.bolt, color: book.limeIcon, size: 32),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                l10n.successfulOrder,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: book.limeText,
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
                style: TextStyle(
                  fontFamily: AppFonts.figures,
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: book.textPrimary,
                ),
              ),

              const Spacer(),

              // ── SUBMIT button ─────────────────────────────────────────
              FilledButton(
                onPressed: (_rating > 0 && !_isSubmitting) ? _submit : null,
                style: FilledButton.styleFrom(
                  backgroundColor: book.lime,
                  foregroundColor: book.onLime,
                  disabledBackgroundColor: book.border,
                  disabledForegroundColor: book.textFaint,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(_ctaRadius),
                  ),
                  textStyle: const TextStyle(
                    fontFamily: AppFonts.ui,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                child:
                    _isSubmitting
                        ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: book.onLime,
                          ),
                        )
                        : Text(l10n.submitUppercaseButton),
              ).withAutomationId(AutomationIds.tradeRateSubmit),

              const SizedBox(height: AppSpacing.sm),

              // ── CLOSE link (skip rating) ────────────────────────────
              // Skipping the rating undoes nothing: a neutral link
              // (DS-CMP-20).
              InvoiceCancelLink(
                label: l10n.closeRatingButton,
                danger: false,
                onPressed: () => context.pop(),
              ).withAutomationId(AutomationIds.tradeRateClose),

              const SizedBox(height: AppSpacing.lg),
            ],
          ),
        ),
      ),
    );
  }
}

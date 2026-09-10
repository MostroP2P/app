import 'package:flutter/material.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/l10n/app_localizations.dart';

/// A single reputation metric (value + label), optionally with a leading icon.
///
/// Shared between the creator-reputation card on the take-order screen and the
/// counterpart-reputation card ([PeerReputationCard]) so both sides of a trade
/// render identically.
class ReputationStat extends StatelessWidget {
  const ReputationStat({
    super.key,
    required this.value,
    required this.label,
    this.icon,
    this.iconColor,
  });

  final String value;
  final String label;
  final IconData? icon;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>();
    final textSec = colors?.textSecondary ?? const Color(0xFFB0B3C6);
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: iconColor),
              const SizedBox(width: AppSpacing.xs),
            ],
            Text(
              value,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(color: textSec, fontSize: 11)),
      ],
    );
  }
}

/// Counterpart (taker) reputation snapshot, shown where the maker decides
/// whether to continue: the pay/add-invoice screens and the trade detail
/// (issue #305). The daemon sends this as a follow-up Peer DM once its order
/// is taken; the Rust side persists it onto the trade.
///
/// The counterpart's role is derived from the user's own — paying the hold
/// invoice means the taker is the buyer; adding an invoice means the taker is
/// the seller — and passed in as [counterpartIsBuyer] so the title reads
/// "Buyer reputation" / "Seller reputation".
///
/// All-zeros is ambiguous on the wire — a brand-new user and a full-privacy
/// taker are indistinguishable — so the raw numbers are shown as-is.
class PeerReputationCard extends StatelessWidget {
  const PeerReputationCard({
    super.key,
    required this.rating,
    required this.reviews,
    required this.days,
    required this.counterpartIsBuyer,
  });

  final double rating;
  final int reviews;
  final int days;
  final bool counterpartIsBuyer;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>();
    final cardBg = colors?.backgroundCard ?? const Color(0xFF1E2230);
    final textSec = colors?.textSecondary ?? const Color(0xFFB0B3C6);
    final l10n = AppLocalizations.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            counterpartIsBuyer
                ? l10n.buyerReputation
                : l10n.sellerReputation,
            style: TextStyle(color: textSec, fontSize: 12),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: ReputationStat(
                  value: rating.toStringAsFixed(1),
                  label: l10n.ratingStatLabel,
                  icon: Icons.star,
                  iconColor: Colors.amber,
                ),
              ),
              Expanded(
                child: ReputationStat(
                  value: '$reviews',
                  label: l10n.tradesStatLabel,
                ),
              ),
              Expanded(
                child: ReputationStat(
                  value: '$days',
                  label: l10n.daysActiveStatLabel,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

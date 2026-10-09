import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/account/providers/my_reputation_provider.dart';
import 'package:mostro/features/account/widgets/account_card.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/utils/reputation_age.dart';
import 'package:mostro/shared/widgets/counterpart_reputation_row.dart'
    show highlightFigures;
import 'package:mostro/src/rust/api/my_reputation.dart';

/// The user's own reputation on the active node (issue #755), as the node
/// answered `user-info`: `★ 4.8 · 23 ratings · since Nov 2023`.
///
/// Zero ratings is "no reputation yet", never a `0.0` grade. Full privacy
/// mode keeps no reputation, so the card says so instead of showing one.
class MyReputationCard extends StatelessWidget {
  const MyReputationCard({
    super.key,
    required this.privacyMode,
    required this.state,
    this.nodeName,
  });

  final bool privacyMode;
  final MyReputationState state;

  /// The active node's display name, when it has one.
  final String? nodeName;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final reputation = state.reputation;

    final Widget body;
    if (privacyMode) {
      body = _Note(l10n.myReputationPrivacyMode);
    } else if (reputation == null) {
      body = _Note(
        state.loading ? l10n.myReputationLoading : l10n.myReputationUnavailable,
      );
    } else if (reputation.reviews == 0) {
      body = _Note(l10n.myReputationNoReviews);
    } else {
      body = _Figures(reputation: reputation);
    }

    final node = nodeName;
    return AccountCard(
      padding: const EdgeInsets.all(14),
      gap: 12,
      children: [
        AccountCardHeader(
          icon: Icons.star_outline_rounded,
          title: l10n.myReputationTitle,
        ),
        body,
        if (!privacyMode && node != null) _Note(l10n.myReputationOnNode(node)),
      ],
    );
  }
}

class _Figures extends StatelessWidget {
  const _Figures({required this.reputation});

  final MyReputation reputation;

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final since = reputationSince(reputation.since);

    final summary = TextStyle(fontSize: 12, color: book.textSecondary);
    final figure = summary.copyWith(
      color: book.textBody,
      fontWeight: FontWeight.w500,
    );
    final age =
        since == null
            ? l10n.reputationDaysOnMostro(reputation.operatingDays)
            : l10n.myReputationSince(DateFormat.yMMM(locale).format(since));

    return Row(
      children: [
        Icon(Icons.star_rounded, size: 20, color: book.yellow),
        const SizedBox(width: 6),
        Text(
          NumberFormat.decimalPatternDigits(
            locale: locale,
            decimalDigits: 1,
          ).format(reputation.rating),
          style: TextStyle(
            fontFamily: AppFonts.figures,
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: book.textStrong,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                ...highlightFigures(
                  l10n.myReputationReviews(reputation.reviews),
                  figure,
                ),
                const TextSpan(text: ' · '),
                ...highlightFigures(age, figure),
              ],
            ),
            style: summary,
          ),
        ),
      ],
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 12,
        color: OrderBookPalette.of(context).textSecondary,
      ),
    );
  }
}

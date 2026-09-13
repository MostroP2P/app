import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:mostro/core/activity_palette.dart';
import 'package:mostro/core/app_routes.dart';
import 'package:mostro/core/automation/automation_id.dart';
import 'package:mostro/core/automation/automation_ids.dart';
import 'package:mostro/core/order_book_palette.dart';
import 'package:mostro/features/order/models/bond_rules.dart';
import 'package:mostro/features/order/models/invoice_rules.dart';
import 'package:mostro/features/order/providers/bond_providers.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/utils/platform_int64.dart';
import 'package:mostro/src/rust/api/types.dart' show BondClaimPhase;

/// The payout banner on the trade detail (docs/ANTI_ABUSE_BOND.md §8.3):
/// the counterparty's slashed bond has a share for this user. Nothing when
/// the order has no claim; a muted line once the window closed.
class BondClaimBanner extends ConsumerWidget {
  const BondClaimBanner({super.key, required this.orderId});

  final String orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final claim = ref.watch(bondClaimProvider(orderId)).valueOrNull;
    if (claim == null) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final book = OrderBookPalette.of(context);
    final pal = ActivityPalette.of(context);
    final now = clock.now().millisecondsSinceEpoch ~/ 1000;
    final phase = bondClaimEffectivePhase(
      phase: claim.phase,
      deadlineAt: platformInt64ToInt(claim.deadlineAt),
      now: now,
    );
    final sats = formatInvoiceSats(claim.amountSats.toInt());
    final locale = Localizations.localeOf(context).toString();
    String date(int secs) => DateFormat.yMMMd(
      locale,
    ).format(DateTime.fromMillisecondsSinceEpoch(secs * 1000));

    if (phase == BondClaimPhase.expired) {
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Text(
          l10n.bondBannerExpired(date(platformInt64ToInt(claim.deadlineAt))),
          style: TextStyle(fontSize: 12, color: book.textTertiary),
        ),
      ).withAutomationId(AutomationIds.tradeBondClaim, label: phase.name);
    }
    final (title, body) = switch (phase) {
      BondClaimPhase.pending => (
        l10n.bondBannerPendingTitle(sats),
        l10n.bondBannerPendingBody(sats),
      ),
      BondClaimPhase.submitted || BondClaimPhase.acknowledged => (
        l10n.bondBannerInProgressTitle,
        l10n.bondBannerInProgressBody(sats),
      ),
      BondClaimPhase.completed => (
        l10n.bondBannerPaidTitle,
        l10n.bondBannerPaidBody(
          sats,
          date(platformInt64ToInt(claim.updatedAt)),
        ),
      ),
      BondClaimPhase.expired => ('', ''),
    };
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: book.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color:
                phase == BondClaimPhase.pending
                    ? pal.chipDisputeBorder
                    : book.border,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  phase == BondClaimPhase.completed
                      ? Icons.check_circle_outline
                      : Icons.savings_outlined,
                  size: 18,
                  color:
                      phase == BondClaimPhase.pending
                          ? pal.chipDisputeInk
                          : book.lime,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: book.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              body,
              style: TextStyle(
                fontSize: 12,
                height: 1.5,
                color: book.textSecondary,
              ),
            ),
            if (phase != BondClaimPhase.completed) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed:
                      () => context.push(AppRoute.bondPayoutPath(orderId)),
                  child: Text(
                    phase == BondClaimPhase.pending
                        ? l10n.bondBannerAddInvoice
                        : l10n.bondBannerView,
                  ),
                ).withAutomationId(AutomationIds.tradeBondClaimOpen),
              ),
            ],
          ],
        ),
      ),
    ).withAutomationId(AutomationIds.tradeBondClaim, label: phase.name);
  }
}

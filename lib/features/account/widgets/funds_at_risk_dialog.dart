import 'package:flutter/material.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/core/automation/automation_ids.dart';
import 'package:mostro/features/order/models/order_detail_rules.dart';
import 'package:mostro/features/trades/models/trades_list_rules.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/widgets/mostro_modal.dart';
import 'package:mostro/src/rust/api/types.dart';

/// Warns that the current identity still has something in flight, before it
/// is replaced by a generated user or an imported seed (issue #533).
///
/// Resolves to `true` only when the user chose to go on anyway. It warns and
/// does not block: the user may be rotating because the device is
/// compromised. The safe choice is the primary action, and a dismissal —
/// barrier tap or back — counts as it.
Future<bool> confirmIdentitySwapDespiteRisk(
  BuildContext context,
  List<FundsAtRisk> risks,
) async {
  final goOn = await showMostroDialog<bool>(
    context: context,
    builder: (dialogContext) => FundsAtRiskDialog(risks: risks),
  );
  return goOn ?? false;
}

/// What each reason reads as. Rust sends the marker; the words live here.
String fundsAtRiskLabel(
  AppLocalizations l10n,
  FundsAtRiskReason reason,
) => switch (reason) {
  FundsAtRiskReason.sellerEscrowLocked => l10n.fundsAtRiskSellerEscrow,
  FundsAtRiskReason.bondLocked => l10n.fundsAtRiskBondLocked,
  FundsAtRiskReason.payoutClaimOpen => l10n.fundsAtRiskPayoutClaim,
  FundsAtRiskReason.tradeInProgress => l10n.fundsAtRiskTradeInProgress,
  FundsAtRiskReason.bondInvoicePending => l10n.fundsAtRiskBondInvoicePending,
};

class FundsAtRiskDialog extends StatelessWidget {
  const FundsAtRiskDialog({super.key, required this.risks});

  /// Most serious first, as `funds_at_risk()` returns them.
  final List<FundsAtRisk> risks;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final book = OrderBookPalette.of(context);

    return MostroDialog(
      icon: Icons.warning_amber_rounded,
      iconTone: ModalTone.destructive,
      title: l10n.fundsAtRiskTitle,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.fundsAtRiskBody,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13.5, height: 1.5, color: book.textBody),
          ),
          const SizedBox(height: 14),
          for (final risk in risks) _RiskRow(risk: risk),
        ],
      ),
      primary: ModalAction(
        label: l10n.fundsAtRiskKeep,
        automationId: AutomationIds.keysFundsAtRiskKeep,
        onPressed: () => Navigator.pop(context, false),
      ),
      secondary: ModalAction(
        label: l10n.fundsAtRiskContinue,
        tone: ModalTone.destructive,
        automationId: AutomationIds.keysFundsAtRiskContinue,
        onPressed: () => Navigator.pop(context, true),
      ),
    );
  }
}

/// One thing in flight: what it is, on which order, and how many sats.
class _RiskRow extends StatelessWidget {
  const _RiskRow({required this.risk});

  final FundsAtRisk risk;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final book = OrderBookPalette.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final sats = risk.amountSats;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: book.inset,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: book.border),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    fundsAtRiskLabel(l10n, risk.reason),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: book.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    l10n.orderLabel(shortOrderId(risk.orderId)),
                    style: TextStyle(fontSize: 11.5, color: book.textSecondary),
                  ),
                ],
              ),
            ),
            if (sats != null) ...[
              const SizedBox(width: 10),
              Text(
                l10n.satsAmount(formatSatsCount(sats.toInt(), locale)),
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: book.textStrong,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

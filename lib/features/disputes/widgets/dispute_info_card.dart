import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mostro/core/order_book_palette.dart';
import 'package:mostro/features/disputes/models/dispute_info_rules.dart';
import 'package:mostro/features/disputes/providers/disputes_providers.dart';
import 'package:mostro/features/disputes/widgets/dispute_title_row.dart';
import 'package:mostro/features/order/widgets/order_detail_cards.dart';
import 'package:mostro/features/trades/widgets/trade_list_chip.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/widgets/redesign_app_bar.dart';

/// Gap between the card's sections.
const double _sectionGap = 14;

/// The card that opens the dispute chat (MostroP2P/app#680), as v1's
/// `DisputeInfoCard` and in v1's words: who the dispute is with and its
/// status chip, the full order and dispute ids, then the status sentence
/// and what to do.
///
/// It is the first item of the chat's scroll view, so it scrolls away with
/// the messages, as in v1, and never pushes the input bar off screen.
///
/// v1's fourth instruction (give the solver the chat's shared key) is left
/// out: v2 no longer shows that key, and #415 replaces the flow.
class DisputeInfoCard extends ConsumerWidget {
  const DisputeInfoCard({super.key, required this.dispute});

  final DisputeItem dispute;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final book = OrderBookPalette.of(context);
    final counterpart = ref.watch(disputeCounterpartProvider(dispute.tradeId));
    final isSelling = counterpart.isSelling ?? dispute.isSelling;
    final handle =
        counterpart.handle ?? dispute.peerHandle ?? l10n.unknownPeerHandle;
    final chip = disputeChipLabel(dispute);
    final sentence = disputeStatusSentence(dispute);
    final reason = dispute.reason;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        redesignSidePadding,
        12,
        redesignSidePadding,
        12,
      ),
      child: OrderDetailCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Side by side when the title's words fit beside the chip;
            // otherwise the chip goes under the title (no word is broken).
            DisputeTitleRow(
              title: Text(
                l10n.disputeWith(isSelling ? l10n.buyer : l10n.seller, handle),
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  height: 1.4,
                  color: book.textPrimary,
                ),
              ),
              // One line like every chip; one wider than the card at large
              // text shrinks instead of overflowing.
              chip: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.topStart,
                child: TradeListChip.status(
                  kind: disputeChipKind(chip),
                  caption: chip.localized(l10n),
                ),
              ),
            ),
            const SizedBox(height: _sectionGap),
            _IdRow(
              label: l10n.orderIdLabel,
              value: dispute.tradeId,
              copiedMessage: l10n.orderIdCopied,
            ),
            const SizedBox(height: 8),
            _IdRow(
              label: l10n.disputeIdLabel,
              value: dispute.id,
              copiedMessage: l10n.aboutCopiedToClipboard,
            ),
            if (reason != null) ...[
              const SizedBox(height: 8),
              Text(
                l10n.disputeReasonLabel(reason),
                style: TextStyle(fontSize: 12, color: book.textSecondary),
              ),
            ],
            if (sentence != null) ...[
              const SizedBox(height: _sectionGap),
              Text(
                _sentenceText(sentence, l10n, isSelling, handle),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  height: 1.45,
                  color: book.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              _Bullet(l10n.disputeInstruction1),
              _Bullet(l10n.disputeInstruction2),
              _Bullet(l10n.disputeInstruction3, isLast: true),
            ],
          ],
        ),
      ),
    );
  }

  static String _sentenceText(
    DisputeStatusSentence sentence,
    AppLocalizations l10n,
    bool isSelling,
    String handle,
  ) => switch (sentence) {
    DisputeStatusSentence.inProgress => l10n.disputeInProgress,
    DisputeStatusSentence.waitingForSolver => l10n.disputeWaitingForAdmin,
    // The seller's dispute is against the buyer, and the other way round.
    DisputeStatusSentence.openedByYou =>
      isSelling
          ? l10n.disputeOpenedByYouAgainstBuyer(handle)
          : l10n.disputeOpenedByYouAgainstSeller(handle),
  };
}

/// A labelled id: the label above, the whole id below in monospace, wrapped
/// rather than shortened. The row copies the id, like the order screens' id
/// row does.
class _IdRow extends StatelessWidget {
  const _IdRow({
    required this.label,
    required this.value,
    required this.copiedMessage,
  });

  final String label;
  final String value;
  final String copiedMessage;

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    final copy = AppLocalizations.of(context).copyButtonLabel;
    return Semantics(
      button: true,
      label: '$copy $label',
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: () => _copy(context),
          borderRadius: BorderRadius.circular(12),
          child: ConstrainedBox(
            // DS-CMP-6: the row is the tap target.
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: TextStyle(fontSize: 12, color: book.textSecondary),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          value,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            height: 1.4,
                            color: book.textStrong,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ExcludeSemantics(
                        child: Icon(
                          Icons.copy_rounded,
                          size: 16,
                          color: book.limeIcon,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _copy(BuildContext context) {
    Clipboard.setData(ClipboardData(text: value));
    HapticFeedback.selectionClick();
    showOrderDetailSnackBar(context, copiedMessage);
  }
}

/// One instruction: a small dot and the text beside it.
class _Bullet extends StatelessWidget {
  const _Bullet(this.text, {this.isLast = false});

  final String text;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(
            child: Container(
              margin: const EdgeInsets.only(top: 8),
              width: 4,
              height: 4,
              decoration: BoxDecoration(
                color: book.textSecondary,
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13,
                height: 1.45,
                color: book.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

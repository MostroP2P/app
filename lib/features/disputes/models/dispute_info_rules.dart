import 'package:mostro/features/disputes/providers/disputes_providers.dart';
import 'package:mostro/features/trades/models/trades_list_rules.dart'
    show TradeChipKind;
import 'package:mostro/l10n/app_localizations.dart';

/// What the dispute info card says about a dispute: its chip and the
/// sentence above the instructions, ported from v1's `DisputeStatusBadge`
/// and `DisputeStatusContent` (MostroP2P/app#680).

/// The chip's word. v1 shows `Initiated`, `In progress`, `Resolved` (a
/// solver's verdict) and `Closed` (the parties ended it themselves).
enum DisputeChipLabel { initiated, inProgress, resolved, closed }

/// The chip follows the dispute's status alone, as in v1.
DisputeChipLabel disputeChipLabel(DisputeItem dispute) => switch (dispute
    .status) {
  DisputeStatus.open => DisputeChipLabel.initiated,
  DisputeStatus.inReview => DisputeChipLabel.inProgress,
  DisputeStatus.resolved => switch (dispute.resolution) {
    DisputeResolution.fundsToBuyer ||
    DisputeResolution.fundsToSeller => DisputeChipLabel.resolved,
    DisputeResolution.cooperativeCancel || null => DisputeChipLabel.closed,
  },
};

/// The chip's colours, by what each status means (DS-COL-9): waiting for a
/// solver is amber, a live dispute coral, an ended one neutral.
TradeChipKind disputeChipKind(DisputeChipLabel label) => switch (label) {
  DisputeChipLabel.initiated => TradeChipKind.waiting,
  DisputeChipLabel.inProgress => TradeChipKind.dispute,
  DisputeChipLabel.resolved || DisputeChipLabel.closed => TradeChipKind.done,
};

extension DisputeChipLabelL10n on DisputeChipLabel {
  String localized(AppLocalizations l10n) => switch (this) {
    DisputeChipLabel.initiated => l10n.disputeStatusInitiated,
    DisputeChipLabel.inProgress => l10n.disputeStatusInProgress,
    DisputeChipLabel.resolved => l10n.disputeStatusResolved,
    DisputeChipLabel.closed => l10n.disputeStatusClosed,
  };
}

/// The status sentence over the instructions.
enum DisputeStatusSentence {
  /// The user opened it and no solver has taken it yet.
  openedByYou,

  /// The peer opened it and no solver has taken it yet.
  waitingForSolver,

  /// A solver has the dispute.
  inProgress,
}

/// v1's description key for an open dispute: a solver who took it makes it
/// "in progress" whatever the status says; until then the sentence depends
/// on who opened it. A resolved dispute has none: its outcome is the
/// resolved banner's, and the card asks the user for nothing more.
DisputeStatusSentence? disputeStatusSentence(DisputeItem dispute) =>
    switch (dispute.status) {
      DisputeStatus.resolved => null,
      DisputeStatus.inReview => DisputeStatusSentence.inProgress,
      DisputeStatus.open when dispute.adminPubkey != null =>
        DisputeStatusSentence.inProgress,
      DisputeStatus.open when dispute.initiatedByMe =>
        DisputeStatusSentence.openedByYou,
      DisputeStatus.open => DisputeStatusSentence.waitingForSolver,
    };

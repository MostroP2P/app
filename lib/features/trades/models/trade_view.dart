import 'package:mostro/features/trades/models/trade_status.dart';

/// Status chip on the step block: what the user needs to know at a glance —
/// whether they wait or act.
enum TradeChip { none, waiting, active, yourTurn, dispute }

/// The one lime button of the action bar, when the user has something to do.
enum TradePrimaryAction {
  none,
  addInvoice,

  /// The anti-abuse deposit the node asks for before the trade starts.
  payBond,
  payHoldInvoice,
  fiatSent,
  release,
  viewDispute,
  sendRating,
  close,
}

/// Lower-hierarchy actions of the action bar.
enum TradeSecondaryAction { cancel, dispute, release }

/// Whose clock the countdown is: sets the `You have` / `They have` label.
enum TradeTimerOwner { none, user, counterpart, order }

/// The note under the countdown bar.
enum TradeTimerNote { none, expiresCancels, coordinateInChat, leavesBook }

/// Number of steps on the timeline.
const kTradeStepCount = 5;

/// What the trade screen shows for one (status, role) pair — handoff
/// `design_handoff_operacion/` maps its five mockups onto this: 8a waiting
/// for the counterpart's Lightning setup, 8b/8c active, 8d fiat sent, 8e
/// completed. Pure, so the mapping is unit-tested without widgets.
class TradeView {
  const TradeView({
    required this.step,
    required this.chip,
    required this.showsChat,
    required this.showsReputation,
    required this.primary,
    required this.secondary,
    required this.timer,
    required this.note,
    required this.isCompleted,
    this.showsReleaseWarning = false,
    this.showsCloseLink = false,
  });

  /// 0-based index of the current timeline step; [kTradeStepCount] once every
  /// step is done; -1 when the timeline is hidden (dispute, cancel, loading).
  final int step;
  final TradeChip chip;

  /// The chat card, only once both parties know who the other is. Before
  /// that the screen explains why there is no chat instead.
  final bool showsChat;

  /// The counterpart reputation row — while the user decides what to do with
  /// the fiat leg (8b, 8c).
  final bool showsReputation;
  final TradePrimaryAction primary;
  final List<TradeSecondaryAction> secondary;
  final TradeTimerOwner timer;
  final TradeTimerNote note;

  /// The completed card replaces the step block (8e).
  final bool isCompleted;

  /// `Releasing the sats cannot be undone.` inside the step block (8d).
  final bool showsReleaseWarning;

  /// `Close` as a text link under the primary action (8e, unrated).
  final bool showsCloseLink;

  /// The single `Cancel trade` at full width: no counterpart is known yet, so
  /// no dispute is possible (8a).
  bool get cancelIsFullWidth =>
      secondary.length == 1 && secondary.single == TradeSecondaryAction.cancel;

  bool get hasActions =>
      primary != TradePrimaryAction.none || secondary.isNotEmpty;

  bool get showsTimer => timer != TradeTimerOwner.none;

  /// [canRate] is false in privacy mode, where no rating can be sent: the
  /// completed screen then only offers `Close`.
  static TradeView of({
    required TradeStatus status,
    required bool isBuyer,
    bool canRate = true,
  }) {
    const cancelOnly = [TradeSecondaryAction.cancel];
    const cancelOrDispute = [
      TradeSecondaryAction.cancel,
      TradeSecondaryAction.dispute,
    ];

    switch (status) {
      case TradeStatus.loading:
        return const TradeView(
          step: -1,
          chip: TradeChip.none,
          showsChat: false,
          showsReputation: false,
          primary: TradePrimaryAction.none,
          secondary: [],
          timer: TradeTimerOwner.none,
          note: TradeTimerNote.none,
          isCompleted: false,
        );
      case TradeStatus.pending:
        return const TradeView(
          step: 0,
          chip: TradeChip.waiting,
          showsChat: false,
          showsReputation: false,
          primary: TradePrimaryAction.none,
          secondary: cancelOnly,
          timer: TradeTimerOwner.order,
          note: TradeTimerNote.leavesBook,
          isCompleted: false,
        );
      case TradeStatus.waitingInvoice:
        return TradeView(
          step: 1,
          chip: isBuyer ? TradeChip.yourTurn : TradeChip.waiting,
          showsChat: false,
          showsReputation: false,
          primary:
              isBuyer ? TradePrimaryAction.addInvoice : TradePrimaryAction.none,
          secondary: cancelOnly,
          timer: isBuyer ? TradeTimerOwner.user : TradeTimerOwner.counterpart,
          note: TradeTimerNote.expiresCancels,
          isCompleted: false,
        );
      case TradeStatus.waitingPayment:
        return TradeView(
          step: 1,
          chip: isBuyer ? TradeChip.waiting : TradeChip.yourTurn,
          showsChat: false,
          showsReputation: false,
          primary:
              isBuyer
                  ? TradePrimaryAction.none
                  : TradePrimaryAction.payHoldInvoice,
          secondary: cancelOnly,
          timer: isBuyer ? TradeTimerOwner.counterpart : TradeTimerOwner.user,
          note: TradeTimerNote.expiresCancels,
          isCompleted: false,
        );
      case TradeStatus.waitingBond:
        // The bond window precedes the trade flow: the user owes the deposit
        // (docs/ANTI_ABUSE_BOND.md §6.1). Phase 1 only ever parks a taker's
        // row here, and the daemon accepts a taker's cancel during the
        // window; the maker variant (no cancel, local abandon) is Phase 2.
        return const TradeView(
          step: 1,
          chip: TradeChip.yourTurn,
          showsChat: false,
          showsReputation: false,
          primary: TradePrimaryAction.payBond,
          secondary: cancelOnly,
          timer: TradeTimerOwner.none,
          note: TradeTimerNote.none,
          isCompleted: false,
        );
      case TradeStatus.inProgress:
        // The coarse public bucket: taken, escrow state unknown (#203). Only
        // cancel is safe to offer, and no clock is known.
        return const TradeView(
          step: 1,
          chip: TradeChip.waiting,
          showsChat: false,
          showsReputation: false,
          primary: TradePrimaryAction.none,
          secondary: cancelOnly,
          timer: TradeTimerOwner.none,
          note: TradeTimerNote.none,
          isCompleted: false,
        );
      case TradeStatus.active:
        return TradeView(
          step: 2,
          chip: isBuyer ? TradeChip.yourTurn : TradeChip.active,
          showsChat: true,
          showsReputation: true,
          primary:
              isBuyer ? TradePrimaryAction.fiatSent : TradePrimaryAction.none,
          secondary: cancelOrDispute,
          timer: isBuyer ? TradeTimerOwner.user : TradeTimerOwner.counterpart,
          note: TradeTimerNote.coordinateInChat,
          isCompleted: false,
        );
      case TradeStatus.fiatSent:
        return TradeView(
          step: 3,
          chip: isBuyer ? TradeChip.waiting : TradeChip.yourTurn,
          showsChat: true,
          showsReputation: false,
          primary:
              isBuyer ? TradePrimaryAction.none : TradePrimaryAction.release,
          secondary: cancelOrDispute,
          timer: isBuyer ? TradeTimerOwner.counterpart : TradeTimerOwner.user,
          note: TradeTimerNote.none,
          isCompleted: false,
          showsReleaseWarning: !isBuyer,
        );
      case TradeStatus.payoutPending:
        return const TradeView(
          step: 3,
          chip: TradeChip.waiting,
          showsChat: true,
          showsReputation: false,
          primary: TradePrimaryAction.none,
          secondary: [],
          timer: TradeTimerOwner.none,
          note: TradeTimerNote.none,
          isCompleted: false,
        );
      case TradeStatus.disputed:
        // Matches the daemon's own preconditions: only the seller can still
        // release or cancel once a dispute is open.
        return TradeView(
          step: -1,
          chip: TradeChip.dispute,
          showsChat: true,
          showsReputation: false,
          primary: TradePrimaryAction.viewDispute,
          secondary:
              isBuyer
                  ? const []
                  : const [
                    TradeSecondaryAction.release,
                    TradeSecondaryAction.cancel,
                  ],
          timer: TradeTimerOwner.none,
          note: TradeTimerNote.none,
          isCompleted: false,
        );
      case TradeStatus.pendingRating:
        return TradeView(
          step: kTradeStepCount - 1,
          chip: TradeChip.none,
          showsChat: false,
          showsReputation: false,
          primary:
              canRate
                  ? TradePrimaryAction.sendRating
                  : TradePrimaryAction.close,
          secondary: const [],
          timer: TradeTimerOwner.none,
          note: TradeTimerNote.none,
          isCompleted: true,
          showsCloseLink: canRate,
        );
      case TradeStatus.completed || TradeStatus.rated:
        return const TradeView(
          step: kTradeStepCount,
          chip: TradeChip.none,
          showsChat: false,
          showsReputation: false,
          primary: TradePrimaryAction.close,
          secondary: [],
          timer: TradeTimerOwner.none,
          note: TradeTimerNote.none,
          isCompleted: true,
        );
      case TradeStatus.cancelled:
        return const TradeView(
          step: -1,
          chip: TradeChip.none,
          showsChat: false,
          showsReputation: false,
          primary: TradePrimaryAction.close,
          secondary: [],
          timer: TradeTimerOwner.none,
          note: TradeTimerNote.none,
          isCompleted: false,
        );
    }
  }
}

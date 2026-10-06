import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/core/automation/automation_id.dart';
import 'package:mostro/core/automation/automation_ids.dart';
import 'package:mostro/features/chat/attachments/attachment_flow.dart';
import 'package:mostro/features/chat/attachments/upload_controller.dart';
import 'package:mostro/features/disputes/providers/dispute_chat_provider.dart';
import 'package:mostro/features/disputes/providers/disputes_providers.dart';
import 'package:mostro/features/disputes/widgets/dispute_message_input.dart';
import 'package:mostro/features/disputes/widgets/dispute_messages_list.dart';
import 'package:mostro/features/disputes/widgets/share_chat_key_action.dart';
import 'package:mostro/features/notifications/models/notification_model.dart';
import 'package:mostro/features/notifications/providers/notifications_provider.dart';
import 'package:mostro/shared/widgets/redesign_app_bar.dart';
import 'package:mostro/src/rust/api/types.dart' as rust_types;

/// Dispute chat screen — Route `/dispute_details/:disputeId`.
///
/// Layout:
///   - App bar: "Dispute Details", as in v1, and the [ShareChatKeyAction]
///     once a solver took the dispute (#415)
///   - Scrollable [DisputeMessagesList]: the info card ("Dispute with
///     [role]: [handle]", status chip, order and dispute ids, instructions
///     — #680), the resolved outcome, bubbles and banners
///   - [DisputeMessageInput] — only once a solver took the dispute
///
/// The conversation is with the solver (#143): history and live messages
/// from [disputeChatProvider], text through `submit_evidence`, images and
/// PDFs through `send_dispute_file` (#589 phase 3).
///
/// Terminal state — resolved (admin settled in buyer's favour):
///   Green checkmark + "Successfully completed" + lock icon + closed message.
///
/// Terminal state — seller-refunded (admin canceled):
///   "Resolved" badge (blue) + green resolution box + lock message.
///
/// Marks the dispute as read on [initState].
class DisputeChatScreen extends ConsumerStatefulWidget {
  const DisputeChatScreen({super.key, required this.disputeId});

  final String disputeId;

  @override
  ConsumerState<DisputeChatScreen> createState() => _DisputeChatScreenState();
}

class _DisputeChatScreenState extends ConsumerState<DisputeChatScreen> {
  bool _isSending = false;
  bool _isAttaching = false;

  /// The trade whose dispute was refreshed and whose solver notice was
  /// marked read: done once, as soon as the dispute is known.
  String? _openedTradeId;

  /// Live updates applied so far. A refresh that started before one of them
  /// answers with an older record, so it is dropped (PR #596 review).
  int _liveUpdates = 0;

  @override
  void initState() {
    super.initState();
    // Mark as read as soon as the screen opens.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(disputeNotifierProvider.notifier).markRead(widget.disputeId);
    });
  }

  /// Once per trade, whenever the dispute first shows up — on the first
  /// frame, or later if the list had not loaded it yet.
  void _onDisputeKnown(String tradeId) {
    if (_openedTradeId == tradeId) return;
    _openedTradeId = tradeId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(
        ref
            .read(notificationsProvider.notifier)
            .markAsRead(NotificationModel.chatCardId(tradeId, fromSolver: true)),
      );
      unawaited(_refreshDispute(tradeId));
    });
  }

  /// The list learns of a dispute's changes on resume only; a solver who took
  /// it since then must show here before the first live update does.
  Future<void> _refreshDispute(String tradeId) async {
    final liveUpdates = _liveUpdates;
    try {
      final dispute = await ref
          .read(disputeChatGatewayProvider)
          .getDispute(tradeId);
      if (dispute == null || !mounted || liveUpdates != _liveUpdates) return;
      ref
          .read(disputeNotifierProvider.notifier)
          .applyBridgeUpdate(disputeItemFromRust(dispute));
    } catch (e) {
      debugPrint('[disputes] refresh failed: $e');
    }
  }

  Future<bool> _onSendText(String tradeId, String text) async {
    if (_isSending) return false;
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _isSending = true);
    try {
      final sent = await ref
          .read(disputeChatGatewayProvider)
          .sendText(tradeId: tradeId, text: text);
      if (mounted) ref.read(disputeChatProvider(tradeId).notifier).add(sent);
      return true;
    } catch (e) {
      debugPrint('[disputes] send failed: $e');
      messenger.showSnackBar(
        SnackBar(
          content: Text(disputeSendErrorMessage(l10n, e)),
          backgroundColor: Colors.red,
        ),
      );
      return false;
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  /// Paperclip: pick, confirm, then send to the solver (#589 phase 3). The
  /// upload shows its own progress in the list.
  Future<void> _onAttachFile(String tradeId) async {
    if (_isAttaching) return;
    final picked = await pickAttachmentToSend(
      context,
      ref,
      onBusy: (busy) => setState(() => _isAttaching = busy),
      sheetNote: AppLocalizations.of(context).attachSheetBodySolver,
    );
    if (picked == null || !mounted) return;
    final sent = await ref
        .read(disputeUploadsProvider(tradeId).notifier)
        .send(picked.name, picked.bytes);
    if (sent != null && mounted) {
      ref.read(disputeChatProvider(tradeId).notifier).add(sent);
    }
  }

  /// Key button: confirm, then send the solver the peer chat key (#415). The
  /// dialog sends it and reports a failure itself.
  Future<void> _onShareChatKey(String tradeId) async {
    final gateway = ref.read(disputeChatGatewayProvider);
    final sent = await showShareChatKeyDialog(
      context: context,
      share: () => gateway.shareChatKey(tradeId),
    );
    if (!mounted) return;
    if (sent != null) {
      ref.read(disputeChatProvider(tradeId).notifier).add(sent);
    }
    // Shared now, or already: the record says which the button shows.
    unawaited(_refreshDispute(tradeId));
  }

  Future<void> _retryUpload(String tradeId, String uploadId) async {
    final sent = await ref
        .read(disputeUploadsProvider(tradeId).notifier)
        .retry(uploadId);
    if (sent != null && mounted) {
      ref.read(disputeChatProvider(tradeId).notifier).add(sent);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>();
    if (colors == null) throw StateError('AppColors theme extension must be registered');

    final dispute = ref.watch(disputeByIdProvider(widget.disputeId));

    if (dispute == null) {
      final l10n = AppLocalizations.of(context);
      return Scaffold(
        appBar: AppBar(
          title: Text(l10n.disputeScreenTitle),
          leading: const BackButton().withAutomationId(AutomationIds.appBarBack),
        ),
        body: Center(child: Text(l10n.disputeNotFound)),
      );
    }

    final tradeId = dispute.tradeId;
    _onDisputeKnown(tradeId);
    // The solver taking the dispute, and its resolution, while it is open.
    ref.listen(
      disputeUpdatesProvider(tradeId),
      (_, next) => next.whenData((update) {
        _liveUpdates++;
        // A takeover or a verdict: read who each solver is again, so a label
        // shown before the node's Serbero announcement arrived catches up.
        ref.invalidate(solverRoleProvider);
        ref
            .read(disputeNotifierProvider.notifier)
            .applyBridgeUpdate(disputeItemFromRust(update));
      }),
    );
    final messages = ref.watch(disputeChatProvider(tradeId));
    final uploads = ref.watch(disputeUploadsProvider(tradeId));
    // Who each solver is (#637): the current one and whoever wrote here —
    // Serbero, then the person who took over. A person until Rust answers.
    final roles = {
      for (final pubkey in <String>{
        if (dispute.adminPubkey case final admin?) admin,
        for (final m in messages)
          if (m.senderPubkey case final sender? when !m.isMine) sender,
      })
        pubkey:
            ref
                .watch(
                  solverRoleProvider((tradeId: tradeId, solverPubkey: pubkey)),
                )
                .valueOrNull,
    };

    final isResolved = dispute.status == DisputeStatus.resolved;
    // Only a solver can be written to: until one takes the dispute there is
    // nobody to share a key with.
    final canWrite =
        dispute.status == DisputeStatus.inReview && dispute.adminPubkey != null;

    return Scaffold(
      backgroundColor: OrderBookPalette.of(context).bg,
      // Who the dispute is with and its status open the conversation, in
      // the info card (#680); the bar names the screen, as v1's does. Its
      // back arrow carries `appbar.back`, like every other screen's.
      appBar: redesignAppBar(
        context,
        title: AppLocalizations.of(context).disputeDetailsTitle,
        onBack: () => Navigator.of(context).maybePop(),
        actions: [
          if (canWrite) ...[
            ShareChatKeyAction(
              shared: dispute.chatKeyShared,
              onPressed: () => _onShareChatKey(tradeId),
            ),
            // Its 48 target pads the 22 glyph by 13; the rest lines the
            // glyph up with the content below.
            const SizedBox(width: redesignSidePadding - 13),
          ],
        ],
      ),
      body: Column(
        children: [
          // ── Chat area ─────────────────────────────────────────────────
          Expanded(
            child: DisputeMessagesList(
              dispute: dispute,
              // Terminal state: the outcome scrolls under the info card.
              outcome: isResolved
                  ? _ResolvedBanner(
                      dispute: dispute,
                      colors: colors,
                      // The side the info card names, from the trade row.
                      isSelling: ref
                          .watch(disputeCounterpartProvider(tradeId))
                          .isSelling,
                    )
                  : null,
              messages: messages,
              uploads: uploads,
              roleOf: (pubkey) =>
                  roles[pubkey] ?? rust_types.SolverRole.human,
              onRetryUpload: (id) => _retryUpload(tradeId, id),
              onDiscardUpload:
                  (id) => ref
                      .read(disputeUploadsProvider(tradeId).notifier)
                      .discard(id),
            ),
          ),

          // ── Message input (solver assigned only) ─────────────────────
          if (canWrite)
            Padding(
              // #267: add the bottom system-bar inset so the message input
              // clears the gesture / 3-button navigation bar.
              padding: EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.xs,
                AppSpacing.md,
                AppSpacing.md + MediaQuery.of(context).viewPadding.bottom,
              ),
              child: DisputeMessageInput(
                onSendText: (text) => _onSendText(tradeId, text),
                onAttachFile: () => _onAttachFile(tradeId),
                isAttaching: _isAttaching,
                isSending: _isSending,
              ),
            ),
        ],
      ),
    );
  }
}

/// Why a message to the solver was not sent, localized from the marker
/// `submit_evidence` fails with (CLAUDE.md, *Translations*).
String disputeSendErrorMessage(AppLocalizations l10n, Object error) {
  final raw = error.toString();
  if (raw.contains('AdminNotAssigned')) return l10n.disputeSolverNotAssigned;
  if (raw.contains('NoOpenDispute')) return l10n.disputeChatClosed;
  return l10n.messageSendFailed;
}

// ── Terminal state banners ─────────────────────────────────────────────────────

/// Shown above the chat when the dispute is resolved.
///
/// Three sub-cases driven by [DisputeResolution]:
/// - [DisputeResolution.fundsToBuyer] or [DisputeResolution.fundsToSeller] where the
///   viewing party won → green checkmark + "Successfully completed"
/// - [DisputeResolution.cooperativeCancel] → blue "Resolved" badge + cooperative cancel text
/// - [DisputeResolution.fundsToBuyer] or [DisputeResolution.fundsToSeller] where the
///   viewing party lost → blue "Resolved" badge + role-aware outcome text
/// - the viewing party's side unknown → the same badge + a neutral outcome
class _ResolvedBanner extends StatelessWidget {
  const _ResolvedBanner({
    required this.dispute,
    required this.colors,
    required this.isSelling,
  });

  final DisputeItem dispute;
  final AppColors colors;

  /// The user's side of the trade, null while unknown: then nobody is told
  /// they won or lost.
  final bool? isSelling;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final textTheme = Theme.of(context).textTheme;

    if (dispute.resolution == DisputeResolution.cooperativeCancel) {
      // ── Cooperative cancel: both parties agreed ───────────────────────
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.all(AppSpacing.md),
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.statusActive.$1,
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: 3,
              ),
              decoration: BoxDecoration(
                color: AppColors.statusActive.$2.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(AppRadius.chip),
              ),
              child: Text(
                l10n.disputeResolved,
                style: textTheme.bodySmall?.copyWith(
                  color: AppColors.statusActive.$2,
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              l10n.disputeCoopCancelMessage,
              style: textTheme.bodySmall?.copyWith(
                color: AppColors.statusActive.$2,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Icon(Icons.lock_outline, size: 14, color: AppColors.statusActive.$2),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    l10n.disputeChatClosed,
                    style: textTheme.bodySmall?.copyWith(
                      color: AppColors.statusActive.$2,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    // Determine if the viewing party "won" the dispute.
    final isSelling = this.isSelling;
    final userWon = switch ((dispute.resolution, isSelling)) {
      (DisputeResolution.fundsToBuyer, false) => true,
      (DisputeResolution.fundsToSeller, true) => true,
      _ => false,
    };

    if (userWon) {
      // ── Viewing party won: green success state ────────────────────────
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.all(AppSpacing.md),
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.statusSuccess.$1,
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        child: Column(
          children: [
            Icon(
              Icons.check_circle_outline,
              color: AppColors.statusSuccess.$2,
              size: 32,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              l10n.disputeSuccessfullyCompleted,
              style: textTheme.bodyMedium?.copyWith(
                color: AppColors.statusSuccess.$2,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.lock_outline, size: 14, color: AppColors.statusSuccess.$2),
                const SizedBox(width: AppSpacing.xs),
                Flexible(
                  child: Text(
                    l10n.disputeChatClosed,
                    style: textTheme.bodySmall?.copyWith(
                      color: AppColors.statusSuccess.$2,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    // ── Viewing party lost: blue "Resolved" badge + outcome message ──────
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.statusActive.$1,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: 3,
            ),
            decoration: BoxDecoration(
              color: AppColors.statusActive.$2.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(AppRadius.chip),
            ),
            child: Text(
              l10n.disputeResolved,
              style: textTheme.bodySmall?.copyWith(
                color: AppColors.statusActive.$2,
                fontWeight: FontWeight.bold,
                fontSize: 11,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: AppColors.statusSuccess.$1,
              borderRadius: BorderRadius.circular(AppRadius.card),
            ),
            child: Text(
              _outcomeText(dispute.resolution, isSelling, l10n),
              style: textTheme.bodySmall?.copyWith(
                color: AppColors.statusSuccess.$2,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Icon(Icons.lock_outline, size: 14, color: AppColors.statusActive.$2),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  l10n.disputeChatClosed,
                  style: textTheme.bodySmall?.copyWith(
                    color: AppColors.statusActive.$2,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// The outcome when the viewing party did not win, or when their side is
  /// unknown ([isSelling] null) and the outcome is told without a side.
  ///
  /// Only called when [userWon] is false and resolution is not
  /// [DisputeResolution.cooperativeCancel], so the reachable cases are:
  /// - [DisputeResolution.fundsToBuyer] with isSelling=true (seller lost)
  /// - [DisputeResolution.fundsToSeller] with isSelling=false (buyer lost)
  /// - either verdict, or none, with the side unknown
  static String _outcomeText(
    DisputeResolution? resolution,
    bool? isSelling,
    AppLocalizations l10n,
  ) => switch ((resolution, isSelling)) {
    // Seller lost: admin released funds to the buyer.
    (DisputeResolution.fundsToBuyer, true) => l10n.disputeLostFundsToBuyer,
    // Buyer lost: admin returned funds to the seller.
    (DisputeResolution.fundsToSeller, false) => l10n.disputeLostFundsToSeller,
    (DisputeResolution.fundsToBuyer, _) => l10n.disputeDescResolvedBuyerFavour,
    (DisputeResolution.fundsToSeller, _) =>
      l10n.disputeDescResolvedSellerFavour,
    _ => l10n.disputeDescResolved,
  };
}

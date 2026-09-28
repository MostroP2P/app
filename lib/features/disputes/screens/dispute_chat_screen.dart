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
import 'package:mostro/features/notifications/models/notification_model.dart';
import 'package:mostro/features/notifications/providers/notifications_provider.dart';

/// Dispute chat screen — Route `/dispute_details/:disputeId`.
///
/// Layout:
///   - Custom header: "Dispute with Buyer/Seller: [handle]" + status badge
///   - Scrollable [DisputeMessagesList] (info card + bubbles + banners)
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
        ref
            .read(disputeNotifierProvider.notifier)
            .applyBridgeUpdate(disputeItemFromRust(update));
      }),
    );
    final messages = ref.watch(disputeChatProvider(tradeId));
    final uploads = ref.watch(disputeUploadsProvider(tradeId));

    final isResolved = dispute.status == DisputeStatus.resolved;
    // Only a solver can be written to: until one takes the dispute there is
    // nobody to share a key with.
    final canWrite =
        dispute.status == DisputeStatus.inReview && dispute.adminPubkey != null;

    return Scaffold(
      appBar: AppBar(
        title: _HeaderTitle(dispute: dispute, colors: colors),
        titleSpacing: 0,
        // The dispute screen is pushed over the trade detail; automation
        // leaves it the way it leaves every other screen (`appbar.back`).
        leading: const BackButton().withAutomationId(AutomationIds.appBarBack),
      ),
      body: Column(
        children: [
          // ── Terminal state: resolved ──────────────────────────────────
          if (isResolved) _ResolvedBanner(dispute: dispute, colors: colors),

          // ── Chat area ─────────────────────────────────────────────────
          Expanded(
            child: DisputeMessagesList(
              dispute: dispute,
              messages: messages,
              uploads: uploads,
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

// ── Header title ──────────────────────────────────────────────────────────────

class _HeaderTitle extends StatelessWidget {
  const _HeaderTitle({required this.dispute, required this.colors});

  final DisputeItem dispute;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final textTheme = Theme.of(context).textTheme;
    final handle = dispute.peerHandle ?? l10n.unknownPeerHandle;

    final title = dispute.isSelling
        ? l10n.disputeWithBuyer(handle)
        : l10n.disputeWithSeller(handle);

    final truncatedId = dispute.tradeId.length > 12
        ? '${dispute.tradeId.substring(0, 12)}\u2026'
        : dispute.tradeId;

    final (statusBg, statusFg, statusLabel) = _statusChip(dispute.status, l10n);

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: textTheme.titleMedium?.copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.bold,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                l10n.orderLabel(truncatedId),
                style: textTheme.bodySmall?.copyWith(color: colors.textSubtle),
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 3),
          decoration: BoxDecoration(
            color: statusBg,
            borderRadius: BorderRadius.circular(AppRadius.chip),
          ),
          child: Text(
            statusLabel,
            style: textTheme.bodySmall?.copyWith(
              color: statusFg,
              fontWeight: FontWeight.w500,
              fontSize: 11,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
      ],
    );
  }

  static (Color, Color, String) _statusChip(
    DisputeStatus status,
    AppLocalizations l10n,
  ) {
    return switch (status) {
      DisputeStatus.open => (
        AppColors.statusPending.$1,
        AppColors.statusPending.$2,
        l10n.disputeInitiated,
      ),
      DisputeStatus.inReview => (
        AppColors.statusActive.$1,
        AppColors.statusActive.$2,
        l10n.disputeInProgress,
      ),
      DisputeStatus.resolved => (
        AppColors.statusInactive.$1,
        AppColors.statusInactive.$2,
        l10n.disputeStatusClosed,
      ),
    };
  }
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
class _ResolvedBanner extends StatelessWidget {
  const _ResolvedBanner({required this.dispute, required this.colors});

  final DisputeItem dispute;
  final AppColors colors;

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
    final userWon =
        (dispute.resolution == DisputeResolution.fundsToBuyer && !dispute.isSelling) ||
        (dispute.resolution == DisputeResolution.fundsToSeller && dispute.isSelling);

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
              _lostResolutionText(dispute, l10n),
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

  /// Returns the outcome description for the party who did not win.
  ///
  /// Only called when [userWon] is false and resolution is not
  /// [DisputeResolution.cooperativeCancel], so the two reachable cases are:
  /// - [DisputeResolution.fundsToBuyer] with isSelling=true (seller lost)
  /// - [DisputeResolution.fundsToSeller] with isSelling=false (buyer lost)
  static String _lostResolutionText(DisputeItem dispute, AppLocalizations l10n) {
    if (dispute.isSelling) {
      // Seller lost: admin released funds to the buyer.
      return l10n.disputeLostFundsToBuyer;
    }
    // Buyer lost: admin returned funds to the seller.
    return l10n.disputeLostFundsToSeller;
  }
}

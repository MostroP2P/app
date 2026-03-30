import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/disputes/providers/disputes_providers.dart';
import 'package:mostro/features/disputes/widgets/dispute_message_input.dart';
import 'package:mostro/features/disputes/widgets/dispute_messages_list.dart';

/// Dispute chat screen — Route `/dispute_details/:disputeId`.
///
/// Layout:
///   - Custom header: "Dispute with Buyer/Seller: [handle]" + status badge
///   - Scrollable [DisputeMessagesList] (info card + bubbles + banners)
///   - [DisputeMessageInput] — only visible when status == in-progress
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
  bool _isAttaching = false;

  @override
  void initState() {
    super.initState();
    // Mark as read as soon as the screen opens.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(disputeNotifierProvider.notifier).markRead(widget.disputeId);
    });
  }

  void _onSendText(String text) {
    // TODO(bridge): Encrypt with adminSharedKey and publish via Rust bridge.
  }

  void _onAttachFile() async {
    // TODO(bridge): Open file picker, encrypt with adminSharedKey, upload.
    setState(() => _isAttaching = true);
    await Future.delayed(const Duration(milliseconds: 300));
    if (mounted) setState(() => _isAttaching = false);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>();
    assert(colors != null, 'AppColors theme extension must be registered');
    if (colors == null) return const SizedBox.shrink();

    final dispute = ref.watch(disputeByIdProvider(widget.disputeId));

    if (dispute == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Dispute')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    // Stub messages list — will be driven by bridge events in Phase 13+.
    const List<DisputeMessage> messages = [];

    final isResolved = dispute.status == DisputeStatus.resolved;
    final isInProgress = dispute.status == DisputeStatus.inReview ||
        dispute.status == DisputeStatus.open;

    return Scaffold(
      appBar: AppBar(
        title: _HeaderTitle(dispute: dispute, colors: colors),
        titleSpacing: 0,
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
            ),
          ),

          // ── Message input (in-progress only) ─────────────────────────
          if (isInProgress)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.xs,
                AppSpacing.md,
                AppSpacing.md,
              ),
              child: DisputeMessageInput(
                onSendText: _onSendText,
                onAttachFile: _onAttachFile,
                isAttaching: _isAttaching,
              ),
            ),
        ],
      ),
    );
  }
}

// ── Header title ──────────────────────────────────────────────────────────────

class _HeaderTitle extends StatelessWidget {
  const _HeaderTitle({required this.dispute, required this.colors});

  final DisputeItem dispute;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final handle = dispute.peerHandle ?? 'Unknown';
    final role = dispute.isSelling ? 'Buyer' : 'Seller';

    final (statusBg, statusFg, statusLabel) = _statusChip(dispute.status);

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Dispute with $role: $handle',
                style: textTheme.titleMedium?.copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.bold,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                'Order ${dispute.tradeId.length > 12 ? '${dispute.tradeId.substring(0, 12)}…' : dispute.tradeId}',
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

  static (Color, Color, String) _statusChip(DisputeStatus status) {
    return switch (status) {
      DisputeStatus.open => (
        AppColors.statusPending.$1,
        AppColors.statusPending.$2,
        'Initiated',
      ),
      DisputeStatus.inReview => (
        AppColors.statusActive.$1,
        AppColors.statusActive.$2,
        'In progress',
      ),
      DisputeStatus.resolved => (
        AppColors.statusInactive.$1,
        AppColors.statusInactive.$2,
        'Closed',
      ),
    };
  }
}

// ── Terminal state banners ─────────────────────────────────────────────────────

/// Shown above the chat when the dispute is resolved.
///
/// Two sub-cases driven by [DisputeResolution]:
/// - [DisputeResolution.fundsToMe] → green checkmark + "Successfully completed"
/// - [DisputeResolution.fundsToCounterparty] → blue "Resolved" badge + refund text
class _ResolvedBanner extends StatelessWidget {
  const _ResolvedBanner({required this.dispute, required this.colors});

  final DisputeItem dispute;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    if (dispute.resolution == DisputeResolution.fundsToMe) {
      // ── Funds to me: green success state ──────────────────────────────
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
              'Successfully completed',
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
                Text(
                  'This dispute has been resolved. The chat is closed.',
                  style: textTheme.bodySmall?.copyWith(
                    color: AppColors.statusSuccess.$2,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    // ── Funds to counterparty: blue "Resolved" badge + refund message ──
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
              'Resolved',
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
              'The administrator canceled the order and refunded you. '
              'The buyer did not receive the sats.',
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
                  'This dispute has been resolved. The chat is closed.',
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
}

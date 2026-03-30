import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/disputes/providers/disputes_providers.dart';

// ── DisputeMessagesList ───────────────────────────────────────────────────────

/// Scrollable list of dispute messages with info card and optional banners.
///
/// Slot order (always shown in this sequence):
///   1. [DisputeInfoCard] — always first
///   2. "Admin assigned" banner — shown when status is `inReview` and no
///      messages yet
///   3. [DisputeMessageBubble] entries — sorted by `createdAt`, deduped by
///      `nostrEventId` if present
///   4. "Chat closed" lock banner — shown when status is resolved/closed
///
/// Auto-scrolls to bottom when new messages arrive.
class DisputeMessagesList extends StatefulWidget {
  const DisputeMessagesList({
    super.key,
    required this.dispute,
    required this.messages,
  });

  final DisputeItem dispute;
  final List<DisputeMessage> messages;

  @override
  State<DisputeMessagesList> createState() => _DisputeMessagesListState();
}

class _DisputeMessagesListState extends State<DisputeMessagesList> {
  final ScrollController _scrollController = ScrollController();

  @override
  void didUpdateWidget(DisputeMessagesList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.messages.length != oldWidget.messages.length) {
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>();
    assert(colors != null, 'AppColors theme extension must be registered');
    if (colors == null) return const SizedBox.shrink();

    // Deduplicate by nostrEventId where present.
    final seen = <String>{};
    final deduped = widget.messages.where((m) {
      final key = m.nostrEventId ?? m.id;
      return seen.add(key);
    }).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

    final isResolved = widget.dispute.status == DisputeStatus.resolved;
    final isInReview = widget.dispute.status == DisputeStatus.inReview;

    return CustomScrollView(
      controller: _scrollController,
      slivers: [
        // 1. Info card (always first)
        SliverToBoxAdapter(
          child: DisputeInfoCard(dispute: widget.dispute, colors: colors),
        ),

        // 2. "Admin assigned" banner (inReview + no messages)
        if (isInReview && deduped.isEmpty)
          const SliverToBoxAdapter(
            child: _AdminAssignedBanner(),
          ),

        // 3. Message bubbles
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) => DisputeMessageBubble(
              message: deduped[index],
              colors: colors,
            ),
            childCount: deduped.length,
          ),
        ),

        // 4. "Chat closed" lock banner (resolved state)
        if (isResolved)
          SliverToBoxAdapter(
            child: _ChatClosedBanner(colors: colors),
          ),

        // Bottom padding
        const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xl)),
      ],
    );
  }
}

// ── DisputeInfoCard ───────────────────────────────────────────────────────────

/// Always-first card showing order/dispute IDs and dispute details.
class DisputeInfoCard extends StatelessWidget {
  const DisputeInfoCard({
    super.key,
    required this.dispute,
    required this.colors,
  });

  final DisputeItem dispute;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Card(
      margin: const EdgeInsets.all(AppSpacing.md),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Dispute Details',
              style: textTheme.bodyLarge?.copyWith(
                color: colors.textPrimary,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            _IdRow(
              label: 'Order ID',
              value: dispute.tradeId,
              colors: colors,
              textTheme: textTheme,
            ),
            _IdRow(
              label: 'Dispute ID',
              value: dispute.id,
              colors: colors,
              textTheme: textTheme,
            ),
            if (dispute.reason != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Reason: ${dispute.reason}',
                style: textTheme.bodySmall?.copyWith(color: colors.textSecondary),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _IdRow extends StatelessWidget {
  const _IdRow({
    required this.label,
    required this.value,
    required this.colors,
    required this.textTheme,
  });

  final String label;
  final String value;
  final AppColors colors;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Clipboard.setData(ClipboardData(text: value));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$label copied'),
            duration: const Duration(seconds: 2),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Text(
              '$label: ',
              style: textTheme.bodySmall?.copyWith(color: colors.textSubtle),
            ),
            Expanded(
              child: Text(
                value,
                style: textTheme.bodySmall?.copyWith(
                  color: colors.blueAccent,
                  fontFamily: 'monospace',
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── DisputeMessageBubble ──────────────────────────────────────────────────────

/// Single message bubble in the dispute chat.
///
/// - Own → right-aligned, purple (`colors.purpleButton`)
/// - Admin → left-aligned, dark gray
/// - System → centered italic
class DisputeMessageBubble extends StatelessWidget {
  const DisputeMessageBubble({
    super.key,
    required this.message,
    required this.colors,
  });

  final DisputeMessage message;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    if (message.isSystem) {
      return Padding(
        padding: const EdgeInsets.symmetric(
          vertical: AppSpacing.sm,
          horizontal: AppSpacing.xl,
        ),
        child: Center(
          child: Text(
            message.content,
            textAlign: TextAlign.center,
            style: textTheme.bodySmall?.copyWith(
              color: colors.systemMessage,
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
      );
    }

    final isMine = message.isMine;
    final bubbleColor = isMine
        ? colors.purpleButton
        : const Color(0xFF2D3142); // admin/peer dark gray

    final borderRadius = isMine
        ? const BorderRadius.only(
            topLeft: Radius.circular(AppRadius.bubble),
            topRight: Radius.zero,
            bottomLeft: Radius.circular(AppRadius.bubble),
            bottomRight: Radius.circular(AppRadius.bubble),
          )
        : const BorderRadius.only(
            topLeft: Radius.zero,
            topRight: Radius.circular(AppRadius.bubble),
            bottomLeft: Radius.circular(AppRadius.bubble),
            bottomRight: Radius.circular(AppRadius.bubble),
          );

    return GestureDetector(
      onLongPress: () {
        Clipboard.setData(ClipboardData(text: message.content));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Copied'),
            duration: Duration(seconds: 2),
          ),
        );
      },
      child: Padding(
        padding: EdgeInsets.only(
          left: isMine ? AppSpacing.xl : AppSpacing.lg,
          right: isMine ? AppSpacing.lg : AppSpacing.xl,
          top: AppSpacing.xs,
          bottom: AppSpacing.xs,
        ),
        child: Align(
          alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.72,
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: bubbleColor,
              borderRadius: borderRadius,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (message.isAdmin && !message.isMine)
                  Text(
                    'Admin',
                    style: textTheme.bodySmall?.copyWith(
                      color: colors.tealAccent,
                      fontWeight: FontWeight.bold,
                      fontSize: 10,
                    ),
                  ),
                Text(
                  message.content,
                  style: textTheme.bodyMedium
                      ?.copyWith(color: Colors.white),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Banners ───────────────────────────────────────────────────────────────────

class _AdminAssignedBanner extends StatelessWidget {
  const _AdminAssignedBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.statusActive.$1,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Row(
        children: [
          Icon(Icons.support_agent, color: AppColors.statusActive.$2, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'An administrator has been assigned to your dispute. '
              'They will contact you here shortly.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.statusActive.$2,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatClosedBanner extends StatelessWidget {
  const _ChatClosedBanner({required this.colors});
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.lock_outline, size: 14, color: colors.textSubtle),
          const SizedBox(width: AppSpacing.xs),
          Text(
            'This dispute has been resolved. The chat is closed.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colors.textSubtle,
                  fontStyle: FontStyle.italic,
                ),
          ),
        ],
      ),
    );
  }
}

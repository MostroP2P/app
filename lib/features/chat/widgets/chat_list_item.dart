import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/chat/providers/chat_providers.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/widgets/nym_avatar.dart';

/// A single row in the chat rooms list.
///
/// Shows the peer's avatar, handle, trade context, last message preview,
/// a timestamp chip, and an unread-count dot when applicable.
class ChatListItem extends StatelessWidget {
  const ChatListItem({
    super.key,
    required this.room,
    required this.onTap,
  });

  final ChatRoomState room;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>();
    assert(colors != null, 'AppColors theme extension must be registered');
    if (colors == null) return const SizedBox.shrink();
    final textTheme = Theme.of(context).textTheme;

    final contextLine = room.isSelling
        ? 'You are selling sats to ${room.peerHandle}'
        : 'You are buying sats from ${room.peerHandle}';

    final previewText = room.lastMessage == null
        ? null
        : room.lastMessageIsOwn
            ? 'You: ${room.lastMessage}'
            : room.lastMessage;

    final l10n = AppLocalizations.of(context);
    final timestampLabel = room.lastMessageAt > 0
        ? _formatTimestamp(room.lastMessageAt, l10n)
        : '';

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Avatar
            NymAvatar(
              iconIndex: room.peerIconIndex,
              colorHue: room.peerColorHue,
              size: 46,
            ),
            const SizedBox(width: AppSpacing.md),

            // Text section
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Peer handle
                  Text(
                    room.peerHandle,
                    style: textTheme.bodyLarge?.copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),

                  // Context line
                  Text(
                    contextLine,
                    style: textTheme.bodySmall?.copyWith(
                      color: colors.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),

                  // Last message preview
                  if (previewText != null) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      previewText,
                      style: textTheme.bodySmall?.copyWith(
                        color: colors.textSubtle,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),

            // Trailing: timestamp + unread dot
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (timestampLabel.isNotEmpty)
                  Text(
                    timestampLabel,
                    style: textTheme.bodySmall?.copyWith(
                      color: colors.textSubtle,
                      fontSize: 11,
                    ),
                  ),
                if (room.unreadCount > 0) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: colors.destructiveRed,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Formats a unix timestamp as a human-friendly label.
  ///
  /// - Same day → locale time (e.g. "14:32")
  /// - Yesterday → localized "Yesterday" from [AppLocalizations]
  /// - Older → locale short date (e.g. "Mar 30")
  String _formatTimestamp(int unixSeconds, AppLocalizations l10n) {
    final dt = DateTime.fromMillisecondsSinceEpoch(unixSeconds * 1000);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final msgDay = DateTime(dt.year, dt.month, dt.day);

    if (msgDay == today) {
      return DateFormat.Hm().format(dt);
    }

    final yesterday = today.subtract(const Duration(days: 1));
    if (msgDay == yesterday) {
      return l10n.chatTimestampYesterday;
    }

    return DateFormat.MMMd().format(dt);
  }
}

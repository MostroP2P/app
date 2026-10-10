import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:mostro/core/app_routes.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/core/trade_palette.dart';
import 'package:mostro/features/chat/providers/chat_providers.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/widgets/tab_app_bar.dart' show CountBadge;

/// The chat card of an active trade (21a): it says who the user chats with
/// by role — "Chat with the buyer" when they sell, "the seller" when they buy
/// — over "End-to-end encrypted", with a filled lime icon, a lime stroke
/// and an explicit "Open", so it reads as a place to write rather than a
/// label. With unread messages the second line counts them instead, and the
/// badge on the icon says the same.
///
/// No alias: the role already says who is on the other side, and the room
/// shows the alias once opened. So the card never needs the counterpart's
/// identity, and never reads "Unknown" while the chat rooms are still being
/// built (only on hydration, from the Chat tab or from the room itself).
///
/// [closed] once the conversation has ended: muted, with a line that the
/// messages can still be read, and no "Open". The tap opens the room,
/// read-only. The unread badge stays: the messages are unread until the room
/// is opened, and the chat list and the Chat tab count them too.
class TradeChatCard extends ConsumerWidget {
  const TradeChatCard({
    super.key,
    required this.orderId,
    this.closed = false,
    this.isSelling,
  });

  final String orderId;
  final bool closed;

  /// The trade's side as the screen knows it, for the title while the chat
  /// room has not loaded; the room's own side wins once it has.
  final bool? isSelling;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final book = OrderBookPalette.of(context);
    final trade = TradePalette.of(context);
    final l10n = AppLocalizations.of(context);

    final room =
        ref
            .watch(chatRoomsNotifierProvider)
            .where((r) => r.orderId == orderId)
            .firstOrNull;
    final unread = room?.unreadCount ?? 0;
    // A seller chats with the buyer, and the other way round.
    final withRole = switch (room?.isSelling ?? isSelling) {
      true => l10n.tradeChatWithBuyer,
      false => l10n.tradeChatWithSeller,
      null => l10n.tradeChatWithCounterpart,
    };
    final subtitle =
        closed
            ? l10n.tradeChatClosed
            : unread > 0
            ? l10n.tradeChatNewMessages(unread)
            : l10n.tradeChatEncrypted;
    final radius = BorderRadius.circular(18);
    void open() => context.push(AppRoute.chatRoomPath(orderId));

    // DS-A11Y-1: one button that reads the role and the second line, with
    // "Open" as its hint; the texts and the badge under it stay silent.
    return Semantics(
      button: true,
      enabled: true,
      label: '$withRole. $subtitle',
      hint: closed ? null : l10n.tradeChatOpen,
      onTap: open,
      excludeSemantics: true,
      child: Material(
        color: closed ? book.surface : trade.chatActiveBg,
        borderRadius: radius,
        child: InkWell(
          onTap: open,
          borderRadius: radius,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              border: Border.all(
                color: closed ? book.border : trade.chatActiveBorder,
                width: closed ? 1 : 1.5,
              ),
              borderRadius: radius,
            ),
            child: Row(
              children: [
                _Avatar(unread: unread, closed: closed),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        withRole,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: closed ? book.textSecondary : book.textStrong,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 2,
                        style: TextStyle(
                          fontSize: 12,
                          color:
                              closed ? book.textTertiary : book.textSecondary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (!closed)
                  Text(
                    l10n.tradeChatOpen,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: book.limeText,
                    ),
                  ),
                Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: closed ? book.textTertiary : book.limeText,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.unread, required this.closed});

  final int unread;
  final bool closed;

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    final trade = TradePalette.of(context);

    return SizedBox(
      width: 44,
      height: 42,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            top: 1,
            // Filled lime while the chat is open (DS-COL-4: its ink on it);
            // the soft tint once it has closed.
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: closed ? trade.avatarBg : book.lime,
                border: closed ? Border.all(color: trade.avatarBorder) : null,
              ),
              child: Icon(
                Icons.chat_bubble_outline,
                size: 20,
                color: closed ? book.textTertiary : book.onLime,
              ),
            ),
          ),
          if (unread > 0)
            Positioned(
              right: 0,
              top: -3,
              // The shared badge (99+ past 99), ringed in the card's surface
              // to stand off the icon. A Container insets its child by the
              // border, so 13 + 2 × 1.5 keeps it 16 high, and a padding of 3
              // keeps one digit inside 13: a 16 dp circle, a pill past it.
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: book.surface, width: 1.5),
                ),
                child: CountBadge(
                  count: unread,
                  background: book.lime,
                  foreground: book.onLime,
                  size: 13,
                  padding: 3,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// What stands in for the chat before the trade is active (8a): nobody knows
/// who the other party is yet, and the line says so.
class TradeChatLockedLine extends StatelessWidget {
  const TradeChatLockedLine({super.key});

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    final trade = TradePalette.of(context);
    final l10n = AppLocalizations.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: trade.lockedBg,
        border: Border.all(color: trade.lockedBorder),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(Icons.lock_outline, size: 15, color: book.textTertiary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              l10n.tradeChatLockedNote,
              style: TextStyle(
                fontSize: 11,
                height: 1.5,
                color: book.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

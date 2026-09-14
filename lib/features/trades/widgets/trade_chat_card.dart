import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:mostro/core/app_routes.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/core/trade_palette.dart';
import 'package:mostro/features/chat/providers/chat_providers.dart';
import 'package:mostro/l10n/app_localizations.dart';

/// The chat card of an active trade: the counterpart's alias, the unread
/// badge from the message stream, and a tap into the room. The alias is the
/// datum — never a "your counterpart" placeholder once the trade is active.
class TradeChatCard extends ConsumerWidget {
  const TradeChatCard({super.key, required this.orderId});

  final String orderId;

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
    final alias = room?.displayHandle(l10n) ?? l10n.unknownPeerHandle;
    final unread = room?.unreadCount ?? 0;

    return Material(
      color: book.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: () => context.push(AppRoute.chatRoomPath(orderId)),
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            border: Border.all(color: trade.chatBorder),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              _Avatar(unread: unread),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      alias,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: book.textStrong,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      l10n.tradeChatEncrypted,
                      style: TextStyle(fontSize: 11, color: book.textTertiary),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right, size: 18, color: book.limeIcon),
            ],
          ),
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.unread});

  final int unread;

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    final trade = TradePalette.of(context);

    return SizedBox(
      width: 38,
      height: 36,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            top: 1,
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: trade.avatarBg,
                border: Border.all(color: trade.avatarBorder),
              ),
              child: Icon(
                Icons.chat_bubble_outline,
                size: 16,
                color: book.limeText,
              ),
            ),
          ),
          if (unread > 0)
            Positioned(
              right: 0,
              top: -3,
              child: Container(
                constraints: const BoxConstraints(minWidth: 16),
                height: 16,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: book.lime,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: book.surface, width: 1.5),
                ),
                child: Text(
                  '$unread',
                  style: TextStyle(
                    fontFamily: AppFonts.figures,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    height: 1,
                    color: book.onLime,
                  ),
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

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'package:mostro/core/activity_palette.dart';
import 'package:mostro/core/app_theme.dart' show AppFonts;
import 'package:mostro/core/order_book_palette.dart';
import 'package:mostro/features/chat/models/chat_list_rules.dart';
import 'package:mostro/features/chat/providers/chat_list_provider.dart';
import 'package:mostro/features/chat/providers/chat_providers.dart';
import 'package:mostro/features/trades/models/trades_list_rules.dart';
import 'package:mostro/features/trades/providers/trade_rows_provider.dart';
import 'package:mostro/features/trades/widgets/trade_list_chip.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/widgets/tab_app_bar.dart' show CountBadge;

/// One conversation of the chat list (handoff 11b): an avatar tinted by the
/// trade's state, the alias, which trade this is and where it stands, and
/// the last message — bold with a badge while unread.
class ChatListItem extends StatelessWidget {
  const ChatListItem({
    super.key,
    required this.row,
    required this.onTap,
    this.isLast = false,
  });

  final ChatListRow row;
  final VoidCallback onTap;

  /// The last row of its card draws no divider: the card edge separates it.
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    final pal = ActivityPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toString();
    final room = row.room;
    final handle = room.displayHandle(l10n);
    final unread = room.unreadCount > 0;
    final context_ = chatContextLine(row.trade, l10n, locale);

    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: DecoratedBox(
        decoration: BoxDecoration(
          border:
              isLast ? null : Border(bottom: BorderSide(color: pal.rowDivider)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ChatAvatar(
                initial: handle,
                tone: row.state.tone,
                showsActiveDot: row.state.showsActiveDot,
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            handle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: book.textPrimary,
                            ),
                          ),
                        ),
                        if (room.lastMessageAt > 0)
                          Text(
                            _time(room.lastMessageAt, l10n, locale),
                            style: TextStyle(
                              fontFamily: AppFonts.figures,
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                              color: unread ? book.limeIcon : book.textFaint,
                            ),
                          ),
                      ],
                    ),
                    if (context_ != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        context_,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: book.textTertiary,
                        ),
                      ),
                    ],
                    if (room.lastMessage != null) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Expanded(
                            child: Text.rich(
                              TextSpan(
                                children: [
                                  if (room.lastMessageIsOwn)
                                    TextSpan(
                                      text: '${l10n.chatYouLabel} ',
                                      style: TextStyle(
                                        color: book.textFaint,
                                        fontWeight: FontWeight.w400,
                                      ),
                                    ),
                                  TextSpan(text: room.lastMessage),
                                ],
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                height: 1.35,
                                fontWeight:
                                    unread ? FontWeight.w500 : FontWeight.w400,
                                color:
                                    unread
                                        ? book.textStrong
                                        : book.textSecondary,
                              ),
                            ),
                          ),
                          if (unread) ...[
                            const SizedBox(width: 8),
                            CountBadge(
                              count: room.unreadCount,
                              background: pal.badgeBg,
                              foreground: pal.badgeInk,
                            ),
                          ],
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// `14:32` today, `ayer`, then a short date.
  static String _time(int unixSeconds, AppLocalizations l10n, String locale) {
    final at = DateTime.fromMillisecondsSinceEpoch(unixSeconds * 1000);
    final now = clock.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(at.year, at.month, at.day);
    if (day == today) return DateFormat.Hm(locale).format(at);
    if (today.difference(day).inDays == 1) return l10n.chatTimestampYesterday;
    return DateFormat.MMMd(locale).format(at);
  }
}

/// `Le vendes 55 BOB · te toca liberar`, `Le compraste 6.666 ARS ·
/// completada`: which trade the conversation is about and where it stands.
/// The verb is present while the trade is open and past once it closed. Null
/// while the trade has not loaded.
String? chatContextLine(TradeRow? trade, AppLocalizations l10n, String locale) {
  if (trade == null) return null;
  final amount = formatFiatAmount(
    amount: trade.fiatAmount,
    min: trade.fiatAmountMin,
    max: trade.fiatAmountMax,
    locale: locale,
  );
  final closed = isTradeFinished(trade.status);
  final what = switch ((trade.isSelling, closed)) {
    (true, false) => l10n.chatContextSellActive(amount, trade.fiatCode),
    (false, false) => l10n.chatContextBuyActive(amount, trade.fiatCode),
    (true, true) => l10n.chatContextSellClosed(amount, trade.fiatCode),
    (false, true) => l10n.chatContextBuyClosed(amount, trade.fiatCode),
  };
  final where = switch (trade.state.verb) {
    TradeRowVerb.addInvoice => l10n.chatTurnAddInvoice,
    TradeRowVerb.payInvoice => l10n.chatTurnPayInvoice,
    TradeRowVerb.sendPayment => l10n.chatTurnSendPayment,
    TradeRowVerb.releaseSats => l10n.chatTurnRelease,
    TradeRowVerb.rate => l10n.chatTurnRate,
    TradeRowVerb.none =>
      TradeListChip.text(trade.state.chip, l10n).toLowerCase(),
  };
  return '$what · $where';
}

/// The initial of the alias on a state-tinted circle, with the lime dot of
/// an open trade at its lower right.
class ChatAvatar extends StatelessWidget {
  const ChatAvatar({
    super.key,
    required this.initial,
    required this.tone,
    required this.showsActiveDot,
    this.dispute = false,
  });

  /// The alias; only its first character is drawn.
  final String initial;
  final ChatAvatarTone tone;
  final bool showsActiveDot;

  /// Tints the circle coral: an open dispute.
  final bool dispute;

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    final pal = ActivityPalette.of(context);
    final (bg, ink) =
        dispute
            ? (pal.chipDisputeBg, pal.chipDisputeInk)
            : switch (tone) {
              ChatAvatarTone.yourTurn => (
                pal.avatarActiveBg,
                pal.chipActionInk,
              ),
              ChatAvatarTone.waiting => (pal.avatarWaitBg, pal.chipWaitInk),
              ChatAvatarTone.closed => (
                pal.avatarClosedBg,
                pal.avatarClosedInk,
              ),
            };
    final letter =
        initial.trim().isEmpty ? '?' : initial.trim().characters.first;
    return SizedBox(
      width: 38,
      height: 38,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
            child: Text(
              letter.toUpperCase(),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: ink,
              ),
            ),
          ),
          if (showsActiveDot)
            Positioned(
              right: -1,
              bottom: -1,
              child: Container(
                width: 11,
                height: 11,
                decoration: BoxDecoration(
                  color: book.lime,
                  shape: BoxShape.circle,
                  border: Border.all(color: book.surface, width: 2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

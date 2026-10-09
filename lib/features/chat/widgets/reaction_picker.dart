import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';

import 'package:mostro/core/order_book_palette.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/widgets/mostro_modal.dart';

/// Every emoji, for a reaction the quick ones in the message's menu do not
/// offer («…»). Resolves to the emoji picked, or null when dismissed.
Future<String?> showReactionPicker(BuildContext context) {
  return showMostroSheet<String>(
    context: context,
    builder: (sheetContext) => MostroSheet(
      title: AppLocalizations.of(sheetContext).moreReactions,
      content: const _AllEmojis(),
    ),
  );
}

class _AllEmojis extends StatelessWidget {
  const _AllEmojis();

  /// Smallest cell an emoji gets (DS-CMP-6).
  static const double _cell = 48;

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    return LayoutBuilder(
      builder: (context, constraints) => EmojiPicker(
        onEmojiSelected: (_, emoji) => Navigator.of(context).pop(emoji.emoji),
        config: Config(
          height: 320,
          emojiViewConfig: EmojiViewConfig(
            // As many 48-dp cells as the width holds: seven on most phones
            // held upright, five on a 320-dp screen.
            columns: (constraints.maxWidth / _cell).floor().clamp(1, 12),
            emojiSizeMax: 28,
            backgroundColor: book.surface,
          ),
          // No recents tab: it would keep the user's emojis on the device,
          // past a change of identity.
          categoryViewConfig: CategoryViewConfig(
            initCategory: Category.SMILEYS,
            recentTabBehavior: RecentTabBehavior.NONE,
            backgroundColor: book.surface,
            indicatorColor: book.limeText,
            iconColor: book.textMuted,
            iconColorSelected: book.limeText,
            dividerColor: book.border,
          ),
          // Search would need its own words in every language; the
          // categories reach every emoji.
          bottomActionBarConfig: const BottomActionBarConfig(enabled: false),
          skinToneConfig: SkinToneConfig(
            dialogBackgroundColor: book.surface,
            indicatorColor: book.textMuted,
          ),
        ),
      ),
    );
  }
}

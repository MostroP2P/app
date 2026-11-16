import 'package:flutter/material.dart';

import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/utils/insert_at_cursor.dart';
import 'package:mostro/shared/widgets/emoji_sheet.dart';

/// Emoji button of a chat composer: opens every emoji and puts the one
/// picked where the user is typing in [controller], then gives [focusNode]
/// the focus back so typing goes on. Not every keyboard shows an emoji key,
/// so the app offers its own (#938).
class ComposerEmojiButton extends StatelessWidget {
  const ComposerEmojiButton({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.color,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final Color color;

  Future<void> _pick(BuildContext context) async {
    final emoji = await showEmojiSheet(
      context,
      title: AppLocalizations.of(context).insertEmoji,
    );
    if (emoji == null) return;
    controller.value = insertAtCursor(controller.value, emoji);
    focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 36,
      height: 36,
      child: IconButton(
        icon: Icon(Icons.emoji_emotions_outlined, color: color),
        onPressed: () => _pick(context),
        tooltip: AppLocalizations.of(context).insertEmoji,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
      ),
    );
  }
}

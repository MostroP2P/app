import 'package:flutter/material.dart';

import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/widgets/emoji_sheet.dart';

/// Every emoji, for a reaction the quick ones in the message's menu do not
/// offer («…»). Resolves to the emoji picked, or null when dismissed.
Future<String?> showReactionPicker(BuildContext context) =>
    showEmojiSheet(context, title: AppLocalizations.of(context).moreReactions);

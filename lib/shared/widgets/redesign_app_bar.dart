import 'package:flutter/material.dart';

import 'package:mostro/core/automation/automation_id.dart';
import 'package:mostro/core/automation/automation_ids.dart';
import 'package:mostro/core/order_book_palette.dart';

/// Side padding every redesigned screen uses, and the right inset of the app
/// bar's actions so they line up with the content below.
const double redesignSidePadding = 18;

/// The app bar of the redesign: back arrow, a 15/600 sentence-case title in
/// place of the Material 24px one, and actions flush right.
///
/// One implementation for every redesigned screen — the order detail and take
/// order screens (handoffs 6a/7a) and the settings screens (10a–10e) — so the
/// title metrics cannot drift between them.
///
/// [actions] are placed verbatim, so each screen sets its own right inset to
/// [redesignSidePadding]: how much of that an action already carries depends
/// on whether it is an `IconButton`, which pads itself by 8, or a bare
/// widget, which pads by nothing.
///
/// A null [onBack] drops the arrow — a terminal step with nowhere to go back
/// to (backup 16d) — and the title moves to the side padding.
PreferredSizeWidget redesignAppBar(
  BuildContext context, {
  required String title,
  required VoidCallback? onBack,
  List<Widget> actions = const [],
}) {
  final book = OrderBookPalette.of(context);
  return AppBar(
    backgroundColor: book.bg,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    automaticallyImplyLeading: false,
    leading:
        onBack == null
            ? null
            : IconButton(
              icon: Icon(Icons.arrow_back, size: 22, color: book.textBody),
              tooltip: MaterialLocalizations.of(context).backButtonTooltip,
              onPressed: onBack,
            ).withAutomationId(AutomationIds.appBarBack),
    titleSpacing: onBack == null ? redesignSidePadding : 0,
    title: Text(
      title,
      style: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.3,
        color: book.textPrimary,
      ),
    ),
    actions: actions.isEmpty ? null : actions,
  );
}

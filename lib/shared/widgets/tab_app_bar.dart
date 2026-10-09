import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:mostro/core/app_theme.dart' show AppFonts;
import 'package:mostro/core/automation/automation_id.dart';
import 'package:mostro/core/automation/automation_ids.dart';
import 'package:mostro/core/order_book_palette.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/mascot/header_mascot.dart';
import 'package:mostro/shared/widgets/notification_bell.dart';

/// App bar of every tab root (DS-CMP-12): menu, the Mostro mascot, bell.
///
/// The order book (handoff 4b) and the trades and chat tabs (handoff 11) used
/// to disagree in the centre, the mascot in one and `Mostro` in text in the
/// others, so the bar changed every time the user switched tabs (#770). The
/// name of each screen lives in the header below it; the centre only says
/// which app this is, and the mascot says it with a mood.
class TabAppBar extends StatelessWidget {
  const TabAppBar({super.key, required this.onMenuTap, this.waiting = false});

  /// Null on desktop, where the persistent sidebar replaces the drawer.
  final VoidCallback? onMenuTap;

  /// Whether the tab is waiting on something slow; see [HeaderMascot.waiting].
  final bool waiting;

  /// Material's minimum touch target (DS-CMP-6).
  static const double _target = 48;
  static const double _glyph = 22;

  /// Space between a 48-dp target and its glyph, taken out of the mock's
  /// paddings so the glyphs, not the targets, sit where it puts them.
  static const double _glyphInset = (_target - _glyph) / 2;
  static const double _side = 18;

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    // The mock's 44 includes the status bar; below a taller one keep 12.
    final top = math.max(44.0, MediaQuery.paddingOf(context).top + 12);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        _side - _glyphInset,
        top - _glyphInset,
        _side - _glyphInset,
        math.max(0, 12 - _glyphInset),
      ),
      child: SizedBox(
        height: _target,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // The artwork is decorative and its tap an easter egg, so the
            // node says what the text it replaced said, and nothing more.
            Semantics(
              label: AppLocalizations.of(context).appName,
              child: HeaderMascot(waiting: waiting),
            ),
            Row(
              children: [
                if (onMenuTap != null)
                  IconButton(
                    onPressed: onMenuTap,
                    style: IconButton.styleFrom(
                      minimumSize: const Size.square(_target),
                      padding: const EdgeInsets.all(_glyphInset),
                    ),
                    iconSize: _glyph,
                    icon: Icon(Icons.menu_rounded, color: book.textBody),
                    tooltip: AppLocalizations.of(context).menuTooltip,
                  ).withAutomationId(AutomationIds.appBarDrawer),
                const Spacer(),
                NotificationBell(
                  iconColor: book.textBody,
                  iconSize: _glyph,
                  dotColor: book.notif,
                  dotRingColor: book.bg,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// `REQUIEREN TU ACCIÓN  2`: a group title and how many rows it holds, so
/// the user need not scroll into a group to know whether it has anything.
class GroupHeader extends StatelessWidget {
  const GroupHeader({
    super.key,
    required this.title,
    required this.count,
    required this.color,
  });

  final String title;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 4, 2, 0),
      child: Row(
        children: [
          Flexible(
            child: Text(
              title.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 1,
                color: color,
              ),
            ),
          ),
          const SizedBox(width: 7),
          Text(
            '$count',
            style: TextStyle(
              fontFamily: 'Manrope',
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// A lime counter pill: unread messages, pending disputes.
class CountBadge extends StatelessWidget {
  const CountBadge({
    super.key,
    required this.count,
    required this.background,
    required this.foreground,
    this.size = 18,
    this.padding = 5,
  });

  final int count;
  final Color background;
  final Color foreground;
  final double size;

  /// Horizontal padding around the count. A badge small enough that one
  /// digit plus the default would outgrow [size] passes less, to stay round.
  final double padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(minWidth: size),
      height: size,
      padding: EdgeInsets.symmetric(horizontal: padding),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        style: TextStyle(
          fontFamily: AppFonts.figures,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          height: 1,
          color: foreground,
        ),
      ),
    );
  }
}

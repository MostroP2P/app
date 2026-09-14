import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:mostro/core/automation/automation_id.dart';
import 'package:mostro/core/automation/automation_ids.dart';
import 'package:mostro/core/order_book_palette.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/widgets/notification_bell.dart';

/// App bar of the trades and chat tabs (handoff 11): menu, `Mostro` in text,
/// bell. The name of the screen lives in the header below it, so the centre
/// only says which app this is.
class TabAppBar extends StatelessWidget {
  const TabAppBar({super.key, required this.onMenuTap});

  /// Null on desktop, where the persistent sidebar replaces the drawer.
  final VoidCallback? onMenuTap;

  static const double _target = 48;
  static const double _glyph = 20;
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
            Text(
              AppLocalizations.of(context).appName,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
                color: book.textPrimary,
              ),
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
                  dotColor: book.lime,
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
  });

  final int count;
  final Color background;
  final Color foreground;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(minWidth: size),
      height: size,
      padding: const EdgeInsets.symmetric(horizontal: 5),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        style: TextStyle(
          fontFamily: 'Manrope',
          fontSize: 10,
          fontWeight: FontWeight.w700,
          height: 1,
          color: foreground,
        ),
      ),
    );
  }
}

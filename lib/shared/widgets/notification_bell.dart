import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:mostro/core/app_routes.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/account/providers/backup_reminder_provider.dart';
import 'package:mostro/features/notifications/providers/notifications_provider.dart';
import 'package:mostro/l10n/app_localizations.dart';

/// App-bar notification bell.
///
/// Two visual states:
///   1. **Red dot** — backup reminder is active (no number shown).
///   2. **Gold pill badge** — backup done; shows unread notification count.
///
/// A left-right shake animation plays whenever any indicator is active.
///
/// The optional styling lets a redesigned screen match its mock (the order
/// book sets a 22-dp glyph and a ringed dot); screens that pass nothing keep
/// the original look.
class NotificationBell extends ConsumerStatefulWidget {
  const NotificationBell({
    super.key,
    this.iconColor,
    this.iconSize = 24,
    this.dotColor,
    this.dotRingColor,
  });

  /// Glyph colour; the ambient icon theme when null.
  final Color? iconColor;
  final double iconSize;

  /// Backup-reminder dot colour; the theme's destructive red when null.
  final Color? dotColor;

  /// When set, the dot is drawn 7 dp with a 1.5-dp ring of this colour — the
  /// page background — so it reads as cut out of the glyph.
  final Color? dotRingColor;

  @override
  ConsumerState<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends ConsumerState<NotificationBell>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shakeController;
  late final Animation<double> _shakeAnimation;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    _shakeAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: -6.0), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -6.0, end: 6.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 6.0, end: -6.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -6.0, end: 6.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 6.0, end: 0.0), weight: 1),
    ]).animate(CurvedAnimation(
      parent: _shakeController,
      curve: Curves.easeInOut,
    ),);
  }

  @override
  void dispose() {
    _shakeController.dispose();
    super.dispose();
  }

  void _triggerShake() {
    _shakeController.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final backupActive = ref.watch(backupReminderProvider);
    final unreadCount = ref.watch(unreadNotificationCountProvider);

    final isActive = backupActive || unreadCount > 0;

    // Trigger shake whenever the indicator becomes active.
    ref.listen<bool>(backupReminderProvider, (prev, next) {
      if (next) _triggerShake();
    });
    ref.listen<int>(unreadNotificationCountProvider, (prev, next) {
      if (next > (prev ?? 0)) _triggerShake();
    });

    final l10n = AppLocalizations.of(context);
    final semanticLabel = !isActive
        ? l10n.notificationsBellNoUnread
        : backupActive
            ? l10n.notificationsBellBackupActive
            : l10n.notificationsBellUnread(unreadCount);

    return Semantics(
      label: semanticLabel,
      button: true,
      child: IconButton(
        tooltip: semanticLabel,
        onPressed: () => context.push(AppRoute.notifications),
        icon: AnimatedBuilder(
          animation: _shakeAnimation,
          builder: (context, child) => Transform.translate(
            offset: Offset(_shakeAnimation.value, 0),
            child: child,
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(
                Icons.notifications_outlined,
                size: widget.iconSize,
                color: widget.iconColor,
              ),
              if (isActive)
                Positioned(
                  top: -2,
                  right: -2,
                  child: backupActive
                      ? _RedDot(
                          color: widget.dotColor,
                          ringColor: widget.dotRingColor,
                        )
                      : _CountBadge(count: unreadCount),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RedDot extends StatelessWidget {
  const _RedDot({this.color, this.ringColor});

  final Color? color;
  final Color? ringColor;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>();
    final ringColor = this.ringColor;
    final size = ringColor == null ? 8.0 : 7 + 2 * 1.5;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color ?? colors?.destructiveRed ?? const Color(0xFFD84D4D),
        shape: BoxShape.circle,
        border:
            ringColor == null ? null : Border.all(color: ringColor, width: 1.5),
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>();
    final label = count > 99 ? '99+' : '$count';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: colors?.badgeGold ?? const Color(0xFFB8860B),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.bold,
          height: 1,
        ),
      ),
    );
  }
}

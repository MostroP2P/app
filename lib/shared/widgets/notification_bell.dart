import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:mostro/core/app_routes.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/account/providers/backup_reminder_provider.dart';
import 'package:mostro/features/notifications/providers/notifications_provider.dart';

/// App-bar notification bell.
///
/// Two visual states:
///   1. **Red dot** — backup reminder is active (no number shown).
///   2. **Gold pill badge** — backup done; shows unread notification count.
///
/// A left-right shake animation plays whenever any indicator is active.
class NotificationBell extends ConsumerStatefulWidget {
  const NotificationBell({super.key});

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

    final semanticLabel = !isActive
        ? 'Notifications, no unread notifications'
        : backupActive
            ? 'Notifications, backup reminder active'
            : 'Notifications, $unreadCount unread';

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
              const Icon(Icons.notifications_outlined, size: 24),
              if (isActive)
                Positioned(
                  top: -2,
                  right: -2,
                  child: backupActive
                      ? const _RedDot()
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
  const _RedDot();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>();
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: colors?.destructiveRed ?? const Color(0xFFD84D4D),
        shape: BoxShape.circle,
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

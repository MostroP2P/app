import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:mostro/core/app_routes.dart';
import 'package:mostro/core/order_book_palette.dart';
import 'package:mostro/core/settings_palette.dart';
import 'package:mostro/features/settings/providers/notification_permission_provider.dart';
import 'package:mostro/features/settings/providers/notification_prefs_provider.dart';
import 'package:mostro/features/settings/widgets/settings_section.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/widgets/redesign_app_bar.dart';

/// Push notifications — handoff 10d.
///
/// One group card with four rows: 13/600 titles (the old 17px forced
/// `Actualizaciones de operaciones` onto two lines), an 11/400 description,
/// and the glyph centred on the text block rather than on its first line.
class NotificationSettingsScreen extends ConsumerWidget {
  const NotificationSettingsScreen({super.key});

  /// The rows, in the handoff's order, with the icon each carries.
  static const _rows = <(NotificationEvent, IconData)>[
    (NotificationEvent.tradeUpdates, Icons.swap_horiz),
    (NotificationEvent.newMessages, Icons.chat_bubble_outline),
    (NotificationEvent.paymentAlerts, Icons.bolt),
    (NotificationEvent.disputeUpdates, Icons.gavel_outlined),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final book = OrderBookPalette.of(context);
    final prefs = ref.watch(notificationPrefsProvider);
    // Unknown reads as granted: a banner that appears while the answer is
    // still loading would flash on every visit.
    final denied =
        ref.watch(notificationPermissionDeniedProvider).valueOrNull ?? false;

    return Scaffold(
      backgroundColor: book.bg,
      appBar: redesignAppBar(
        context,
        title: l10n.pushNotificationsSettingTitle,
        onBack:
            () =>
                context.canPop()
                    ? context.pop()
                    : context.go(AppRoute.settings),
      ),
      body: ListView(
        // #267: add the bottom system-bar inset so the last item isn't hidden
        // behind the gesture / 3-button navigation bar.
        padding: EdgeInsets.fromLTRB(
          redesignSidePadding,
          6,
          redesignSidePadding,
          14 + MediaQuery.of(context).viewPadding.bottom,
        ),
        children: [
          if (denied) ...[
            const _SystemDeniedBanner(),
            const SizedBox(height: 14),
          ],
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 0, 2, 14),
            child: Text(
              l10n.chooseNotificationEventsSubtitle,
              style: TextStyle(
                fontSize: 12,
                height: 1.5,
                color: book.textSecondary,
              ),
            ),
          ),
          // With the system permission denied the rows change nothing the
          // user can see, so they fade and stop taking taps; the banner above
          // is the only thing left to act on.
          Opacity(
            opacity: denied ? 0.55 : 1,
            child: SettingsGroup(
              rows: [
                for (final (event, icon) in _rows)
                  _EventRow(
                    event: event,
                    icon: icon,
                    value: prefs.isEnabled(event),
                    enabled: !denied,
                  ),
              ],
            ),
          ),
          const SizedBox(height: settingsGroupGap),
          SettingsFootnote(
            icon: Icons.lock_outline,
            // Relevant in a privacy app: pushes travel through Google/Apple.
            text: l10n.notificationsPrivacyFootnote,
          ),
        ],
      ),
    );
  }
}

class _EventRow extends ConsumerWidget {
  const _EventRow({
    required this.event,
    required this.icon,
    required this.value,
    required this.enabled,
  });

  final NotificationEvent event;
  final IconData icon;
  final bool value;
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final book = OrderBookPalette.of(context);
    final (title, description) = _copy(l10n, event);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      child: Row(
        // Centred on the whole text block, not its first line: at two lines
        // the v2 icon sat halfway up the title.
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 17,
            color: value ? book.limeIcon : book.textTertiary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: book.textStrong,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.4,
                    color: book.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          MostroToggle(
            value: value,
            semanticLabel: title,
            onChanged: enabled ? (next) => _set(context, ref, next) : null,
          ),
        ],
      ),
    );
  }

  Future<void> _set(BuildContext context, WidgetRef ref, bool next) async {
    final ok = await ref
        .read(notificationPrefsProvider.notifier)
        .setEvent(event, next);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context).notificationPrefSaveFailed,
          ),
        ),
      );
    }
  }

  static (String, String) _copy(
    AppLocalizations l10n,
    NotificationEvent event,
  ) => switch (event) {
    NotificationEvent.tradeUpdates => (
      l10n.notifTradeUpdatesTitle,
      l10n.notifTradeUpdatesSubtitle,
    ),
    NotificationEvent.newMessages => (
      l10n.notifNewMessagesTitle,
      l10n.notifNewMessagesSubtitle,
    ),
    NotificationEvent.paymentAlerts => (
      l10n.notifPaymentAlertsTitle,
      l10n.notifPaymentAlertsSubtitle,
    ),
    NotificationEvent.disputeUpdates => (
      l10n.notifDisputeUpdatesTitle,
      l10n.notifDisputeUpdatesSubtitle,
    ),
  };
}

// ── Denied-permission banner ──────────────────────────────────────────────────

/// Shown when the OS is refusing this app's notifications: the four toggles
/// below cannot deliver anything until this is fixed, and it is not fixed
/// from here.
class _SystemDeniedBanner extends ConsumerWidget {
  const _SystemDeniedBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final pal = SettingsPalette.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: pal.warnBg,
        borderRadius: const BorderRadius.all(Radius.circular(14)),
        border: Border.all(color: pal.warnBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 4,
          children: [
            Text(
              l10n.notificationsSystemDenied,
              style: TextStyle(fontSize: 11, height: 1.4, color: pal.warnInk),
            ),
            InkWell(
              onTap: () async {
                await ref.read(openSystemSettingsProvider)();
                // The answer can only have changed while the user was away.
                ref.invalidate(notificationPermissionDeniedProvider);
              },
              child: Text(
                l10n.openSystemSettingsAction,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: pal.warnInk,
                  decoration: TextDecoration.underline,
                  decorationColor: pal.warnInk,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

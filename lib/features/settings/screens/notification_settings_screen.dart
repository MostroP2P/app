import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:mostro/core/app_routes.dart';
import 'package:mostro/core/order_book_palette.dart';
import 'package:mostro/core/settings_palette.dart';
import 'package:mostro/features/settings/models/push_status_line.dart';
import 'package:mostro/features/settings/providers/notification_permission_provider.dart';
import 'package:mostro/features/settings/providers/notification_prefs_provider.dart';
import 'package:mostro/features/settings/providers/push_settings_provider.dart';
import 'package:mostro/features/settings/widgets/settings_section.dart';
import 'package:mostro/features/trades/models/trades_list_rules.dart'
    show relativeTime;
import 'package:mostro/features/trades/widgets/trade_card.dart'
    show relativeTimeLabel;
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/widgets/redesign_app_bar.dart';

/// Push notifications — handoff 10d.
///
/// A master card on top — the push toggle and what Rust reports about the
/// registration, or an info row where the platform cannot push — then one
/// group card with the four event rows: 13/600 titles (the old 17px forced
/// `Actualizaciones de operaciones` onto two lines), an 11/400 description,
/// and the glyph centred on the text block rather than on its first line.
///
/// The event rows gate the in-app cards, not the push: a push carries no
/// type to filter on (docs/PUSH_NOTIFICATIONS.md §9.1).
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
    // Capability first (§9.1): a denied permission on a phone keeps its
    // banner and its toggle, never unsupported copy.
    final supported = ref.watch(pushSupportedProvider);

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
          SettingsGroup(
            rows: [
              if (supported)
                const _PushMasterRow()
              else
                const _UnsupportedPlatformRow(),
            ],
          ),
          const SizedBox(height: settingsGroupGap),
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

// ── Master push toggle ────────────────────────────────────────────────────────

/// The push toggle, with the registration status Rust reports under it.
///
/// Stays enabled while the system permission is denied: turning push off is
/// still meaningful then — it unregisters every trade from the server.
class _PushMasterRow extends ConsumerStatefulWidget {
  const _PushMasterRow();

  @override
  ConsumerState<_PushMasterRow> createState() => _PushMasterRowState();
}

class _PushMasterRowState extends ConsumerState<_PushMasterRow> {
  /// The value the user just chose, shown until Rust's status agrees.
  bool? _pending;

  /// A toggle round trip is running; a second tap would race it.
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final book = OrderBookPalette.of(context);
    final pal = SettingsPalette.of(context);
    final status = ref.watch(pushStatusProvider).valueOrNull;
    final activeTarget = ref.watch(pushTogglePendingProvider);
    ref.listen(pushStatusProvider, (_, next) {
      if (!_busy && _pending != null && next.valueOrNull?.enabled == _pending) {
        setState(() => _pending = null);
      }
    });
    // Unknown reads as on, the persisted default (§8.1).
    final value = activeTarget ?? _pending ?? status?.enabled ?? true;
    // No line while a change is on its way: the old status would contradict
    // the toggle the user just flipped.
    final line =
        status == null || _pending != null || activeTarget != null
            ? null
            : pushStatusLine(status, now: clock.now());
    final title = l10n.pushMasterToggleTitle;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(
            value
                ? Icons.notifications_active_outlined
                : Icons.notifications_off_outlined,
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
                  l10n.pushMasterToggleSubtitle,
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.4,
                    color: book.textSecondary,
                  ),
                ),
                if (line != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    _lineCopy(context, l10n, line),
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.4,
                      fontWeight:
                          line.isWarning ? FontWeight.w600 : FontWeight.w400,
                      color: line.isWarning ? pal.warnInk : book.textTertiary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          MostroToggle(
            value: value,
            semanticLabel: title,
            onChanged: _busy || activeTarget != null ? null : _set,
          ),
        ],
      ),
    );
  }

  Future<void> _set(bool next) async {
    setState(() {
      _pending = next;
      _busy = true;
    });
    final ok = await ref.read(pushToggleProvider).set(next);
    if (!mounted) return;
    setState(() {
      _busy = false;
      // Failed: nothing changed, so the toggle goes back. Succeeded and the
      // status already agrees: nothing left to wait for.
      if (!ok || ref.read(pushStatusProvider).valueOrNull?.enabled == next) {
        _pending = null;
      }
    });
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).pushToggleSaveFailed),
        ),
      );
    }
  }

  static String _lineCopy(
    BuildContext context,
    AppLocalizations l10n,
    PushStatusLine line,
  ) => switch (line.kind) {
    PushStatusLineKind.off => l10n.pushStatusOff,
    PushStatusLineKind.cleanupPending => l10n.pushStatusCleanupPending(
      line.count,
    ),
    PushStatusLineKind.refused => l10n.pushStatusNodeRefused,
    PushStatusLineKind.noToken => l10n.pushStatusNoToken,
    PushStatusLineKind.unreachable => l10n.pushStatusUnreachable,
    PushStatusLineKind.rateLimited => l10n.pushStatusRateLimited,
    PushStatusLineKind.idle => l10n.pushStatusIdle,
    PushStatusLineKind.registered => [
      l10n.pushStatusRegistered(line.count),
      if (line.lastSuccessAt case final at?)
        l10n.pushStatusLastRegistered(
          relativeTimeLabel(
            relativeTime(at.toLocal(), now: clock.now()),
            l10n,
            Localizations.localeOf(context).toString(),
          ),
        ),
    ].join(' · '),
  };
}

/// Where no push can arrive (desktop; web until the server accepts it) the
/// toggle would promise something the platform cannot do.
class _UnsupportedPlatformRow extends StatelessWidget {
  const _UnsupportedPlatformRow();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final book = OrderBookPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      child: Row(
        children: [
          Icon(
            Icons.notifications_off_outlined,
            size: 17,
            color: book.textTertiary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              l10n.pushUnsupportedPlatform,
              style: TextStyle(
                fontSize: 12,
                height: 1.4,
                color: book.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Event rows ────────────────────────────────────────────────────────────────

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
              // `notificationPermissionDeniedProvider` re-reads the answer
              // when the app resumes, which is when the user comes back.
              onTap: () => ref.read(openSystemSettingsProvider)(),
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

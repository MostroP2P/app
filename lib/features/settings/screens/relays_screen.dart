import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:mostro/core/app_routes.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/core/automation/automation_id.dart';
import 'package:mostro/core/automation/automation_ids.dart';
import 'package:mostro/core/settings_palette.dart';
import 'package:mostro/core/test_environment.dart';
import 'package:mostro/features/settings/models/settings_rows.dart';
import 'package:mostro/features/settings/providers/relays_provider.dart';
import 'package:mostro/features/settings/widgets/settings_section.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/widgets/dashed_border.dart';
import 'package:mostro/shared/widgets/redesign_app_bar.dart';
import 'package:mostro/src/rust/api/types.dart' show RelayInfo;

/// Relays — handoff 10b.
///
/// Out of the settings accordion and onto its own screen, because the state
/// that matters is per relay: the v2 card showed a green dot even on the ones
/// that were down. A summary card says what the tally means for the user, and
/// each row carries its own dot, status line and toggle.
class RelaysScreen extends ConsumerWidget {
  const RelaysScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final book = OrderBookPalette.of(context);
    final relays = ref.watch(relaysProvider);
    final tally = RelayTally.of(relays);

    return Scaffold(
      backgroundColor: book.bg,
      appBar: redesignAppBar(
        context,
        title: l10n.relaysSettingTitle,
        onBack:
            () =>
                context.canPop()
                    ? context.pop()
                    : context.go(AppRoute.settings),
      ),
      body: ListView(
        // #267: bottom system-bar inset so the add-relay button clears the
        // gesture / 3-button navigation bar.
        padding: EdgeInsets.fromLTRB(
          redesignSidePadding,
          6,
          redesignSidePadding,
          14 + MediaQuery.of(context).viewPadding.bottom,
        ),
        children: [
          _SummaryCard(tally: tally),
          const SizedBox(height: settingsGroupGap),
          SettingsGroup(
            rows: [
              for (final relay in relays)
                _RelayRow(
                  key: ValueKey(canonicalRelayUrl(relay.url)),
                  relay: relay,
                ),
            ],
          ),
          const SizedBox(height: 12),
          _AddRelayButton(
            onTap: () => _showAddRelayDialog(context, ref, relays),
          ),
          const SizedBox(height: settingsGroupGap),
          SettingsFootnote(icon: Icons.info_outline, text: l10n.relaysFootnote),
        ],
      ),
    );
  }

  Future<void> _showAddRelayDialog(
    BuildContext context,
    WidgetRef ref,
    List<RelayInfo> relays,
  ) async {
    final controller = TextEditingController();
    String? errorText;

    final url = await showDialog<String>(
      context: context,
      builder:
          (ctx) => StatefulBuilder(
            builder: (ctx, setDialogState) {
              final l10n = AppLocalizations.of(ctx);
              return AlertDialog(
                title: Text(l10n.addRelayDialogTitle),
                content: TextField(
                  controller: controller,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    hintText: l10n.relayHintText,
                    errorText: errorText,
                  ),
                  onChanged: (_) {
                    if (errorText != null) {
                      setDialogState(() => errorText = null);
                    }
                  },
                ).withAutomationId(AutomationIds.settingsRelaysAddUrl),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: Text(l10n.cancel),
                  ).withAutomationId(AutomationIds.settingsRelaysAddCancel),
                  TextButton(
                    onPressed: () {
                      // Canonicalized before anything else looks at it: a relay
                      // written with and without a trailing slash is the same
                      // relay, and two rows for it would share one automation
                      // identifier, which no driver could then tell apart.
                      final candidate = canonicalRelayUrl(controller.text);
                      final error = _validateRelayUrl(candidate, relays, l10n);
                      if (error != null) {
                        setDialogState(() => errorText = error);
                        return;
                      }
                      Navigator.of(ctx).pop(candidate);
                    },
                    child: Text(l10n.addButtonLabel),
                  ).withAutomationId(AutomationIds.settingsRelaysAddConfirm),
                ],
              );
            },
          ),
    );

    controller.dispose();
    if (url == null || !context.mounted) return;
    final ok = await ref.read(relaysProvider.notifier).add(url);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).relayAddFailed)),
      );
    }
  }

  /// The add-relay rules, in one place: scheme, length, and no duplicate.
  static String? _validateRelayUrl(
    String url,
    List<RelayInfo> relays,
    AppLocalizations l10n,
  ) {
    // A Mortsom run points the app at a local relay, which is plain ws:// on
    // a private address. Outside the test environment the wss:// requirement
    // is unchanged.
    final schemeOk =
        url.startsWith('wss://') ||
        (TestEnvironment.allowInsecureRelays && url.startsWith('ws://'));
    if (!schemeOk) return l10n.relayErrorMustStartWithWss;
    if (url.length < 10) return l10n.relayErrorUrlTooShort;
    if (relays.any((r) => canonicalRelayUrl(r.url) == url)) {
      return l10n.relayErrorDuplicate;
    }
    return null;
  }
}

// ── Summary card ──────────────────────────────────────────────────────────────

/// `3 de 4 conectados` and what that means: the tally alone does not tell the
/// user whether they can still trade.
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.tally});

  final RelayTally tally;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final book = OrderBookPalette.of(context);
    final pal = SettingsPalette.of(context);
    final healthy = !tally.isCritical;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: book.surface,
        borderRadius: const BorderRadius.all(Radius.circular(18)),
        border: Border.all(
          color:
              tally.allConnected ? pal.summaryOkBorder : pal.summaryWarnBorder,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: pal.discBg,
                shape: BoxShape.circle,
                border: Border.all(color: pal.discBorder),
              ),
              child: Icon(
                Icons.router_outlined,
                size: 16,
                color: pal.dotOnline,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.relaysConnectedOfTotal(tally.connected, tally.total),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: book.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    healthy
                        ? l10n.relaysSummaryHealthy
                        : l10n.relaysSummaryAtRisk,
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.4,
                      color: healthy ? book.textSecondary : pal.warnInk,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Relay row ─────────────────────────────────────────────────────────────────

class _RelayRow extends ConsumerWidget {
  const _RelayRow({super.key, required this.relay});

  final RelayInfo relay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final book = OrderBookPalette.of(context);
    final pal = SettingsPalette.of(context);
    final health = relayHealth(relay);
    final (dot, status, statusColor) = switch (health) {
      RelayHealth.connected => (
        pal.dotOnline,
        l10n.relayStatusConnected,
        book.textSecondary,
      ),
      // Unreachable until the connection manager publishes latency; kept so
      // adding it is a change to `relayHealth` alone.
      RelayHealth.slow => (pal.dotSlow, l10n.relayStatusConnected, pal.warnInk),
      RelayHealth.offline => (
        pal.dotOffline,
        l10n.relayStatusOffline,
        book.textTertiary,
      ),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      child: Row(
        children: [
          // The dot and label crossfade as the connection changes; the row
          // never moves, because reordering under the finger makes the user
          // toggle the wrong relay.
          AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  // The scheme is the same on every row and eats the width
                  // the host needs; the full URL stays in the semantics.
                  relayDisplayUrl(relay.url),
                  style: TextStyle(
                    fontFamily: AppFonts.figures,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color:
                        health == RelayHealth.connected
                            ? book.textStrong
                            : book.textSecondary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 150),
                  style: TextStyle(fontSize: 10, color: statusColor),
                  child: Text(status),
                ),
              ],
            ),
          ),
          const SizedBox(width: 11),
          MostroToggle(
            value: relay.isActive,
            semanticLabel:
                relay.isActive
                    ? l10n.disableRelayLabel(relay.url)
                    : l10n.enableRelayLabel(relay.url),
            onChanged: (value) => _toggle(context, ref, value),
          ),
          if (!relay.isDefault)
            IconButton(
              icon: Icon(Icons.delete_outline, size: 18, color: pal.danger),
              tooltip: l10n.removeRelayTooltip,
              onPressed: () => _remove(context, ref),
            ).withAutomationId(AutomationIds.settingsRelayDelete(relay.url)),
        ],
      ),
    ).withAutomationId(
      AutomationIds.settingsRelayItem(relay.url),
      // The row holds a toggle and, for user-added relays, a delete button,
      // so merge: false keeps those addressable on their own.
      merge: false,
      label: relay.url,
    );
  }

  Future<void> _toggle(BuildContext context, WidgetRef ref, bool value) async {
    final notifier = ref.read(relaysProvider.notifier);
    // Only the step that would leave the user with nothing asks first —
    // every other toggle is reversible from the same row.
    if (!value && RelayTally.of(ref.read(relaysProvider)).total <= 1) {
      final confirmed = await _confirmLastRelay(context);
      if (confirmed != true) return;
    }
    final ok = await notifier.setActive(relay.url, value);
    if (!ok && context.mounted) {
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(value ? l10n.relayAddFailed : l10n.relayRemoveFailed),
        ),
      );
    }
  }

  Future<bool?> _confirmLastRelay(BuildContext context) =>
      showModalBottomSheet<bool>(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (ctx) => _LastRelaySheet(),
      );

  Future<void> _remove(BuildContext context, WidgetRef ref) async {
    final ok = await ref.read(relaysProvider.notifier).remove(relay.url);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).relayRemoveFailed)),
      );
    }
  }
}

/// Asked only when disabling the relay would leave none active.
class _LastRelaySheet extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final book = OrderBookPalette.of(context);
    final pal = SettingsPalette.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(redesignSidePadding),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: book.surface,
            borderRadius: const BorderRadius.all(Radius.circular(18)),
            border: Border.all(color: book.border),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l10n.lastRelayDialogTitle,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: book.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.lastRelayDialogBody,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.5,
                    color: book.textSecondary,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: book.textBody,
                          side: BorderSide(color: pal.buttonBorder),
                          padding: const EdgeInsets.symmetric(vertical: 11),
                          shape: const RoundedRectangleBorder(
                            borderRadius: BorderRadius.all(Radius.circular(14)),
                          ),
                        ),
                        child: Text(l10n.cancel),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: pal.danger,
                          side: BorderSide(color: pal.dangerBorder),
                          padding: const EdgeInsets.symmetric(vertical: 11),
                          shape: const RoundedRectangleBorder(
                            borderRadius: BorderRadius.all(Radius.circular(14)),
                          ),
                        ),
                        child: Text(l10n.disableButtonLabel),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Add relay ─────────────────────────────────────────────────────────────────

/// `+ Agregar relay`: full width, dashed border — the same pattern as
/// `Agregar nodo propio` and the create-order chips.
class _AddRelayButton extends StatelessWidget {
  const _AddRelayButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    final pal = SettingsPalette.of(context);
    return CustomPaint(
      foregroundPainter: DashedBorderPainter(color: pal.dashedBorder),
      child: Material(
        color: pal.dashedFill,
        borderRadius: const BorderRadius.all(Radius.circular(16)),
        child: InkWell(
          onTap: onTap,
          borderRadius: const BorderRadius.all(Radius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.add, size: 14, color: book.limeIcon),
                const SizedBox(width: 6),
                Text(
                  AppLocalizations.of(context).addRelayButtonLabel,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: book.textBody,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ).withAutomationId(AutomationIds.settingsRelaysAdd);
  }
}

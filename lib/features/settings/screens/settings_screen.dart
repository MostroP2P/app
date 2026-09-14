import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:mostro/core/app_routes.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/core/automation/automation_id.dart';
import 'package:mostro/core/automation/automation_ids.dart';
import 'package:mostro/core/settings_palette.dart';
import 'package:mostro/features/about/screens/about_screen.dart'
    show appVersionProvider;
import 'package:mostro/features/settings/models/settings_rows.dart';
import 'package:mostro/features/settings/providers/mostro_nodes_provider.dart';
import 'package:mostro/features/settings/providers/notification_prefs_provider.dart';
import 'package:mostro/features/settings/providers/nwc_provider.dart';
import 'package:mostro/features/settings/providers/relays_provider.dart';
import 'package:mostro/features/settings/providers/settings_provider.dart';
import 'package:mostro/features/settings/widgets/currency_selector_dialog.dart';
import 'package:mostro/features/settings/widgets/escrow_mode_dev_card.dart';
import 'package:mostro/features/settings/widgets/language_selector.dart';
import 'package:mostro/features/settings/widgets/mostro_node_selector.dart';
import 'package:mostro/features/settings/widgets/settings_section.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/widgets/redesign_app_bar.dart';
import 'package:mostro/src/rust/api/types.dart' show MostroNodeEntry;

/// Settings — handoff 10a.
///
/// Four groups instead of nine equal cards, and every row's subtitle replaced
/// by the setting's current value flush right: `Relays · 3 de 4 conectados`
/// rather than `Administrar conexiones de relay`. The value is also the
/// warning — amber when something is unset or degraded — so a relay being
/// down is visible without opening Relays.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final book = OrderBookPalette.of(context);
    final pal = SettingsPalette.of(context);
    final settings = ref.watch(settingsProvider);

    return Scaffold(
      backgroundColor: book.bg,
      appBar: redesignAppBar(
        context,
        title: l10n.settingsScreenTitle,
        onBack:
            () => context.canPop() ? context.pop() : context.go(AppRoute.home),
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
          SettingsGroup(
            header: l10n.settingsGroupApp,
            rows: [
              SettingsRow(
                icon: Icons.language,
                label: l10n.languageSettingTitle,
                value: languageNameForCode(settings.language),
                onTap: () => showLanguageSelector(context),
              ),
              SettingsRow(
                icon: Icons.contrast,
                label: l10n.appearanceSettingTitle,
                value: _themeLabel(l10n, settings.themeMode),
                onTap: () => _showThemeDialog(context, ref),
              ),
              SettingsRow(
                icon: Icons.monetization_on_outlined,
                label: l10n.fiatCurrencySettingTitle,
                value: settings.defaultFiatCode ?? l10n.allCurrencies,
                onTap: () => showCurrencySelector(context),
              ),
              _notificationsRow(context, ref, l10n),
            ],
          ),
          const SizedBox(height: settingsGroupGap),
          SettingsGroup(
            header: l10n.settingsGroupPayments,
            rows: [
              _lightningAddressRow(context, ref, l10n, settings),
              _walletRow(context, ref, l10n),
            ],
          ),
          const SizedBox(height: settingsGroupGap),
          SettingsGroup(
            header: l10n.settingsGroupNetwork,
            rows: [
              SettingsRow(
                icon: Icons.hub_outlined,
                label: l10n.mostroNodeSettingTitle,
                value: _activeNodeName(ref),
                // The visible value is the node's name; the readout carries
                // the full key, which is what automation compares.
                semanticValue: ref.watch(mostroPubkeyProvider),
                valueAutomationId: AutomationIds.settingsMostroNodePubkey,
                onTap: () => showMostroNodeSelector(context),
                // The row holds a tap target plus that readout, so
                // merge: false keeps the readout its own node.
              ).withAutomationId(
                AutomationIds.settingsMostroNode,
                merge: false,
              ),
              _relaysRow(context, ref, l10n),
            ],
          ),
          const SizedBox(height: settingsGroupGap),
          SettingsGroup(
            header: l10n.settingsGroupHelp,
            rows: [
              SettingsRow(
                icon: Icons.description_outlined,
                label: l10n.logReportSettingTitle,
                onTap: () => context.push(AppRoute.logs),
              ),
            ],
          ),
          // Escrow backend override. Debug builds only: forcing a backend the
          // node does not run is a testing affordance, never a user setting.
          // See docs/cashu/README.md §4.3.
          if (kDebugMode) ...[
            const SizedBox(height: settingsGroupGap),
            const EscrowModeDevCard(),
          ],
          // The version is not a setting, so it sits outside the cards. It is
          // here because support asks for it first.
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 14, 2, 0),
            child: Row(
              children: [
                Text(
                  'Mostro',
                  style: TextStyle(fontSize: 11, color: book.textTertiary),
                ),
                const SizedBox(width: 7),
                Text(
                  ref.watch(appVersionProvider).valueOrNull ?? '',
                  style: TextStyle(
                    fontFamily: AppFonts.figures,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: pal.groupHeader,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Rows whose value is derived ──────────────────────────────────────────────

  /// `Notificaciones push → 3 de 4`, amber `Desactivadas` when every event is
  /// off: a push setting that silences everything is a state worth flagging.
  Widget _notificationsRow(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) {
    final prefs = ref.watch(notificationPrefsProvider);
    return SettingsRow(
      icon: Icons.notifications_outlined,
      label: l10n.pushNotificationsSettingTitle,
      value:
          prefs.allDisabled
              ? l10n.notificationsAllOff
              : l10n.notificationsEnabledOfTotal(
                prefs.enabledCount,
                prefs.total,
              ),
      tone:
          prefs.allDisabled
              ? SettingsValueTone.warn
              : SettingsValueTone.neutral,
      onTap: () => context.push(AppRoute.notificationSettings),
    );
  }

  Widget _lightningAddressRow(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
    AppSettingsState settings,
  ) {
    final address = settings.defaultLightningAddress;
    return SettingsRow(
      icon: Icons.bolt,
      label: l10n.lightningAddressSettingTitle,
      value: address ?? l10n.lightningAddressUnset,
      tone:
          address == null ? SettingsValueTone.warn : SettingsValueTone.neutral,
      onTap: () => _showLightningAddressDialog(context, ref),
    );
  }

  Widget _walletRow(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) {
    final wallet = ref.watch(nwcProvider);
    return SettingsRow(
      icon: Icons.account_balance_wallet_outlined,
      label: l10n.nwcWalletSettingTitle,
      value:
          wallet == null
              ? l10n.nwcWalletNotConnected
              : (wallet.walletName ?? l10n.nwcConnectedStatus),
      tone: wallet == null ? SettingsValueTone.warn : SettingsValueTone.neutral,
      onTap:
          () => context.push(
            wallet == null ? AppRoute.connectWallet : AppRoute.walletSettings,
          ),
    ).withAutomationId(AutomationIds.settingsWallet);
  }

  /// `Relays → 3 de 4 conectados`, lime only when every enabled relay is
  /// connected. Relays left the accordion for their own screen (10b), where
  /// the state is per relay.
  Widget _relaysRow(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) {
    final tally = RelayTally.of(ref.watch(relaysProvider));
    return SettingsRow(
      icon: Icons.router_outlined,
      label: l10n.relaysSettingTitle,
      value: l10n.relaysConnectedOfTotal(tally.connected, tally.total),
      tone: tally.tone,
      onTap: () => context.push(AppRoute.relays),
    ).withAutomationId(AutomationIds.settingsRelays);
  }

  String _activeNodeName(WidgetRef ref) {
    final nodes = ref.watch(mostroNodesProvider).valueOrNull;
    for (final node in nodes ?? const <MostroNodeEntry>[]) {
      if (node.isActive && (node.name?.isNotEmpty ?? false)) {
        return nodeDisplayName(node);
      }
    }
    return truncatePubkey(ref.watch(mostroPubkeyProvider));
  }

  // ── Theme dialog ─────────────────────────────────────────────────────────────

  String _themeLabel(AppLocalizations l10n, ThemeMode mode) => switch (mode) {
    ThemeMode.dark => l10n.themeDark,
    ThemeMode.light => l10n.themeLight,
    ThemeMode.system => l10n.themeSystemDefault,
  };

  Future<void> _showThemeDialog(BuildContext context, WidgetRef ref) async {
    final current = ref.read(settingsProvider).themeMode;
    await showDialog<void>(
      context: context,
      builder:
          (ctx) => SimpleDialog(
            title: Text(AppLocalizations.of(ctx).appearanceDialogTitle),
            children:
                ThemeMode.values
                    .map(
                      (mode) => ListTile(
                        title: Text(
                          _themeLabel(AppLocalizations.of(ctx), mode),
                        ),
                        trailing:
                            mode == current ? const Icon(Icons.check) : null,
                        onTap: () {
                          ref
                              .read(settingsProvider.notifier)
                              .setThemeMode(mode);
                          Navigator.of(ctx).pop();
                        },
                      ),
                    )
                    .toList(),
          ),
    );
  }

  // ── Lightning address dialog ─────────────────────────────────────────────────

  Future<void> _showLightningAddressDialog(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final controller = TextEditingController(
      text: ref.read(settingsProvider).defaultLightningAddress ?? '',
    );
    String? errorText;

    await showDialog<void>(
      context: context,
      builder:
          (ctx) => StatefulBuilder(
            builder: (ctx, setDialogState) {
              final l10n = AppLocalizations.of(ctx);
              return AlertDialog(
                title: Text(l10n.lightningAddressDialogTitle),
                content: TextField(
                  controller: controller,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    hintText: l10n.lightningAddressHintText,
                    errorText: errorText,
                  ),
                  onChanged: (_) {
                    if (errorText != null) {
                      setDialogState(() => errorText = null);
                    }
                  },
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      ref
                          .read(settingsProvider.notifier)
                          .setDefaultLightningAddress(null);
                      Navigator.of(ctx).pop();
                    },
                    child: Text(l10n.clearButtonLabel),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: Text(l10n.cancel),
                  ),
                  TextButton(
                    onPressed: () {
                      final input = controller.text.trim();
                      if (input.isEmpty) {
                        ref
                            .read(settingsProvider.notifier)
                            .setDefaultLightningAddress(null);
                        Navigator.of(ctx).pop();
                        return;
                      }
                      final parts = input.split('@');
                      if (parts.length != 2 ||
                          parts[0].isEmpty ||
                          parts[1].isEmpty) {
                        setDialogState(
                          () => errorText = l10n.invalidLightningAddressFormat,
                        );
                        return;
                      }
                      ref
                          .read(settingsProvider.notifier)
                          .setDefaultLightningAddress(input);
                      Navigator.of(ctx).pop();
                    },
                    child: Text(l10n.saveButtonLabel),
                  ),
                ],
              );
            },
          ),
    );

    controller.dispose();
  }
}

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:mostro/features/settings/providers/escrow_mode_provider.dart';
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
import 'package:mostro/shared/widgets/mostro_modal.dart';
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
            // The rows follow the backend the active node settles over, never
            // both: a Cashu node has no invoice step and no bond (bonds are
            // Lightning-only, docs/ANTI_ABUSE_BOND.md), so a Lightning address
            // or an NWC wallet does nothing there, and on a Lightning node
            // there is no mint. A node that has not said yet reads as
            // Lightning, as everywhere else.
            rows: [
              if (ref.watch(isCashuModeProvider)) ...[
                ..._mintRows(context, ref, l10n),
                // The wallet binds to one mint: shown only on a node that
                // pins one. On a node that accepts several, or any, each
                // order names its own, which the wallet cannot follow yet.
                if (ref.watch(isCashuAvailableProvider))
                  SettingsRow(
                    icon: Icons.savings_outlined,
                    label: l10n.cashuWalletTitle,
                    onTap: () => context.push(AppRoute.cashuWallet),
                  ),
              ] else ...[
                _lightningAddressRow(context, ref, l10n, settings),
                _walletRow(context, ref, l10n),
              ],
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
                const SizedBox(width: 8),
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

  /// `Mint → mint.cashu.space`, one row per mint the active node accepts
  /// (MostroP2P/mostro#1047): who may hold the sats while a trade is open.
  /// The maker picks one per order, so the rows inform rather than edit, and
  /// a tap copies the full URL. A node that lists none accepts any mint, and
  /// one row says so.
  List<Widget> _mintRows(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) {
    final urls = ref.watch(escrowModeProvider).valueOrNull?.mintUrls ?? [];
    if (urls.isEmpty) {
      return [
        SettingsRow(
          icon: Icons.account_balance_outlined,
          label: l10n.settingsMintLabel,
          // Nothing to copy or open, so no tap and no chevron.
          value: l10n.cashuAnyMint,
        ),
      ];
    }
    return [
      for (final url in urls)
        SettingsRow(
          icon: Icons.account_balance_outlined,
          label: l10n.settingsMintLabel,
          value: mintDisplayHost(url),
          valueIsData: true,
          semanticValue: url,
          // A copy mark, not the chevron: the row leads nowhere.
          trailing: Icon(
            Icons.copy_rounded,
            size: 14,
            color: SettingsPalette.of(context).dotOffline,
          ),
          onTap: () async {
            final messenger = ScaffoldMessenger.of(context);
            await Clipboard.setData(ClipboardData(text: url));
            messenger.showSnackBar(
              SnackBar(content: Text(l10n.settingsMintCopied)),
            );
          },
        ),
    ];
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
    await showMostroDialog<void>(
      context: context,
      builder:
          (ctx) => MostroDialog(
            title: AppLocalizations.of(ctx).appearanceDialogTitle,
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children:
                  ThemeMode.values
                      .map(
                        (mode) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            _themeLabel(AppLocalizations.of(ctx), mode),
                          ),
                          trailing:
                              mode == current
                                  ? Icon(
                                    Icons.check,
                                    color: OrderBookPalette.of(ctx).lime,
                                  )
                                  : null,
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
          ),
    );
  }

  // ── Lightning address dialog ─────────────────────────────────────────────────

  Future<void> _showLightningAddressDialog(
    BuildContext context,
    WidgetRef ref,
  ) => showMostroDialog<void>(
    context: context,
    builder: (_) => const _LightningAddressDialog(),
  );
}

/// Owns its [TextEditingController] so it is disposed with the dialog's
/// element, not when `showDialog` resolves: that future completes on `pop`,
/// while the TextField is still mounted for the exit animation. Disposing it
/// there crashed the save (red screen, `_dependents.isEmpty`).
class _LightningAddressDialog extends ConsumerStatefulWidget {
  const _LightningAddressDialog();

  @override
  ConsumerState<_LightningAddressDialog> createState() =>
      _LightningAddressDialogState();
}

class _LightningAddressDialogState
    extends ConsumerState<_LightningAddressDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: ref.read(settingsProvider).defaultLightningAddress ?? '',
  );
  String? _errorText;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _saveAndClose(String? address) {
    ref.read(settingsProvider.notifier).setDefaultLightningAddress(address);
    Navigator.of(context).pop();
  }

  void _onSave(AppLocalizations l10n) {
    final input = _controller.text.trim();
    if (input.isEmpty) {
      _saveAndClose(null);
      return;
    }
    final parts = input.split('@');
    if (parts.length != 2 || parts[0].isEmpty || parts[1].isEmpty) {
      setState(() => _errorText = l10n.invalidLightningAddressFormat);
      return;
    }
    _saveAndClose(input);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return MostroDialog(
      title: l10n.lightningAddressDialogTitle,
      content: TextField(
        controller: _controller,
        keyboardType: TextInputType.emailAddress,
        decoration: InputDecoration(
          hintText: l10n.lightningAddressHintText,
          errorText: _errorText,
        ),
        onChanged: (_) {
          if (_errorText != null) setState(() => _errorText = null);
        },
      ),
      // Clearing the saved address is neither the answer nor the way out of
      // this dialog, so it reads as a link rather than a third button.
      links: [
        ModalLink(
          label: l10n.clearButtonLabel,
          onPressed: () => _saveAndClose(null),
        ),
      ],
      secondary: ModalAction(
        label: l10n.cancel,
        onPressed: () => Navigator.of(context).pop(),
      ),
      primary: ModalAction(
        label: l10n.saveButtonLabel,
        onPressed: () => _onSave(l10n),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:mostro/core/app_routes.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/features/settings/providers/nwc_provider.dart';
import 'package:mostro/features/settings/providers/settings_provider.dart';
import 'package:mostro/features/settings/widgets/currency_selector_dialog.dart';
import 'package:mostro/features/settings/widgets/language_selector.dart';
import 'package:mostro/features/settings/widgets/mostro_node_selector.dart';
import 'package:mostro/features/settings/widgets/relay_management_card.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _relaysExpanded = false;

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final wallet = ref.watch(nwcProvider);
    final isWalletConnected = wallet != null;
    final mostroPubkey = ref.watch(mostroPubkeyProvider);
    final colors = Theme.of(context).extension<AppColors>()!;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          // 1 — Language
          _settingsCard(
            context: context,
            colors: colors,
            icon: Icons.language,
            title: 'Language',
            subtitle: languageNameForCode(settings.language),
            onTap: () => showLanguageSelector(context),
          ),

          // 2 — Appearance (theme)
          _settingsCard(
            context: context,
            colors: colors,
            icon: Icons.brightness_6_outlined,
            title: AppLocalizations.of(context).appearanceSettingTitle,
            subtitle: _themeLabel(context, settings.themeMode),
            onTap: () => _showThemeDialog(context),
          ),

          // 3 — Default Fiat Currency
          _settingsCard(
            context: context,
            colors: colors,
            icon: Icons.monetization_on_outlined,
            title: 'Default Fiat Currency',
            subtitle: settings.defaultFiatCode ?? 'All currencies',
            onTap: () => showCurrencySelector(context),
          ),

          // 4 — Lightning Address
          _settingsCard(
            context: context,
            colors: colors,
            icon: Icons.bolt,
            title: 'Lightning Address',
            subtitle: settings.defaultLightningAddress ?? 'Tap to set',
            onTap: () => _showLightningAddressDialog(context),
          ),

          // 5 — NWC Wallet
          _settingsCard(
            context: context,
            colors: colors,
            icon: Icons.account_balance_wallet_outlined,
            title: 'NWC Wallet',
            subtitle: isWalletConnected
                ? 'NWC — Connected. Balance: ${wallet.balanceSats != null ? '${wallet.balanceSats} sats' : 'N/A'}'
                : 'Connect your Lightning wallet via NWC',
            onTap: () => context.push(
              isWalletConnected
                  ? AppRoute.walletSettings
                  : AppRoute.connectWallet,
            ),
          ),

          // 6 — Relays
          Container(
            margin: const EdgeInsets.only(bottom: AppSpacing.md),
            decoration: BoxDecoration(
              color: colors.backgroundCard,
              borderRadius: BorderRadius.circular(AppRadius.card),
            ),
            child: Column(
              children: [
                InkWell(
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  onTap: () =>
                      setState(() => _relaysExpanded = !_relaysExpanded),
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Row(
                      children: [
                        Icon(
                          Icons.router_outlined,
                          color: colors.mostroGreen,
                          size: 22,
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Relays',
                                style: Theme.of(context).textTheme.bodyLarge
                                    ?.copyWith(fontWeight: FontWeight.w600),
                              ),
                              Text(
                                'Manage relay connections',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          _relaysExpanded
                              ? Icons.keyboard_arrow_up
                              : Icons.chevron_right,
                          color: colors.textSubtle,
                        ),
                      ],
                    ),
                  ),
                ),
                if (_relaysExpanded)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      0,
                      AppSpacing.lg,
                      AppSpacing.lg,
                    ),
                    child: RelayManagementCard(),
                  ),
              ],
            ),
          ),

          // 6 — Push Notifications
          _settingsCard(
            context: context,
            colors: colors,
            icon: Icons.notifications_outlined,
            title: 'Push Notifications',
            subtitle: 'Manage notification preferences',
            onTap: () => context.push(AppRoute.notificationSettings),
          ),

          // 7 — Log Report
          _settingsCard(
            context: context,
            colors: colors,
            icon: Icons.description_outlined,
            title: 'Log Report',
            subtitle: 'View diagnostic logs',
            onTap: () => context.push(AppRoute.logs),
          ),

          // 8 — Mostro Node
          _settingsCard(
            context: context,
            colors: colors,
            icon: Icons.hub_outlined,
            title: 'Mostro Node',
            subtitle: truncatePubkey(mostroPubkey),
            onTap: () => showMostroNodeSelector(context),
          ),
        ],
      ),
    );
  }

  // ── Card builder ─────────────────────────────────────────────────────────────

  Widget _settingsCard({
    required BuildContext context,
    required AppColors colors,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      decoration: BoxDecoration(
        color: colors.backgroundCard,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.card),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Row(
            children: [
              Icon(icon, color: colors.mostroGreen, size: 22),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context)
                          .textTheme
                          .bodyLarge
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: colors.textSubtle),
            ],
          ),
        ),
      ),
    );
  }

  // ── Theme helpers ─────────────────────────────────────────────────────────────

  String _themeLabel(BuildContext context, ThemeMode mode) {
    final l10n = AppLocalizations.of(context);
    return switch (mode) {
      ThemeMode.dark => l10n.themeDark,
      ThemeMode.light => l10n.themeLight,
      ThemeMode.system => l10n.themeSystemDefault,
    };
  }

  Future<void> _showThemeDialog(BuildContext context) async {
    final current = ref.read(settingsProvider).themeMode;
    await showDialog<void>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(AppLocalizations.of(ctx).appearanceDialogTitle),
        children: ThemeMode.values.map((mode) {
          return ListTile(
            title: Text(_themeLabel(ctx, mode)),
            trailing: mode == current ? const Icon(Icons.check) : null,
            onTap: () {
              ref.read(settingsProvider.notifier).setThemeMode(mode);
              Navigator.of(ctx).pop();
            },
          );
        }).toList(),
      ),
    );
  }

  // ── Lightning address dialog ──────────────────────────────────────────────────

  Future<void> _showLightningAddressDialog(BuildContext context) async {
    final settings = ref.read(settingsProvider);
    final controller = TextEditingController(
      text: settings.defaultLightningAddress ?? '',
    );
    String? errorText;

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: const Text('Lightning Address'),
              content: TextField(
                controller: controller,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  hintText: 'user@domain.com',
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
                  child: const Text('Clear'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Cancel'),
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
                        () => errorText = 'Must be in user@domain format',
                      );
                      return;
                    }
                    ref
                        .read(settingsProvider.notifier)
                        .setDefaultLightningAddress(input);
                    Navigator.of(ctx).pop();
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    controller.dispose();
  }
}

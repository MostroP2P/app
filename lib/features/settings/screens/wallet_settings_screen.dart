import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:mostro/core/app_routes.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/settings/providers/nwc_provider.dart';
import 'package:mostro/src/rust/api/nwc.dart' as nwc_api;

/// Wallet Settings screen — Route `/wallet_settings`.
///
/// Displays connected wallet info (name, pubkey, relay URLs, balance).
/// Provides a Disconnect button to clear the wallet.
class WalletSettingsScreen extends ConsumerWidget {
  const WalletSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wallet = ref.watch(nwcProvider);
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>();
    final green = colors?.mostroGreen ?? const Color(0xFF8CC63F);
    final cardBg = colors?.backgroundCard ?? const Color(0xFF1E2230);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Wallet Configuration'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go(AppRoute.settings),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: wallet == null
            ? _DisconnectedView(green: green, cardBg: cardBg, theme: theme, colors: colors)
            : _ConnectedView(
                wallet: wallet,
                green: green,
                cardBg: cardBg,
                theme: theme,
                colors: colors,
                onDisconnect: () => _disconnect(context, ref),
              ),
      ),
    );
  }

  Future<void> _disconnect(BuildContext context, WidgetRef ref) async {
    try {
      await nwc_api.disconnectWallet();
    } catch (e) {
      debugPrint('[WalletSettings] disconnect failed: $e');
    }
    ref.read(nwcProvider.notifier).setDisconnected();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Wallet disconnected')),
      );
    }
  }
}

// ── Connected view ────────────────────────────────────────────────────────────

class _ConnectedView extends StatelessWidget {
  const _ConnectedView({
    required this.wallet,
    required this.green,
    required this.cardBg,
    required this.theme,
    required this.colors,
    required this.onDisconnect,
  });

  final NwcWalletState wallet;
  final Color green;
  final Color cardBg;
  final ThemeData theme;
  final AppColors? colors;
  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Wallet info card ──────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(AppRadius.card),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Status row
              Row(
                children: [
                  Icon(Icons.account_balance_wallet, color: green, size: 24),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    wallet.walletName ?? 'NWC Wallet',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: colors?.textPrimary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF065F46),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Connected',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: const Color(0xFF6EE7B7),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: AppSpacing.md),
              const Divider(height: 1),
              const SizedBox(height: AppSpacing.md),

              // Balance
              _InfoRow(
                label: 'Balance',
                value: wallet.balanceSats != null
                    ? '${wallet.balanceSats} sats'
                    : '—',
                colors: colors,
                theme: theme,
              ),

              const SizedBox(height: AppSpacing.sm),

              // Pubkey (truncated)
              _InfoRow(
                label: 'Pubkey',
                value: _truncate(wallet.walletPubkey),
                colors: colors,
                theme: theme,
                monospace: true,
              ),

              const SizedBox(height: AppSpacing.sm),

              // Relays
              _InfoRow(
                label: wallet.relayUrls.length == 1 ? 'Relay' : 'Relays',
                value: _formatRelays(wallet.relayUrls),
                colors: colors,
                theme: theme,
              ),
            ],
          ),
        ),

        const Spacer(),

        // ── Disconnect button ─────────────────────────────────────────
        OutlinedButton(
          onPressed: onDisconnect,
          style: OutlinedButton.styleFrom(
            foregroundColor: colors?.destructiveRed ?? const Color(0xFFD84D4D),
            side: BorderSide(
              color: colors?.destructiveRed ?? const Color(0xFFD84D4D),
            ),
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.button),
            ),
          ),
          child: const Text(
            'Disconnect',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),

        const SizedBox(height: AppSpacing.lg),
      ],
    );
  }

  String _truncate(String s) {
    if (s.length <= 16) return s;
    return '${s.substring(0, 8)}…${s.substring(s.length - 8)}';
  }

  String _formatRelays(List<String> relays) {
    if (relays.isEmpty) return '—';
    if (relays.length == 1) return relays.first;
    return '${relays.first} (+${relays.length - 1} more)';
  }
}

// ── Disconnected view ─────────────────────────────────────────────────────────

class _DisconnectedView extends StatelessWidget {
  const _DisconnectedView({
    required this.green,
    required this.cardBg,
    required this.theme,
    required this.colors,
  });

  final Color green;
  final Color cardBg;
  final ThemeData theme;
  final AppColors? colors;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpacing.xl),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(AppRadius.card),
          ),
          child: Column(
            children: [
              Icon(
                Icons.account_balance_wallet_outlined,
                color: colors?.textSubtle,
                size: 48,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'No wallet connected',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: colors?.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Connect a wallet to enable automatic Lightning payments.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors?.textSubtle,
                ),
              ),
            ],
          ),
        ),

        const Spacer(),

        FilledButton(
          onPressed: () => context.push(AppRoute.connectWallet),
          style: FilledButton.styleFrom(
            backgroundColor: green,
            foregroundColor: Colors.black,
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.button),
            ),
          ),
          child: const Text(
            'Connect Wallet',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),

        const SizedBox(height: AppSpacing.lg),
      ],
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    required this.colors,
    required this.theme,
    this.monospace = false,
  });

  final String label;
  final String value;
  final AppColors? colors;
  final ThemeData theme;
  final bool monospace;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 64,
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors?.textSubtle,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            value,
            style: (theme.textTheme.bodySmall ?? const TextStyle()).copyWith(
              color: colors?.textPrimary,
              fontFamily: monospace ? 'monospace' : null,
            ),
          ),
        ),
      ],
    );
  }
}

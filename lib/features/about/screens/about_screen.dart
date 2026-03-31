import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/core/mostro_defaults.dart';

// Default Mostro node info — imported from core/mostro_defaults.dart.
const _defaultPubkey = defaultMostroPubkey;
const _defaultRelays = defaultMostroRelays;

/// About screen — shows app version, Mostro branding, docs link, and default
/// node information.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  // TODO(bridge): replace with get_app_version() when bridge is wired
  static const _appVersion = '1.0.0';

  String _truncatePubkey(String pubkey) {
    if (pubkey.length <= 16) return pubkey;
    return '${pubkey.substring(0, 8)}…${pubkey.substring(pubkey.length - 8)}';
  }

  void _openDocs(BuildContext context) {
    // url_launcher is not in pubspec — show a SnackBar with the URL instead.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Docs at mostro.network/docs'),
        action: SnackBarAction(
          label: 'Copy',
          onPressed: () {
            Clipboard.setData(
              const ClipboardData(text: 'https://mostro.network/docs'),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>();
    assert(colors != null, 'AppColors theme extension must be registered');
    final c = colors!;

    return Scaffold(
      appBar: AppBar(
        title: const Text('About'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          // ── App identity section ─────────────────────────────────────────────
          Center(
            child: Column(
              children: [
                const SizedBox(height: AppSpacing.xl),
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: c.mostroGreen.withAlpha(30),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Icon(
                    Icons.hub_outlined,
                    size: 48,
                    color: c.mostroGreen,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Mostro',
                  style: Theme.of(context).textTheme.headlineLarge,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'v$_appVersion',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: c.textSubtle,
                      ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Peer-to-peer Bitcoin trading over Nostr',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: c.textSubtle,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.xl),
                // ── Documentation button ─────────────────────────────────────
                FilledButton.icon(
                  onPressed: () => _openDocs(context),
                  icon: const Icon(Icons.menu_book_outlined),
                  label: const Text('View Documentation'),
                ),
                const SizedBox(height: AppSpacing.xxl),
              ],
            ),
          ),

          // ── Mostro node section ──────────────────────────────────────────────
          Text(
            'Default Node',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: AppSpacing.md),

          Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: c.backgroundCard,
              borderRadius: BorderRadius.circular(AppRadius.card),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Pubkey row
                Row(
                  children: [
                    Icon(
                      Icons.fingerprint,
                      size: 18,
                      color: c.textSubtle,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      'Pubkey',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: c.textSubtle,
                          ),
                    ),
                    const Spacer(),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.sm,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: c.mostroGreen.withAlpha(30),
                            borderRadius: BorderRadius.circular(AppRadius.chip),
                          ),
                          child: Text(
                            'Trusted',
                            style: TextStyle(
                              color: c.mostroGreen,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Semantics(
                  button: true,
                  label: 'Copy pubkey to clipboard',
                  child: InkWell(
                    onTap: () {
                      Clipboard.setData(
                        const ClipboardData(text: _defaultPubkey),
                      );
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Pubkey copied to clipboard'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                    child: Text(
                      _truncatePubkey(_defaultPubkey),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontFamily: 'monospace',
                            color: c.textLink,
                          ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                const Divider(height: 1),
                const SizedBox(height: AppSpacing.md),

                // Relays
                Row(
                  children: [
                    Icon(
                      Icons.router_outlined,
                      size: 18,
                      color: c.textSubtle,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      'Relays',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: c.textSubtle,
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                ..._defaultRelays.map(
                  (url) => Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                    child: Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: c.mostroGreen,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Text(
                          url,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    fontFamily: 'monospace',
                                  ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: AppSpacing.xxl),

          // ── Footer ───────────────────────────────────────────────────────────
          Center(
            child: Text(
              'Open-source. Non-custodial. Private.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: c.textSubtle,
                  ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
      ),
    );
  }
}

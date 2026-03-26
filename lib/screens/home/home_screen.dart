/// Home screen shell (T038).
///
/// Shows:
///   • App bar with relay connection indicator dot.
///   • Current identity pseudonym derived from public key.
///   • Placeholder order list area (populated in Phase 5).
///   • Bottom navigation bar with placeholder tabs.
library home_screen;

import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/identity_provider.dart';
import '../../providers/relay_provider.dart';
import '../../router.dart';
import '../../src/rust/api/identity.dart' as rust_identity;
import '../../src/rust/api/types.dart';

/// Cached nym identity per public key — avoids refetching on every rebuild.
final _nymIdentityProvider =
    FutureProvider.family<NymIdentity, String>((ref, pubkey) {
  return rust_identity.getNymIdentity(pubkey: pubkey);
});

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final identity = ref.watch(identityProvider).valueOrNull;
    final connectionState = ref.watch(connectionStateProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mostro'),
        actions: [
          _ConnectionDot(connectionState),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.goNamed(Routes.settings),
          ),
        ],
      ),
      body: Column(
        children: [
          if (identity != null)
            _NymHeader(publicKey: identity.publicKey),
          const Expanded(
            child: Center(
              child: Text(
                'No open orders',
                style: TextStyle(color: Colors.grey),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.list_alt_outlined),
            selectedIcon: Icon(Icons.list_alt),
            label: 'Orders',
          ),
          NavigationDestination(
            icon: Icon(Icons.swap_horiz_outlined),
            selectedIcon: Icon(Icons.swap_horiz),
            label: 'Trade',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_outlined),
            selectedIcon: Icon(Icons.history),
            label: 'History',
          ),
        ],
        selectedIndex: 0,
        onDestinationSelected: (_) {},
      ),
    );
  }
}

// ── Connection indicator ────────────────────────────────────────────────────

class _ConnectionDot extends StatelessWidget {
  const _ConnectionDot(this.state);

  final ConnectionState state;

  @override
  Widget build(BuildContext context) {
    final color = switch (state) {
      ConnectionState.online => Colors.green,
      ConnectionState.reconnecting => Colors.orange,
      ConnectionState.offline => Colors.red,
    };
    final tooltip = switch (state) {
      ConnectionState.online => 'Connected',
      ConnectionState.reconnecting => 'Reconnecting…',
      ConnectionState.offline => 'Offline',
    };
    return Tooltip(
      message: tooltip,
      child: Container(
        width: 10,
        height: 10,
        margin: const EdgeInsets.only(right: 8),
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }
}

// ── Nym header ──────────────────────────────────────────────────────────────

class _NymHeader extends ConsumerWidget {
  const _NymHeader({required this.publicKey});

  final String publicKey;

  String _shortKey() {
    if (publicKey.length >= 12) {
      return '${publicKey.substring(0, 8)}…'
          '${publicKey.substring(publicKey.length - 4)}';
    }
    return publicKey;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // FutureProvider.family caches the result — no refetch on rebuild.
    final nymAsync = ref.watch(_nymIdentityProvider(publicKey));
    final nym = nymAsync.valueOrNull;
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        children: [
          // Avatar circle with deterministic HSV hue background.
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: nym != null
                  ? HSVColor.fromAHSV(1.0, nym.colorHue.toDouble(), 0.7, 0.8)
                      .toColor()
                  : theme.colorScheme.primaryContainer,
            ),
            child: const Icon(Icons.person, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                nym?.pseudonym ?? '…',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              Text(
                _shortKey(),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

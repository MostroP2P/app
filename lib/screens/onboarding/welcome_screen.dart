/// Welcome / onboarding entry screen (T032).
///
/// Shown on first launch when no identity exists.  Two paths:
///   • Create new identity  → /onboarding/create
///   • Import existing      → /onboarding/import
library welcome_screen;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../router.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
          child: Column(
            children: [
              const Spacer(flex: 2),

              // ── Logo / title ──────────────────────────────────────────────
              Icon(
                Icons.swap_horiz_rounded,
                size: 80,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 24),
              Text(
                'Mostro',
                style: theme.textTheme.displaySmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Text(
                'Peer-to-peer bitcoin trading over Nostr',
                style: theme.textTheme.bodyLarge
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),

              const Spacer(flex: 3),

              // ── Actions ───────────────────────────────────────────────────
              FilledButton.icon(
                onPressed: () =>
                    context.goNamed(Routes.onboardingCreate),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Create new identity'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () =>
                    context.goNamed(Routes.onboardingImport),
                icon: const Icon(Icons.download_rounded),
                label: const Text('Import existing identity'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
              ),

              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}

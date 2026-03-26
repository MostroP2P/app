/// Create identity screen (T033).
///
/// Flow:
///   1. Tap "Generate" → calls Rust createIdentity(), shows 12-word mnemonic.
///   2. User confirms they've saved the phrase.
///   3. Tap "Continue" → navigate to PIN setup.
library create_identity_screen;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/identity_provider.dart';
import '../../router.dart';

class CreateIdentityScreen extends ConsumerStatefulWidget {
  const CreateIdentityScreen({super.key});

  @override
  ConsumerState<CreateIdentityScreen> createState() =>
      _CreateIdentityScreenState();
}

class _CreateIdentityScreenState
    extends ConsumerState<CreateIdentityScreen> {
  List<String>? _words;
  bool _confirmed = false;
  bool _loading = false;
  String? _error;

  Future<void> _generate() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final mnemonic =
          await ref.read(identityProvider.notifier).createIdentity();
      if (mounted) {
        setState(() {
          _words = mnemonic.split(' ');
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Create identity'),
        // Prevent accidental back after identity is created.
        automaticallyImplyLeading: _words == null,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _words == null
              ? _buildIntroStep(theme)
              : _buildMnemonicStep(theme),
        ),
      ),
    );
  }

  // ── Step 1: intro ───────────────────────────────────────────────────────────

  Widget _buildIntroStep(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Spacer(),
        Icon(Icons.key_rounded, size: 64, color: theme.colorScheme.primary),
        const SizedBox(height: 24),
        Text(
          'Your identity is a Nostr key pair.',
          style: theme.textTheme.titleLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Text(
          'We\'ll generate a 12-word recovery phrase. '
          'Write it down — it\'s the only way to recover your account.',
          style: theme.textTheme.bodyMedium,
          textAlign: TextAlign.center,
        ),
        const Spacer(),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(
              _error!,
              style: TextStyle(color: theme.colorScheme.error),
              textAlign: TextAlign.center,
            ),
          ),
        FilledButton(
          onPressed: _loading ? null : _generate,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          child: _loading
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Generate recovery phrase'),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  // ── Step 2: show mnemonic ───────────────────────────────────────────────────

  Widget _buildMnemonicStep(ThemeData theme) {
    final words = _words!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Your recovery phrase',
          style: theme.textTheme.titleLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Write these 12 words in order. Never share them.',
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),

        // 3 columns × 4 rows word grid.
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: words.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            childAspectRatio: 2.8,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
          ),
          itemBuilder: (context, index) {
            return Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  Text(
                    '${index + 1}.',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      words[index],
                      style: theme.textTheme.bodySmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            );
          },
        ),

        const SizedBox(height: 24),

        CheckboxListTile(
          value: _confirmed,
          onChanged: (v) => setState(() => _confirmed = v ?? false),
          title: const Text("I've written down my recovery phrase"),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
        ),

        const Spacer(),

        FilledButton(
          onPressed: _confirmed
              ? () => context.goNamed(Routes.onboardingPin)
              : null,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          child: const Text('Continue'),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

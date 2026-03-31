import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/core/mostro_defaults.dart';

// ── Provider for current Mostro node pubkey ───────────────────────────────────

const _defaultMostroPubkey = defaultMostroPubkey;

/// In-memory override of the Mostro node pubkey.
///
/// **UI-only placeholder** — this value is not yet passed to the Rust bridge.
/// TODO(bridge): read mostroPubkeyProvider when constructing outgoing Nostr
/// events so order routing uses the selected node (Phase 18+).
final mostroPubkeyProvider = StateProvider<String>(
  (ref) => _defaultMostroPubkey,
);

// ── Helpers ───────────────────────────────────────────────────────────────────

/// Truncate a pubkey to `first8…last8` for display.
String truncatePubkey(String pubkey) {
  if (pubkey.length <= 16) return pubkey;
  return '${pubkey.substring(0, 8)}…${pubkey.substring(pubkey.length - 8)}';
}

// ── Regex for 64-char hex pubkey ──────────────────────────────────────────────

final _hexRegex = RegExp(r'^[0-9a-fA-F]{64}$');

// ── Widget ────────────────────────────────────────────────────────────────────

/// Bottom-sheet widget for selecting or entering a Mostro node pubkey.
///
/// Show via [showMostroNodeSelector].
class MostroNodeSelector extends ConsumerStatefulWidget {
  const MostroNodeSelector({super.key});

  @override
  ConsumerState<MostroNodeSelector> createState() =>
      _MostroNodeSelectorState();
}

class _MostroNodeSelectorState extends ConsumerState<MostroNodeSelector> {
  late TextEditingController _controller;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    final current = ref.read(mostroPubkeyProvider);
    _controller = TextEditingController(
      text: current == _defaultMostroPubkey ? '' : current,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _useDefault() {
    ref.read(mostroPubkeyProvider.notifier).state = _defaultMostroPubkey;
    _controller.clear();
    setState(() => _errorText = null);
    Navigator.of(context).pop();
  }

  void _confirm() {
    final input = _controller.text.trim();
    if (input.isEmpty) {
      _useDefault();
      return;
    }
    if (!_hexRegex.hasMatch(input)) {
      setState(() => _errorText = 'Must be a 64-character hex string');
      return;
    }
    ref.read(mostroPubkeyProvider.notifier).state = input;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final currentPubkey = ref.watch(mostroPubkeyProvider);
    final colors = Theme.of(context).extension<AppColors>()!;
    final isDefault = currentPubkey == _defaultMostroPubkey;

    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.lg,
        right: AppSpacing.lg,
        top: AppSpacing.lg,
        bottom: MediaQuery.viewInsetsOf(context).bottom + AppSpacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Mostro Node',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          // Current node display
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: colors.backgroundCard,
              borderRadius: BorderRadius.circular(AppRadius.card),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Current Node',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: colors.textSubtle,
                            ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        truncatePubkey(currentPubkey),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontFamily: 'monospace',
                            ),
                      ),
                    ],
                  ),
                ),
                if (isDefault)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: AppSpacing.xs,
                    ),
                    decoration: BoxDecoration(
                      color: colors.mostroGreen.withAlpha(30),
                      borderRadius: BorderRadius.circular(AppRadius.chip),
                    ),
                    child: Text(
                      'Trusted',
                      style: TextStyle(
                        color: colors.mostroGreen,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'Use a custom node pubkey',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colors.textSubtle,
                ),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _controller,
            maxLength: 64,
            decoration: InputDecoration(
              hintText: 'Enter 64-char hex pubkey',
              errorText: _errorText,
              counterText: '',
            ),
            onChanged: (_) {
              if (_errorText != null) setState(() => _errorText = null);
            },
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _useDefault,
                  child: const Text('Use Default'),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: FilledButton(
                  onPressed: _confirm,
                  child: const Text('Confirm'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Helper ────────────────────────────────────────────────────────────────────

/// Show the [MostroNodeSelector] as a modal bottom sheet.
void showMostroNodeSelector(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.card)),
    ),
    builder: (_) => const MostroNodeSelector(),
  );
}

/// Import identity screen (T034).
///
/// Supports two import modes (toggle via segmented button):
///   • Mnemonic — 12 BIP-39 words separated by spaces
///   • nsec      — bech32-encoded private key (starts with "nsec1…")
library import_identity_screen;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/identity_provider.dart';
import '../../router.dart';

enum _ImportMode { mnemonic, nsec }

class ImportIdentityScreen extends ConsumerStatefulWidget {
  const ImportIdentityScreen({super.key});

  @override
  ConsumerState<ImportIdentityScreen> createState() =>
      _ImportIdentityScreenState();
}

class _ImportIdentityScreenState
    extends ConsumerState<ImportIdentityScreen> {
  _ImportMode _mode = _ImportMode.mnemonic;
  final _controller = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _import() async {
    final input = _controller.text.trim();
    if (input.isEmpty) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      if (_mode == _ImportMode.mnemonic) {
        await ref
            .read(identityProvider.notifier)
            .importFromMnemonic(input, recover: true);
      } else {
        await ref
            .read(identityProvider.notifier)
            .importFromNsec(input);
      }
      if (mounted) context.goNamed(Routes.onboardingPin);
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
      appBar: AppBar(title: const Text('Import identity')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Mode selector ───────────────────────────────────────────
              SegmentedButton<_ImportMode>(
                segments: const [
                  ButtonSegment(
                    value: _ImportMode.mnemonic,
                    label: Text('Recovery phrase'),
                    icon: Icon(Icons.abc_rounded),
                  ),
                  ButtonSegment(
                    value: _ImportMode.nsec,
                    label: Text('nsec key'),
                    icon: Icon(Icons.vpn_key_rounded),
                  ),
                ],
                selected: {_mode},
                onSelectionChanged: (s) => setState(() {
                  _mode = s.first;
                  _controller.clear();
                  _error = null;
                }),
              ),

              const SizedBox(height: 24),

              // ── Input field ─────────────────────────────────────────────
              TextField(
                controller: _controller,
                minLines: _mode == _ImportMode.mnemonic ? 3 : 1,
                maxLines: _mode == _ImportMode.mnemonic ? 5 : 1,
                decoration: InputDecoration(
                  labelText: _mode == _ImportMode.mnemonic
                      ? 'Enter 12-word recovery phrase'
                      : 'Enter nsec1… private key',
                  hintText: _mode == _ImportMode.mnemonic
                      ? 'word1 word2 word3 …'
                      : 'nsec1…',
                  border: const OutlineInputBorder(),
                  errorText: _error,
                ),
                keyboardType: _mode == _ImportMode.mnemonic
                    ? TextInputType.multiline
                    : TextInputType.text,
                autocorrect: false,
                enableSuggestions: false,
                onChanged: (_) => setState(() => _error = null),
              ),

              const SizedBox(height: 8),

              if (_mode == _ImportMode.mnemonic)
                Text(
                  'Separate words with spaces.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),

              const Spacer(),

              FilledButton(
                onPressed: _loading ? null : _import,
                style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52)),
                child: _loading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child:
                            CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Import identity'),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

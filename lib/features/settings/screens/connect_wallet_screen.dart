import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mostro/core/app_routes.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/widgets/platform_aware_qr_scanner.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/settings/providers/nwc_provider.dart';

/// Connect Wallet screen — Route `/connect_wallet`.
///
/// User pastes or scans a NWC URI to connect a Lightning wallet.
/// On successful connection → navigates to `/wallet_settings`.
class ConnectWalletScreen extends ConsumerStatefulWidget {
  const ConnectWalletScreen({super.key});

  @override
  ConsumerState<ConnectWalletScreen> createState() =>
      _ConnectWalletScreenState();
}

class _ConnectWalletScreenState extends ConsumerState<ConnectWalletScreen> {
  final _uriController = TextEditingController();
  bool _connecting = false;
  bool _showScanner = false;

  @override
  void dispose() {
    _uriController.dispose();
    super.dispose();
  }

  bool get _isValid {
    final text = _uriController.text.trim();
    const prefix = 'nostr+walletconnect://';
    if (!text.startsWith(prefix)) return false;
    // Normalize to lowercase so uppercase hex (A-F) is accepted.
    final afterPrefix =
        text.substring(prefix.length).split('?').first.toLowerCase();
    return afterPrefix.length == 64 &&
        afterPrefix.codeUnits.every(
          (c) =>
              (c >= 48 && c <= 57) || // 0-9
              (c >= 97 && c <= 102), // a-f
        );
  }

  Future<void> _connect() async {
    if (_connecting || !_isValid) return;
    setState(() => _connecting = true);
    try {
      // TODO(bridge): Call nwc_api.connect_wallet(_uriController.text) via
      // Rust bridge once FFI bindings are generated.  On success, populate
      // NwcWalletState from the returned NwcWalletInfo.
      await Future.delayed(const Duration(milliseconds: 300));

      // Stub: store minimal wallet state from the parsed URI.
      final parsed = Uri.parse(_uriController.text.trim());
      final pubkey = parsed.host; // Dart normalises host to lowercase.
      final relayUrls = (parsed.queryParametersAll['relay'] ?? const [])
          .where((r) => r.startsWith('wss://') || r.startsWith('ws://'))
          .toList();

      if (!mounted) return;
      if (relayUrls.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No valid relay URL found in NWC URI.'),
          ),
        );
        setState(() => _connecting = false);
        return;
      }
      ref.read(nwcProvider.notifier).setConnected(
            NwcWalletState(
              walletPubkey: pubkey,
              relayUrls: relayUrls,
            ),
          );
      context.go(AppRoute.walletSettings);
    } catch (e) {
      if (!mounted) return;
      debugPrint('NWC connection error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Connection failed. Please check your NWC URI and try again.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  void _onQrDetected(String raw) {
    const scheme = 'nostr+walletconnect://';
    final normalized = raw.trim();
    if (normalized.toLowerCase().startsWith(scheme)) {
      // Normalize scheme to lowercase so _isValid's startsWith check passes.
      _uriController.text = scheme + normalized.substring(scheme.length);
      setState(() => _showScanner = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>();
    final green = colors?.mostroGreen ?? const Color(0xFF8CC63F);
    final cardBg = colors?.backgroundCard ?? const Color(0xFF1E2230);
    final inputBg = colors?.backgroundInput ?? const Color(0xFF252A3A);

    if (_showScanner) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Scan QR Code'),
          leading: BackButton(onPressed: () => setState(() => _showScanner = false)),
        ),
        body: PlatformAwareQrScanner(
          hint: AppLocalizations.of(context).pasteNwcUri,
          onDetected: _onQrDetected,
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Connect Wallet')),
      body: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: AppSpacing.lg),

            // ── Icon + description ──────────────────────────────────────
            Center(
              child: Icon(
                Icons.link,
                color: green,
                size: 56,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Connect your Lightning wallet using a\nNostr Wallet Connect (NWC) URI.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors?.textSecondary,
              ),
            ),

            const SizedBox(height: AppSpacing.xl),

            // ── URI input card ──────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(AppRadius.card),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _uriController,
                    maxLines: 3,
                    autocorrect: false,
                    enableSuggestions: false,
                    enableIMEPersonalizedLearning: false,
                    decoration: InputDecoration(
                      hintText: 'nostr+walletconnect://...',
                      labelText: 'NWC URI',
                      floatingLabelBehavior: FloatingLabelBehavior.auto,
                      filled: true,
                      fillColor: inputBg,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.input),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    style: (theme.textTheme.bodySmall ?? const TextStyle())
                        .copyWith(fontFamily: 'monospace'),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: AppSpacing.sm),

                  // QR scan + paste row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton.icon(
                        onPressed: () async {
                          final data =
                              await Clipboard.getData(Clipboard.kTextPlain);
                          final text = data?.text ?? '';
                          const scheme = 'nostr+walletconnect://';
                          if (text.toLowerCase().startsWith(scheme)) {
                            _uriController.text =
                                scheme + text.substring(scheme.length);
                            setState(() {});
                          } else {
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Clipboard does not contain a valid NWC URI.',
                                ),
                                duration: Duration(seconds: 2),
                              ),
                            );
                          }
                        },
                        icon: const Icon(Icons.paste, size: 16),
                        label: const Text('Paste'),
                        style: TextButton.styleFrom(
                          foregroundColor: colors?.textSecondary,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () => setState(() => _showScanner = true),
                        icon: const Icon(Icons.qr_code_scanner, size: 16),
                        label: const Text('Scan QR'),
                        style: TextButton.styleFrom(
                          foregroundColor: green,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const Spacer(),

            // ── Connect button ──────────────────────────────────────────
            FilledButton(
              onPressed: (_isValid && !_connecting) ? _connect : null,
              style: FilledButton.styleFrom(
                backgroundColor: green,
                foregroundColor: Colors.black,
                disabledBackgroundColor: green.withValues(alpha: 0.3),
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.button),
                ),
              ),
              child: _connecting
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.black54,
                      ),
                    )
                  : const Text(
                      'Connect',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
            ),

            const SizedBox(height: AppSpacing.lg),
          ],
        ),
      ),
    );
  }
}

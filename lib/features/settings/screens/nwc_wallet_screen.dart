import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:mostro/core/app_routes.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/core/automation/automation_id.dart';
import 'package:mostro/core/automation/automation_ids.dart';
import 'package:mostro/core/settings_palette.dart';
import 'package:mostro/features/settings/providers/nwc_provider.dart';
import 'package:mostro/features/settings/widgets/settings_section.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/widgets/platform_aware_qr_scanner.dart';
import 'package:mostro/shared/widgets/redesign_app_bar.dart';
import 'package:mostro/src/rust/api/nwc.dart' as nwc_api;

/// The NWC URI scheme, and the one place the app spells it.
const _nwcScheme = 'nostr+walletconnect://';

/// NWC wallet — handoff 10c.
///
/// One screen with two states rather than a wizard: connected shows the
/// wallet and `Desconectar`, unconnected explains what the wallet is *for*
/// (the old copy described the mechanism) and takes the URI.
class NwcWalletScreen extends ConsumerStatefulWidget {
  const NwcWalletScreen({super.key});

  @override
  ConsumerState<NwcWalletScreen> createState() => _NwcWalletScreenState();
}

class _NwcWalletScreenState extends ConsumerState<NwcWalletScreen> {
  final _uriController = TextEditingController();
  final _uriFocus = FocusNode();
  bool _busy = false;
  bool _showScanner = false;

  @override
  void initState() {
    super.initState();
    _uriFocus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _uriController.dispose();
    _uriFocus.dispose();
    super.dispose();
  }

  /// A URI is connectable when it carries the scheme and a 64-char hex wallet
  /// pubkey. Normalized to lowercase so an uppercase hex key is accepted.
  bool get _isValid {
    final text = _uriController.text.trim();
    if (!text.toLowerCase().startsWith(_nwcScheme)) return false;
    final key =
        text.substring(_nwcScheme.length).split('?').first.toLowerCase();
    return key.length == 64 &&
        key.codeUnits.every(
          (c) => (c >= 48 && c <= 57) || (c >= 97 && c <= 102),
        );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final book = OrderBookPalette.of(context);
    final wallet = ref.watch(nwcProvider);

    if (_showScanner) {
      return Scaffold(
        backgroundColor: book.bg,
        appBar: redesignAppBar(
          context,
          title: l10n.scanQrCodeTitle,
          onBack: () => setState(() => _showScanner = false),
        ),
        body: PlatformAwareQrScanner(
          hint: l10n.nwcUriPlaceholder,
          onDetected: _onQrDetected,
        ),
      );
    }

    return Scaffold(
      backgroundColor: book.bg,
      appBar: redesignAppBar(
        context,
        // `Billetera NWC`, not `Conectar billetera`: a setting with two
        // states, not an assistant.
        title: l10n.nwcWalletSettingTitle,
        onBack:
            () =>
                context.canPop()
                    ? context.pop()
                    : context.go(AppRoute.settings),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                redesignSidePadding,
                6,
                redesignSidePadding,
                14,
              ),
              children:
                  wallet == null
                      ? [
                        const _ExplainerCard(),
                        const SizedBox(height: settingsGroupGap),
                        _uriCard(l10n),
                        const SizedBox(height: settingsGroupGap),
                        SettingsFootnote(
                          icon: Icons.lock_outline,
                          // The fear that stops the user, which the old screen
                          // never answered.
                          text: l10n.nwcStorageFootnote,
                        ),
                      ]
                      : [_ConnectedCard(wallet: wallet)],
            ),
          ),
          _ActionBar(
            child:
                wallet == null ? _connectButton(l10n) : _disconnectButton(l10n),
          ),
        ],
      ),
    );
  }

  // ── Unconnected ───────────────────────────────────────────────────────────

  Widget _uriCard(AppLocalizations l10n) {
    final book = OrderBookPalette.of(context);
    final pal = SettingsPalette.of(context);
    final focused = _uriFocus.hasFocus;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: book.surface,
        borderRadius: const BorderRadius.all(Radius.circular(18)),
        border: Border.all(color: book.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.nwcUriFieldLabel.toUpperCase(),
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.6,
                color: focused ? pal.fieldLabelFocus : pal.fieldLabel,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _uriController,
              focusNode: _uriFocus,
              maxLines: 3,
              minLines: 1,
              autocorrect: false,
              enableSuggestions: false,
              enableIMEPersonalizedLearning: false,
              style: TextStyle(
                fontFamily: AppFonts.figures,
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: book.textPrimary,
              ),
              decoration: InputDecoration(
                isDense: true,
                // The real scheme rather than `NWC URI`: the user recognises
                // what is already on their clipboard.
                hintText: l10n.nwcUriPlaceholder,
                hintStyle: TextStyle(
                  fontFamily: AppFonts.figures,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: pal.placeholder,
                ),
                contentPadding: const EdgeInsets.only(bottom: 9),
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: pal.fieldUnderline),
                ),
                focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(
                    color: pal.fieldUnderlineFocus,
                    width: 1.5,
                  ),
                ),
              ),
              onChanged: (_) => setState(() {}),
            ).withAutomationId(AutomationIds.walletNwcUri),
            const SizedBox(height: 12),
            Row(
              children: [
                // Scanning is the real path; pasting is the exception, so it
                // stays neutral and scanning carries the lime tint.
                Expanded(
                  child: _SecondaryAction(
                    icon: Icons.content_paste_outlined,
                    label: l10n.pasteButtonLabel,
                    onTap: _pasteUri,
                  ).withAutomationId(AutomationIds.walletNwcPaste),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _SecondaryAction(
                    icon: Icons.qr_code_scanner,
                    label: l10n.scanQrButtonLabel,
                    onTap: () => setState(() => _showScanner = true),
                    accent: true,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _connectButton(AppLocalizations l10n) {
    final book = OrderBookPalette.of(context);
    final pal = SettingsPalette.of(context);
    final enabled = _isValid && !_busy;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.all(Radius.circular(16)),
        boxShadow: enabled ? pal.ctaShadow : const [],
      ),
      child: FilledButton(
        onPressed: enabled ? _connect : null,
        style: FilledButton.styleFrom(
          backgroundColor: book.lime,
          foregroundColor: book.onLime,
          // The old disabled pair (grey text on olive) was unreadable.
          disabledBackgroundColor: pal.ctaDisabledBg,
          disabledForegroundColor: pal.ctaDisabledInk,
          minimumSize: const Size.fromHeight(50),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(16)),
          ),
          textStyle: const TextStyle(
            fontFamily: AppFonts.ui,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
        // The button keeps its box while it works, so the bar does not jump.
        child:
            _busy
                ? SizedBox(
                  width: 15,
                  height: 15,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: book.onLime,
                  ),
                )
                : Text(l10n.connectButtonLabel),
      ),
    ).withAutomationId(AutomationIds.walletNwcConnect);
  }

  Widget _disconnectButton(AppLocalizations l10n) {
    final pal = SettingsPalette.of(context);
    return OutlinedButton(
      onPressed: _busy ? null : _disconnect,
      style: OutlinedButton.styleFrom(
        foregroundColor: pal.danger,
        side: BorderSide(color: pal.dangerBorder),
        minimumSize: const Size.fromHeight(50),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
        textStyle: const TextStyle(
          fontFamily: AppFonts.ui,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
      child: Text(l10n.disconnectButtonLabel),
    ).withAutomationId(AutomationIds.walletSettingsDisconnect);
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  /// Reads the clipboard and checks the scheme before filling the field: a
  /// clipboard holding something else leaves the field alone and says so,
  /// rather than putting a value there the user has to clear.
  Future<void> _pasteUri() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = (data?.text ?? '').trim();
    if (!mounted) return;
    if (!text.toLowerCase().startsWith(_nwcScheme)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context).clipboardInvalidNwcUriMessage,
          ),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }
    setState(() => _uriController.text = _normalizeScheme(text));
  }

  /// A valid QR connects straight away — coming back to the form to press
  /// `Conectar` adds a step that can only be answered one way.
  void _onQrDetected(String raw) {
    final text = raw.trim();
    if (!text.toLowerCase().startsWith(_nwcScheme)) return;
    _uriController.text = _normalizeScheme(text);
    setState(() => _showScanner = false);
    _connect();
  }

  /// Lowercases the scheme only, so `_isValid`'s `startsWith` matches while
  /// the wallet key keeps the case the wallet sent.
  static String _normalizeScheme(String text) =>
      _nwcScheme + text.substring(_nwcScheme.length);

  Future<void> _connect() async {
    if (_busy || !_isValid) return;
    setState(() => _busy = true);
    final uri = _uriController.text.trim();
    try {
      final info = await nwc_api.connectWallet(nwcUri: uri);
      if (!mounted) return;
      ref
          .read(nwcProvider.notifier)
          .setConnected(
            NwcWalletState(
              walletPubkey: info.walletPubkey,
              relayUrls: info.relayUrls,
              walletName: info.walletName,
              balanceSats: info.balanceSats?.toInt(),
            ),
            nwcUri: uri,
          );
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.walletConnectedMessage)));
      if (context.canPop()) context.pop();
    } catch (e) {
      if (!mounted) return;
      debugPrint('[nwc] connection failed: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context).nwcConnectionFailedMessage,
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disconnect() async {
    setState(() => _busy = true);
    try {
      await nwc_api.disconnectWallet();
    } catch (e) {
      debugPrint('[nwc] disconnect failed: $e');
    }
    ref.read(nwcProvider.notifier).setDisconnected();
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context).walletDisconnectedMessage),
      ),
    );
  }
}

// ── Cards ─────────────────────────────────────────────────────────────────────

/// What the wallet is for, not how NWC works. Replaces the stray 40px glyph
/// and `Conecta tu wallet Lightning usando una URI de Nostr Wallet Connect`,
/// which described the mechanism instead of the benefit.
class _ExplainerCard extends StatelessWidget {
  const _ExplainerCard();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final book = OrderBookPalette.of(context);
    final pal = SettingsPalette.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: book.surface,
        borderRadius: const BorderRadius.all(Radius.circular(18)),
        border: Border.all(color: book.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: pal.discBg,
                    shape: BoxShape.circle,
                    border: Border.all(color: pal.discBorder),
                  ),
                  child: Icon(
                    Icons.account_balance_wallet_outlined,
                    size: 16,
                    color: pal.dotOnline,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.nwcExplainerTitle,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: book.textPrimary,
                        ),
                      ),
                      Text(
                        l10n.nwcExplainerSubtitle,
                        style: TextStyle(
                          fontSize: 11,
                          color: book.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              l10n.nwcExplainerBody,
              style: TextStyle(
                fontSize: 12,
                height: 1.5,
                color: book.textSecondary,
              ),
            ),
          ],
        ),
      ),
    ).withAutomationId(
      AutomationIds.walletConnection,
      label: AutomationIds.walletDisconnected,
    );
  }
}

/// The connected state: the wallet's name, a lime `Conectada` dot, and the
/// balance when NWC exposes one.
class _ConnectedCard extends StatelessWidget {
  const _ConnectedCard({required this.wallet});

  final NwcWalletState wallet;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final book = OrderBookPalette.of(context);
    final pal = SettingsPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: book.surface,
            borderRadius: const BorderRadius.all(Radius.circular(18)),
            border: Border.all(color: pal.summaryOkBorder),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: pal.discBg,
                    shape: BoxShape.circle,
                    border: Border.all(color: pal.discBorder),
                  ),
                  child: Icon(
                    Icons.account_balance_wallet,
                    size: 16,
                    color: pal.dotOnline,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        wallet.walletName ?? l10n.nwcWalletSettingTitle,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: book.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: pal.dotOnline,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            l10n.nwcConnectedStatus,
                            style: TextStyle(
                              fontSize: 11,
                              color: book.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (wallet.balanceSats != null)
                  Text(
                    l10n.nwcBalanceSats('${wallet.balanceSats}'),
                    style: TextStyle(
                      fontFamily: AppFonts.figures,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: book.limeInk,
                    ),
                  ),
              ],
            ),
          ),
        ).withAutomationId(
          AutomationIds.walletConnection,
          label: AutomationIds.walletConnected,
        ),
        const SizedBox(height: settingsGroupGap),
        SettingsGroup(
          rows: [
            SettingsRow(
              icon: Icons.key_outlined,
              label: l10n.pubkeyLabel,
              value: _truncate(wallet.walletPubkey),
              semanticValue: wallet.walletPubkey,
              valueIsData: true,
            ),
            SettingsRow(
              icon: Icons.router_outlined,
              label:
                  wallet.relayUrls.length == 1
                      ? l10n.relayLabel
                      : l10n.relaysLabel,
              value: _formatRelays(wallet.relayUrls, l10n),
              valueIsData: true,
            ),
          ],
        ),
        const SizedBox(height: settingsGroupGap),
        SettingsFootnote(
          icon: Icons.lock_outline,
          text: l10n.nwcStorageFootnote,
        ),
      ],
    );
  }

  static String _truncate(String s) =>
      s.length <= 16 ? s : '${s.substring(0, 8)}…${s.substring(s.length - 8)}';

  static String _formatRelays(List<String> relays, AppLocalizations l10n) {
    if (relays.isEmpty) return '—';
    if (relays.length == 1) return relays.first;
    return '${relays.first} ${l10n.relaysMoreSuffix(relays.length - 1)}';
  }
}

// ── Chrome ────────────────────────────────────────────────────────────────────

/// The bar the primary action lives in, pinned above the system inset.
class _ActionBar extends StatelessWidget {
  const _ActionBar({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: book.surfaceNav,
        border: Border(top: BorderSide(color: book.navBorder)),
      ),
      child: Padding(
        // #267: the bottom system-bar inset so the button clears the gesture
        // / 3-button navigation bar.
        padding: EdgeInsets.fromLTRB(
          redesignSidePadding,
          12,
          redesignSidePadding,
          18 + MediaQuery.of(context).viewPadding.bottom,
        ),
        child: child,
      ),
    );
  }
}

/// `Pegar` and `Escanear QR`: same shape, different weight — [accent] carries
/// the lime tint of the path the user is meant to take.
class _SecondaryAction extends StatelessWidget {
  const _SecondaryAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.accent = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    final pal = SettingsPalette.of(context);
    final ink = accent ? book.limeInk : book.textBody;
    return Material(
      color: accent ? pal.scanFill : pal.buttonFill,
      borderRadius: const BorderRadius.all(Radius.circular(14)),
      child: InkWell(
        onTap: onTap,
        borderRadius: const BorderRadius.all(Radius.circular(14)),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.all(Radius.circular(14)),
            border: Border.all(
              color: accent ? pal.scanBorder : pal.buttonBorder,
            ),
          ),
          padding: const EdgeInsets.symmetric(vertical: 11),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14, color: ink),
              const SizedBox(width: 6),
              // Half a 360 px screen is tight for `Escanear QR` and tighter
              // for the longer translations: ellipsize rather than overflow.
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: accent ? FontWeight.w600 : FontWeight.w500,
                    color: ink,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

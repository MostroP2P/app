import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:mostro/core/app_routes.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/core/settings_palette.dart';
import 'package:mostro/features/cashu/cashu_error_messages.dart';
import 'package:mostro/features/cashu/providers/cashu_wallet_provider.dart';
import 'package:mostro/features/settings/widgets/settings_section.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/widgets/mostro_modal.dart';
import 'package:mostro/shared/widgets/paste_field.dart';
import 'package:mostro/shared/widgets/platform_aware_qr_scanner.dart';
import 'package:mostro/shared/widgets/redesign_app_bar.dart';
import 'package:mostro/src/rust/api/types.dart';

/// The embedded Cashu wallet — phase C3 of `docs/cashu/README.md`.
///
/// Deliberately minimal: balance, redeem a token, export a token, and the mint
/// it all happens at. It exists to fund and drain escrows, not to be a general
/// Cashu wallet. Melt/mint to Lightning, holding several mints at once and
/// backup UX are later phases.
///
/// Always reachable from Settings, on every node (docs/cashu/README.md §1.2).
/// The mint is the user's: set here, or taken from the first token received,
/// and never changed by a node switch.
class CashuWalletScreen extends ConsumerStatefulWidget {
  const CashuWalletScreen({super.key});

  @override
  ConsumerState<CashuWalletScreen> createState() => _CashuWalletScreenState();
}

class _CashuWalletScreenState extends ConsumerState<CashuWalletScreen> {
  /// True while a command runs, so buttons cannot be double-fired — two
  /// concurrent sends would each reserve proofs.
  bool _busy = false;

  /// The last token exported in this session.
  ///
  /// Kept so the dialog can be re-opened. A token *is* the money: if the only
  /// copy is a dialog the user can dismiss, one stray tap loses the funds until
  /// they find the proof-state check. Cleared when the user says they are done
  /// with it.
  String? _lastToken;

  /// No mint was ever set, so the open-time connect had nothing to bind to.
  /// A state to explain, not an error to flash.
  bool _noMint = false;

  @override
  void initState() {
    super.initState();
    // Connecting is lazy and idempotent; doing it here means the balance is
    // real by the time the user reads it, rather than after they tap something.
    WidgetsBinding.instance.addPostFrameCallback((_) => _connect());
  }

  /// Holds the busy flag, so "Set mint" cannot race the open-time connect.
  Future<void> _connect() async {
    // Runs from a post-frame callback, which can land after a quick pop.
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(cashuWalletControllerProvider).connect();
    } catch (e) {
      if (!mounted) return;
      if (e.toString().contains('CashuNoMint')) {
        setState(() => _noMint = true);
      } else {
        _showError(e);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showError(Object error) {
    final l10n = AppLocalizations.of(context);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(cashuErrorMessage(error, l10n))));
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) _showError(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Runs [prompt] while holding the busy flag, so a fast double tap cannot
  /// stack two sheets or dialogs, then releases it — [_run] takes it again
  /// for the Rust call that follows.
  Future<T?> _prompt<T>(Future<T?> Function() prompt) async {
    if (_busy) return null;
    setState(() => _busy = true);
    try {
      return await prompt();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _receive() async {
    final l10n = AppLocalizations.of(context);
    final token = await _prompt(
      () => showMostroDialog<String>(
        context: context,
        builder: (_) => const _ReceiveDialog(),
      ),
    );

    if (token == null || token.trim().isEmpty || !mounted) return;

    await _run(() async {
      final amount = await ref
          .read(cashuWalletControllerProvider)
          .receiveToken(token.trim());
      if (!mounted) return;
      // With no mint set, the token's mint is now the wallet's.
      setState(() => _noMint = false);
      _showMessage(l10n.cashuReceived(amount.toInt()));
    });
  }

  Future<void> _send(int balanceSats) async {
    final amount = await _prompt(
      () => showMostroDialog<int>(
        context: context,
        builder: (_) => _AmountDialog(maxSats: balanceSats),
      ),
    );
    if (amount == null || !mounted) return;

    await _run(() async {
      final token = await ref
          .read(cashuWalletControllerProvider)
          .createToken(BigInt.from(amount));
      if (mounted) {
        setState(() => _lastToken = token);
        await _showToken(token);
      }
    });
  }

  Future<void> _showToken(String token) {
    return showMostroDialog<void>(
      context: context,
      // Not dismissible: closing this by tapping outside used to be the fastest
      // way to lose an exported token. `barrierDismissible` covers the tap;
      // `PopScope` covers the Android back gesture, which it does not.
      barrierDismissible: false,
      builder:
          (_) => PopScope(canPop: false, child: _TokenDialog(token: token)),
    );
  }

  /// Set the wallet's mint, or change it. A balance never moves with the mint:
  /// it stays at the old one, and the user is told so before they switch.
  Future<void> _setMint(CashuWalletStatus? status) async {
    final l10n = AppLocalizations.of(context);
    final balance = status?.balanceSats;
    final oldMint = status?.mintUrl;
    // Bound or not: a set mint that is not answering still holds its sats,
    // and Rust reads them from disk.
    if (oldMint != null && balance != null && balance > BigInt.zero) {
      final locale = Localizations.localeOf(context).toString();
      final goOn = await _prompt(
        () => showMostroDialog<bool>(
          context: context,
          builder:
              (dialogContext) => MostroDialog(
                title: l10n.cashuChangeMintTitle,
                content: Text(
                  l10n.cashuChangeMintWarning(
                    _fmtSats(balance, locale),
                    oldMint,
                  ),
                ),
                secondary: ModalAction(
                  label: l10n.cancel,
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                ),
                primary: ModalAction(
                  label: l10n.continueButtonLabel,
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                ),
              ),
        ),
      );
      if (goOn != true || !mounted) return;
    }

    final mintUrl = await _prompt(
      () => showMostroDialog<String>(
        context: context,
        builder: (_) => const _MintDialog(),
      ),
    );
    if (mintUrl == null || !mounted) return;

    await _run(() async {
      await ref.read(cashuWalletControllerProvider).connect(mintUrl: mintUrl);
      if (mounted) setState(() => _noMint = false);
    });
  }

  /// Housekeeping against the mint. It refreshes the balance by forgetting
  /// spent proofs; it does not — and must not claim to — recover an exported
  /// token nobody redeemed (phase C10).
  Future<void> _sync() async {
    final l10n = AppLocalizations.of(context);
    await _run(() async {
      await ref.read(cashuWalletControllerProvider).sweepSpentProofs();
      if (mounted) _showMessage(l10n.cashuSynced);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final book = OrderBookPalette.of(context);
    final pal = SettingsPalette.of(context);
    final status = ref.watch(cashuWalletProvider).valueOrNull;
    // `null` here means "not read yet or unreadable", which is not the same as
    // an empty wallet — see CashuWalletStatus.balance_sats.
    final balance = status?.balanceSats;

    return Scaffold(
      backgroundColor: book.bg,
      appBar: redesignAppBar(
        context,
        title: l10n.cashuWalletTitle,
        onBack:
            () =>
                context.canPop()
                    ? context.pop()
                    : context.go(AppRoute.settings),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          redesignSidePadding,
          6,
          redesignSidePadding,
          14,
        ),
        children: [
          _BalanceCard(
            status: status,
            noMint: _noMint,
            // Not while a set mint's balance is unknown: the warning that the
            // balance stays at the old mint could not be shown.
            onSetMint:
                _busy || (status?.mintUrl != null && balance == null)
                    ? null
                    : () => _setMint(status),
          ),
          const SizedBox(height: settingsGroupGap),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _busy ? null : _receive,
                  style: _primaryStyle(book, pal),
                  icon: const Icon(Icons.qr_code_scanner, size: 18),
                  label: Text(l10n.cashuReceiveButton),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  // Nothing to send from an empty wallet; disabling says so
                  // before the mint has to.
                  // Disabled while the balance is unknown as well as when it
                  // is zero: offering a send we cannot size is worse than
                  // waiting a frame for the real figure.
                  onPressed:
                      _busy || balance == null || balance == BigInt.zero
                          ? null
                          : () => _send(balance.toInt()),
                  style: _secondaryStyle(book, pal),
                  icon: const Icon(Icons.upload_outlined, size: 18),
                  label: Text(l10n.cashuSendButton),
                ),
              ),
            ],
          ),
          if (_lastToken != null) ...[
            const SizedBox(height: settingsGroupGap),
            _Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.cashuLastTokenPending,
                    style: TextStyle(fontSize: 13, color: book.textBody),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () => _showToken(_lastToken!),
                        style: _linkStyle(book),
                        child: Text(l10n.cashuShowLastToken),
                      ),
                      TextButton(
                        onPressed: () => setState(() => _lastToken = null),
                        style: _linkStyle(book),
                        child: Text(l10n.cashuLastTokenDone),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: settingsGroupGap),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: _busy ? null : _sync,
              style: _linkStyle(book),
              icon: const Icon(Icons.refresh, size: 16),
              label: Text(l10n.cashuSyncButton),
            ),
          ),
          const SizedBox(height: 6),
          SettingsFootnote(
            icon: Icons.info_outline,
            text: l10n.cashuWalletExplanation,
          ),
        ],
      ),
    );
  }
}

// ── Styles ────────────────────────────────────────────────────────────────────
//
// From the palette, never the v1 theme (DS-CMP-3, DS-CMP-4, DS-CMP-17): the
// same shapes and inks as the NWC wallet screen beside this one in Settings.

ButtonStyle _primaryStyle(OrderBookPalette book, SettingsPalette pal) =>
    FilledButton.styleFrom(
      backgroundColor: book.lime,
      foregroundColor: book.onLime,
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
    );

ButtonStyle _secondaryStyle(OrderBookPalette book, SettingsPalette pal) =>
    OutlinedButton.styleFrom(
      foregroundColor: book.textBody,
      backgroundColor: pal.buttonFill,
      disabledForegroundColor: pal.ctaDisabledInk,
      side: BorderSide(color: pal.buttonBorder),
      minimumSize: const Size.fromHeight(50),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
      ),
      textStyle: const TextStyle(
        fontFamily: AppFonts.ui,
        fontSize: 15,
        fontWeight: FontWeight.w500,
      ),
    );

ButtonStyle _linkStyle(OrderBookPalette book) => TextButton.styleFrom(
  foregroundColor: book.limeInk,
  disabledForegroundColor: book.textFaint,
  textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
);

/// An underlined field that sets every state itself, as `InvoiceInputField`
/// does (DS-CMP-19): left to the theme, it would paint v1's filled underline.
InputDecoration _fieldDecoration(
  OrderBookPalette book,
  SettingsPalette pal, {
  required String label,
  String? hint,
  String? error,
}) => InputDecoration(
  labelText: label,
  labelStyle: TextStyle(fontSize: 13, color: pal.fieldLabel),
  floatingLabelStyle: TextStyle(fontSize: 13, color: pal.fieldLabelFocus),
  hintText: hint,
  hintStyle: TextStyle(fontSize: 14, color: pal.placeholder),
  errorText: error,
  errorStyle: TextStyle(fontSize: 12, color: pal.danger),
  filled: false,
  enabledBorder: UnderlineInputBorder(
    borderSide: BorderSide(color: pal.fieldUnderline),
  ),
  focusedBorder: UnderlineInputBorder(
    borderSide: BorderSide(color: pal.fieldUnderlineFocus, width: 1.5),
  ),
  errorBorder: UnderlineInputBorder(borderSide: BorderSide(color: pal.danger)),
  focusedErrorBorder: UnderlineInputBorder(
    borderSide: BorderSide(color: pal.danger, width: 1.5),
  ),
);

/// A redesign card: surface, radius 18, palette border (DS-CMP-8).
class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: book.surface,
        borderRadius: const BorderRadius.all(Radius.circular(18)),
        border: Border.all(color: book.border),
      ),
      child: Padding(padding: const EdgeInsets.all(14), child: child),
    );
  }
}

/// Group digits so a six-figure balance is readable, with the separator the
/// reader's locale uses — a comma is wrong in four of the five languages this
/// app ships, where `1.234.567` or `1 234 567` is the number and `1,234,567`
/// reads as something else entirely.
///
/// The digits still come from a `BigInt` walk rather than `NumberFormat.format`,
/// which takes a `num`: a `u64` balance can exceed what `int` and `double` hold
/// exactly, and bearer money must never be shown rounded. intl supplies only
/// the separator. That is enough here because all five shipped locales group in
/// plain threes; a locale that groups otherwise (Indian digits, say) would need
/// the full formatter and a BigInt-safe path with it.
String _fmtSats(BigInt sats, String locale) {
  final separator = NumberFormat.decimalPattern(locale).symbols.GROUP_SEP;
  final digits = sats.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(separator);
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

/// Balance, mint, and — when the wallet could not bind — that it did not, with
/// the way to set or change the mint.
class _BalanceCard extends StatelessWidget {
  const _BalanceCard({
    required this.status,
    required this.noMint,
    required this.onSetMint,
  });

  final CashuWalletStatus? status;

  /// No mint was ever set: say how to get one rather than "not connected".
  final bool noMint;

  /// Opens the mint flow; `null` while a command runs.
  final VoidCallback? onSetMint;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final book = OrderBookPalette.of(context);
    final pal = SettingsPalette.of(context);
    final connected = status?.connected ?? false;
    final mintUrl = status?.mintUrl;

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.cashuBalanceLabel,
            style: TextStyle(fontSize: 13, color: book.textMuted),
          ),
          const SizedBox(height: 4),
          Text(
            // An unreadable balance renders as "—", never as a number. Showing
            // "0 Satoshis" for a failed read is the one thing a bearer-money
            // wallet must not do.
            status?.balanceSats == null
                ? '—'
                : '${_fmtSats(status!.balanceSats!, Localizations.localeOf(context).toString())} ${l10n.aboutSatoshisSuffix}',
            // The amount is the screen's subject: a hero figure (§3.2).
            style: TextStyle(
              fontFamily: AppFonts.figures,
              fontSize: 26,
              fontWeight: FontWeight.w700,
              color: book.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          // The mint is named whenever one is set, bound or not: one that is
          // not answering still holds its sats, and replacing it must never
          // be blind.
          if (mintUrl != null)
            Text(
              l10n.cashuMintLabel(mintUrl),
              style: TextStyle(fontSize: 13, color: book.textBody),
            ),
          if (!connected && mintUrl == null && noMint)
            Text(
              l10n.cashuNoMintSet,
              style: TextStyle(fontSize: 13, color: book.textBody),
            )
          else if (!connected)
            Text(
              l10n.cashuNotConnected,
              style: TextStyle(fontSize: 13, color: pal.danger),
            ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              onPressed: onSetMint,
              style: _linkStyle(book),
              child: Text(
                mintUrl != null
                    ? l10n.cashuChangeMintButton
                    : l10n.cashuSetMintButton,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Scans a QR in a sheet over the dialog that asked: the decoded value, or
/// null when the user backs out. [hint] is the paste form's placeholder, for
/// a camera that cannot start.
Future<String?> _scanQr(BuildContext context, String hint) {
  return showMostroSheet<String>(
    context: context,
    builder:
        (sheetContext) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
          ),
          child: PlatformAwareQrScanner(
            hint: hint,
            onDetected: (value) => Navigator.of(sheetContext).pop(value),
          ),
        ),
  );
}

/// Which mint the wallet binds to, typed, pasted or scanned. Only emptiness is
/// checked here: whether it is a usable mint is Rust's call (`InvalidMintUrl`,
/// `CashuMintUnreachable`, `CashuMintUnusable`), and nothing is remembered
/// until the mint has answered.
class _MintDialog extends StatefulWidget {
  const _MintDialog();

  @override
  State<_MintDialog> createState() => _MintDialogState();
}

class _MintDialogState extends State<_MintDialog> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _fill(String value) {
    _controller.text = value.trim();
    if (_error != null) setState(() => _error = null);
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (!mounted) return;
    if (text.isEmpty) {
      setState(() => _error = AppLocalizations.of(context).clipboardEmptyError);
      return;
    }
    _fill(text);
  }

  Future<void> _scan() async {
    final scanned = await _scanQr(
      context,
      AppLocalizations.of(context).cashuMintFieldHint,
    );
    if (scanned != null && mounted) _fill(scanned);
  }

  void _submit() {
    final url = _controller.text.trim();
    if (url.isEmpty) {
      setState(() => _error = AppLocalizations.of(context).enterValueError);
      return;
    }
    Navigator.of(context).pop(url);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final book = OrderBookPalette.of(context);
    final pal = SettingsPalette.of(context);
    // Read once, so whether Scan QR works and the reason it gives cannot
    // disagree.
    final canScan = canScanQr();
    return MostroDialog(
      title: l10n.cashuMintDialogTitle,
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.url,
        autocorrect: false,
        style: TextStyle(fontSize: 14, color: book.textPrimary),
        decoration: _fieldDecoration(
          book,
          pal,
          label: l10n.cashuMintFieldLabel,
          hint: l10n.cashuMintFieldHint,
          error: _error,
        ),
        onSubmitted: (_) => _submit(),
      ),
      // Ways to fill the field, not answers to the dialog: links, not buttons.
      links: [
        ModalLink(label: l10n.pasteButtonLabel, onPressed: _paste),
        ModalLink(
          label: l10n.scanQrButtonLabel,
          // As in the Receive dialog: where there is no camera, the scanner
          // would only be a second paste field over this one.
          onPressed: canScan ? _scan : null,
          tooltip: canScan ? null : l10n.qrScanUnavailable,
        ),
      ],
      secondary: ModalAction(
        label: l10n.cancel,
        onPressed: () => Navigator.of(context).pop(),
      ),
      primary: ModalAction(label: l10n.connectButtonLabel, onPressed: _submit),
    );
  }
}

/// Receive: the token field, Paste and Scan QR as its links — the same way
/// in as the mint dialog — then Cancel and Receive.
///
/// A token is mostly shared as text, and one too large for a QR has no other
/// way in, so pasting is never hidden behind the camera. Pops the trimmed
/// token; Receive stays disabled while the field is empty, so nothing blank
/// reaches the mint.
class _ReceiveDialog extends StatefulWidget {
  const _ReceiveDialog();

  @override
  State<_ReceiveDialog> createState() => _ReceiveDialogState();
}

class _ReceiveDialogState extends State<_ReceiveDialog> {
  final _controller = TextEditingController();
  String? _error;

  String get _token => _controller.text.trim();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Fills the field rather than redeeming at once: the user sees what they
  /// pasted before it goes to the mint. An empty clipboard says so under the
  /// field, where the user is looking.
  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = (data?.text ?? '').trim();
    if (!mounted) return;
    setState(() {
      if (text.isEmpty) {
        _error = AppLocalizations.of(context).clipboardEmptyError;
      } else {
        _controller.text = text;
        _error = null;
      }
    });
  }

  /// A scanned token is redeemed straight away: coming back to the dialog to
  /// press Receive adds a step with one answer.
  Future<void> _scan() async {
    final value =
        (await _scanQr(
          context,
          AppLocalizations.of(context).cashuReceiveHint,
        ))?.trim();
    if (!mounted || value == null || value.isEmpty) return;
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final pal = SettingsPalette.of(context);
    // Read once, so whether Scan QR works and the reason it gives cannot
    // disagree.
    final canScan = canScanQr();
    return MostroDialog(
      title: l10n.cashuReceiveTitle,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.cashuTokenFieldLabel.toUpperCase(),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.6,
              color: pal.fieldLabel,
            ),
          ),
          const SizedBox(height: 8),
          PasteField(
            controller: _controller,
            // Focused where there is no camera, so a desktop paste shortcut
            // lands without a click first. On a phone it would raise the
            // keyboard over the Scan QR the user probably came for.
            autofocus: !canScan,
            hint: l10n.cashuPasteTokenHint,
            errorText: _error,
            onChanged: (_) => setState(() => _error = null),
            // Enter is Receive, under the same rule as the button; on an
            // empty field it does nothing and the focus stays put.
            onEditingComplete: () {
              if (_token.isNotEmpty) Navigator.of(context).pop(_token);
            },
          ),
        ],
      ),
      // Ways to fill the field, not answers to the dialog: links, not
      // buttons, as in the mint dialog.
      links: [
        ModalLink(label: l10n.pasteButtonLabel, onPressed: _paste),
        ModalLink(
          label: l10n.scanQrButtonLabel,
          // Where there is no camera, the scanner would only be a second
          // paste field over this one: off, and says why.
          onPressed: canScan ? _scan : null,
          tooltip: canScan ? null : l10n.qrScanUnavailable,
        ),
      ],
      secondary: ModalAction(
        label: l10n.cancel,
        onPressed: () => Navigator.of(context).pop(),
      ),
      primary: ModalAction(
        label: l10n.cashuReceiveButton,
        onPressed:
            _token.isEmpty ? null : () => Navigator.of(context).pop(_token),
      ),
    );
  }
}

/// How much to export. Bounded by the balance: a send larger than the wallet
/// holds fails at the mint with a far less obvious message.
class _AmountDialog extends StatefulWidget {
  const _AmountDialog({required this.maxSats});

  final int maxSats;

  @override
  State<_AmountDialog> createState() => _AmountDialogState();
}

class _AmountDialogState extends State<_AmountDialog> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final l10n = AppLocalizations.of(context);
    final amount = int.tryParse(_controller.text.trim());
    if (amount == null || amount <= 0) {
      setState(() => _error = l10n.cashuErrorAmountZero);
      return;
    }
    // Bounded by the balance only. A mint fee, or a swap cdk needs to hit an
    // exact amount, is known to the mint and to Rust, never to Dart (no
    // protocol logic here). A send of the whole balance that cannot cover it
    // fails in Rust as `CashuSendFailed`, shown as "you may not have enough
    // funds", and nothing leaves the wallet.
    if (amount > widget.maxSats) {
      setState(() => _error = l10n.cashuErrorAmountTooLarge(widget.maxSats));
      return;
    }
    Navigator.of(context).pop(amount);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final book = OrderBookPalette.of(context);
    final pal = SettingsPalette.of(context);
    return MostroDialog(
      title: l10n.cashuSendButton,
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        style: TextStyle(
          fontFamily: AppFonts.figures,
          fontSize: 14,
          color: book.textPrimary,
        ),
        decoration: _fieldDecoration(
          book,
          pal,
          label: l10n.cashuAmountLabel,
          error: _error,
        ),
        onSubmitted: (_) => _submit(),
      ),
      secondary: ModalAction(
        label: l10n.cancel,
        onPressed: () => Navigator.of(context).pop(),
      ),
      primary: ModalAction(label: l10n.confirm, onPressed: _submit),
    );
  }
}

/// Whether [data] fits a QR at all. Runs the same encode `QrPainter` would,
/// because that is the only place the size limit is enforced.
bool _fitsInQr(String data) {
  try {
    QrImage(
      QrCode.fromData(data: data, errorCorrectLevel: QrErrorCorrectLevel.L),
    );
    return true;
  } on InputTooLongException {
    return false;
  }
}

/// The exported token, as a QR and as copyable text.
///
/// The token is bearer money: whoever redeems it first keeps it. The warning is
/// not decoration — a user who reads it as a receipt can lose the funds.
class _TokenDialog extends StatelessWidget {
  const _TokenDialog({required this.token});

  final String token;

  Future<void> _copy(BuildContext context, AppLocalizations l10n) async {
    await Clipboard.setData(ClipboardData(text: token));
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.cashuTokenCopied)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final book = OrderBookPalette.of(context);
    return MostroDialog(
      title: l10n.cashuTokenTitle,
      // MostroDialog scrolls its content and never asks it for intrinsic
      // dimensions, so `QrImageView` (laid out through a `LayoutBuilder`)
      // needs no fixed width here.
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // A cdk token carries a signature and DLEQ proof per proof, so
          // a wallet funded from many small proofs exports tens of KB —
          // far past the ~2.9 KB a version-40 QR holds. Checked *here*
          // rather than through `errorStateBuilder`: `QrCode.fromData`
          // silently caps at version 40 and only `make()` throws, inside
          // the painter, where the builder never sees it — so without
          // this qr_flutter paints its exception on the one dialog that
          // is showing the user their money.
          if (_fitsInQr(token))
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                // design-check: ignore DS-COL-1 — a QR code must be pure black on white to scan
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
              ),
              child: QrImageView(
                data: token,
                size: 200,
                padding: EdgeInsets.zero,
                // design-check: ignore DS-COL-1 — a QR code must be pure black on white to scan
                backgroundColor: Colors.white,
              ),
            )
          else
            Text(
              l10n.cashuTokenTooLargeForQr,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: book.textBody),
            ),
          const SizedBox(height: 12),
          SelectableText(
            token,
            style: TextStyle(fontSize: 11, color: book.textMuted),
          ),
          const SizedBox(height: 12),
          Text(
            l10n.cashuTokenWarning,
            style: TextStyle(fontSize: 12, color: book.textBody),
          ),
        ],
      ),
      secondary: ModalAction(
        label: l10n.cashuCopyToken,
        onPressed: () => _copy(context, l10n),
      ),
      primary: ModalAction(
        label: l10n.done,
        onPressed: () => Navigator.of(context).pop(),
      ),
    );
  }
}

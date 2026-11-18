import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:mostro/core/app_routes.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/core/settings_palette.dart';
import 'package:mostro/features/cashu/cashu_error_messages.dart';
import 'package:mostro/features/cashu/providers/cashu_wallet_provider.dart';
import 'package:mostro/features/order/widgets/invoice_clock.dart';
import 'package:mostro/features/settings/widgets/settings_section.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/utils/countdown.dart';
import 'package:mostro/shared/widgets/countdown_urgency_announcer.dart';
import 'package:mostro/shared/widgets/mostro_modal.dart';
import 'package:mostro/shared/widgets/mostro_qr.dart';
import 'package:mostro/shared/widgets/paste_field.dart';
import 'package:mostro/shared/widgets/platform_aware_qr_scanner.dart';
import 'package:mostro/shared/widgets/redesign_app_bar.dart';
import 'package:mostro/src/rust/api/types.dart';

/// The embedded Cashu wallet — phase C3 of `docs/cashu/README.md`.
///
/// Deliberately minimal: balance, redeem a token, export a token, pay a
/// Lightning invoice (C3b-1) or receive over one (C3b-2), each when the mint
/// can, and the mint it all happens at. It exists to fund and drain escrows,
/// not to be a general Cashu wallet. Holding several mints at once and backup
/// UX are later phases.
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

  /// Receive: a token, or — when the mint issues against Lightning — an
  /// invoice to pay from any Lightning wallet. Without that capability the
  /// choice is not offered and Receive goes straight to the token, as before.
  /// The choice is the same dialog as Send's, rows of equal weight
  /// (DS-CMP-2).
  Future<void> _receive(CashuWalletStatus? status) async {
    if (status?.canReceiveLightning ?? false) {
      final l10n = AppLocalizations.of(context);
      final kind = await _prompt(
        () => showMostroDialog<_ReceiveKind>(
          context: context,
          builder:
              (dialogContext) => MostroDialog(
                title: l10n.cashuReceiveButton,
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _KindRow(
                      icon: Icons.toll_outlined,
                      label: l10n.cashuReceiveTokenOption,
                      value: _ReceiveKind.token,
                    ),
                    _KindRow(
                      icon: Icons.bolt,
                      label: l10n.cashuReceiveLightningOption,
                      value: _ReceiveKind.lightning,
                    ),
                  ],
                ),
                secondary: ModalAction(
                  label: l10n.cancel,
                  onPressed: () => Navigator.of(dialogContext).pop(),
                ),
              ),
        ),
      );
      if (kind == null || !mounted) return;
      if (kind == _ReceiveKind.lightning) return _receiveLightning();
    }
    await _receiveToken();
  }

  Future<void> _receiveToken() async {
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

  /// Receive over Lightning: the amount, then the invoice, which stays on
  /// screen until it is paid, expires, or the user closes it. Closing loses
  /// nothing — the quote is stored, and a later payment is collected the
  /// next time the app opens — so the dialog only waits, it never holds the
  /// user.
  Future<void> _receiveLightning() async {
    final l10n = AppLocalizations.of(context);
    final amount = await _prompt(
      () => showMostroDialog<int>(
        context: context,
        builder: (_) => _AmountDialog(title: l10n.cashuMintAmountTitle),
      ),
    );
    if (amount == null || !mounted) return;

    await _run(() async {
      final controller = ref.read(cashuWalletControllerProvider);
      final quote = await controller.mintQuote(BigInt.from(amount));
      if (!mounted) return;
      await showMostroDialog<void>(
        context: context,
        // A stray tap must not hide the invoice the user is about to pay.
        barrierDismissible: false,
        builder:
            (_) => _MintInvoiceDialog(
              quote: quote,
              mintUrl: ref.read(cashuWalletProvider).valueOrNull?.mintUrl,
              claim: () => controller.claimMintQuote(quote.quoteId),
            ),
      );
    });
  }

  /// Send: ecash as a token, or — when the mint melts to Lightning — a
  /// Lightning payment. Without that capability the choice is not offered and
  /// Send goes straight to the token, as before.
  ///
  /// A dialog like every other one on this screen, with the two options as
  /// rows of equal weight rather than as a primary and a secondary button,
  /// which would read as "accept" and "cancel" (DS-CMP-2). Cancel is the way
  /// out, as in the Receive dialog.
  Future<void> _send(CashuWalletStatus status, int balanceSats) async {
    if (status.canSendLightning) {
      final l10n = AppLocalizations.of(context);
      final kind = await _prompt(
        () => showMostroDialog<_SendKind>(
          context: context,
          builder:
              (dialogContext) => MostroDialog(
                title: l10n.cashuSendButton,
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _KindRow(
                      icon: Icons.toll_outlined,
                      label: l10n.cashuSendEcashOption,
                      value: _SendKind.ecash,
                    ),
                    _KindRow(
                      icon: Icons.bolt,
                      label: l10n.cashuSendLightningOption,
                      value: _SendKind.lightning,
                    ),
                  ],
                ),
                secondary: ModalAction(
                  label: l10n.cancel,
                  onPressed: () => Navigator.of(dialogContext).pop(),
                ),
              ),
        ),
      );
      if (kind == null || !mounted) return;
      if (kind == _SendKind.lightning) return _sendLightning();
    }
    await _sendEcash(balanceSats);
  }

  Future<void> _sendEcash(int balanceSats) async {
    final amount = await _prompt(
      () => showMostroDialog<int>(
        context: context,
        builder:
            (_) => _AmountDialog(
              title: AppLocalizations.of(context).cashuSendButton,
              maxSats: balanceSats,
            ),
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

  /// Pay a Lightning invoice from the wallet: invoice, quote, confirmation,
  /// payment.
  ///
  /// Nothing is reserved while the confirmation is open — Rust prices the
  /// quote again when the user pays and refuses one that expired or now costs
  /// more than they confirmed. Those two refusals spent nothing, so the wallet
  /// asks for a fresh quote and shows it, once; it never pays a stale one.
  Future<void> _sendLightning() async {
    final invoice = await _prompt(
      () => showMostroDialog<String>(
        context: context,
        builder: (_) => const _InvoiceDialog(),
      ),
    );
    if (invoice == null || invoice.isEmpty || !mounted) return;

    await _run(() async {
      final controller = ref.read(cashuWalletControllerProvider);
      var quote = await controller.meltQuote(invoice);
      var refreshed = false;
      while (true) {
        if (!mounted) return;
        final current = quote;
        // The dialog stays open while the payment runs, its Pay button busy
        // (DS-CMP-2), and then shows how it ended — paid with its fee, still
        // in flight, or failed and why — until the user closes it. A payment
        // is money leaving the wallet: its outcome is not a passing snackbar.
        final exit = await showMostroDialog<_MeltStale>(
          context: context,
          barrierDismissible: false,
          builder:
              (_) => _MeltConfirmDialog(
                quote: current,
                refreshed: refreshed,
                pay:
                    () =>
                        controller.melt(current.quoteId, current.maxTotalSats),
              ),
        );
        if (exit == null || !mounted) return;
        // Refused before paying, nothing spent: show a fresh quote, once.
        if (refreshed) throw exit.error;
        refreshed = true;
        quote = await controller.meltQuote(invoice);
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
                  onPressed: _busy ? null : () => _receive(status),
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
                          : () => _send(status!, balance.toInt()),
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
                  // A wrap, not a row: in Spanish or German, or at large
                  // text, the second link goes under the first instead of
                  // overflowing a narrow phone.
                  Wrap(
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
          // Invoices known paid and not minted yet: the mint was down or
          // failed when asked. Money on its way, never part of the balance
          // until it is minted (C3b-2).
          if ((status?.receivingSats ?? BigInt.zero) > BigInt.zero) ...[
            const SizedBox(height: 4),
            Text(
              l10n.cashuReceivingSats(
                _fmtSats(
                  status!.receivingSats,
                  Localizations.localeOf(context).toString(),
                ),
              ),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: book.textBody,
              ),
            ),
          ],
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

/// What Send does with the ecash.
enum _SendKind { ecash, lightning }

/// How Receive brings ecash in.
enum _ReceiveKind { token, lightning }

/// One option of the Send or Receive dialog: its icon and name. The whole row
/// is the target, and tapping it is the choice, popping [value] — the same
/// rows as the chat's attach sheet.
class _KindRow<T> extends StatelessWidget {
  const _KindRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final T value;

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: Icon(icon, color: book.limeIcon),
      title: Text(
        label,
        style: TextStyle(fontWeight: FontWeight.w500, color: book.textPrimary),
      ),
      onTap: () => Navigator.of(context).pop(value),
    );
  }
}

/// The Lightning invoice to pay: the field, Paste and Scan QR as its links —
/// the same way in as the Receive dialog — then Cancel and Continue.
///
/// Only emptiness is checked here. Whether it is an invoice the wallet can pay
/// (amount, expiry, the mint's limits) is Rust's call, answered as a marker.
/// Pops the trimmed invoice; Continue stays disabled while the field is empty.
class _InvoiceDialog extends StatefulWidget {
  const _InvoiceDialog();

  @override
  State<_InvoiceDialog> createState() => _InvoiceDialogState();
}

class _InvoiceDialogState extends State<_InvoiceDialog> {
  final _controller = TextEditingController();
  String? _error;

  String get _invoice => _controller.text.trim();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

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

  /// A scanned invoice goes straight on to the quote: the confirmation that
  /// follows is where the user checks it, and nothing is paid before it.
  Future<void> _scan() async {
    final value =
        (await _scanQr(
          context,
          AppLocalizations.of(context).cashuInvoiceScanHint,
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
      title: l10n.cashuInvoiceDialogTitle,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.cashuInvoiceFieldLabel.toUpperCase(),
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
            // As in the Receive dialog: focused only where there is no camera.
            autofocus: !canScan,
            hint: l10n.cashuPasteInvoiceHint,
            errorText: _error,
            onChanged: (_) => setState(() => _error = null),
            onEditingComplete: () {
              if (_invoice.isNotEmpty) Navigator.of(context).pop(_invoice);
            },
          ),
        ],
      ),
      links: [
        ModalLink(label: l10n.pasteButtonLabel, onPressed: _paste),
        ModalLink(
          label: l10n.scanQrButtonLabel,
          onPressed: canScan ? _scan : null,
          tooltip: canScan ? null : l10n.qrScanUnavailable,
        ),
      ],
      secondary: ModalAction(
        label: l10n.cancel,
        onPressed: () => Navigator.of(context).pop(),
      ),
      primary: ModalAction(
        label: l10n.continueButtonLabel,
        onPressed:
            _invoice.isEmpty ? null : () => Navigator.of(context).pop(_invoice),
      ),
    );
  }
}

/// How long the payment dialog waits on Pay before it reports the payment as
/// pending — never closing the way out for good. Rust answers within its
/// `MELT_WAIT` (30 s, `rust/src/cashu/wallet.rs`) unless the mint holds the
/// request open, ignoring `respond-async`, which nothing below times out.
/// Above that wait, so a real answer is never cut short.
const _meltDialogWait = Duration(seconds: 40);

/// Why the payment dialog closed, when the caller has more to do: the quote
/// expired or now costs more than the user confirmed, so nothing was paid and
/// a fresh quote is due. Every other end — cancelled, or an outcome the user
/// has read — closes it with `null`.
final class _MeltStale {
  _MeltStale(this.error);

  final Object error;
}

/// True for the two refusals that spent nothing and only need a new quote.
bool _isStaleQuote(Object error) {
  final raw = error.toString();
  return raw.contains('CashuMeltQuoteExpired') ||
      raw.contains('CashuMeltFeeChanged');
}

/// The payment, from confirmation to outcome, in one dialog.
///
/// First what paying the invoice costs, before anything is spent: the
/// amount, the fees as an upper bound — routing reserve plus the mint's input
/// fees — and the most the balance can drop. "Up to", because the mint returns
/// the routing reserve it does not use.
///
/// Pay runs [pay] with the dialog still open and its button busy; while it
/// runs there is no way out — not Cancel, not the back gesture: closing would
/// not stop it. Then the same dialog shows how it ended, with Close as its
/// only button: paid, with the fee actually charged; still in flight; or
/// failed, with the reason. A stale quote pops [_MeltStale] instead. A
/// payment with no answer after [_meltDialogWait] shows as still in flight,
/// so the busy state always ends.
class _MeltConfirmDialog extends StatefulWidget {
  const _MeltConfirmDialog({
    required this.quote,
    required this.refreshed,
    required this.pay,
  });

  final CashuMeltQuote quote;

  /// Shown again with a fresh quote, after the first expired or went up.
  final bool refreshed;

  final Future<CashuMeltResult> Function() pay;

  @override
  State<_MeltConfirmDialog> createState() => _MeltConfirmDialogState();
}

class _MeltConfirmDialogState extends State<_MeltConfirmDialog> {
  bool _paying = false;
  CashuMeltResult? _result;
  Object? _failure;

  Future<void> _pay() async {
    setState(() => _paying = true);
    final payment = widget.pay();
    try {
      // Not cancelled on timeout — it cannot be, and the payment may still
      // settle: its late answer is dropped, and Rust broadcasts the balance
      // whenever it comes.
      final result = await payment.timeout(
        _meltDialogWait,
        onTimeout: () {
          payment.ignore();
          return const CashuMeltResult.pending();
        },
      );
      if (mounted) {
        setState(() {
          _paying = false;
          _result = result;
        });
      }
    } catch (e) {
      if (!mounted) return;
      if (_isStaleQuote(e)) {
        Navigator.of(context).pop(_MeltStale(e));
        return;
      }
      setState(() {
        _paying = false;
        _failure = e;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_paying,
      child: switch ((_result, _failure)) {
        (final result?, _) => _outcome(context, result),
        (_, final failure?) => _failed(context, failure),
        _ => _confirmation(context),
      },
    );
  }

  ModalAction _close(AppLocalizations l10n) => ModalAction(
    label: l10n.closeButtonLabel,
    onPressed: () => Navigator.of(context).pop(),
  );

  // The outcome replaces the confirmation in place, with no route change to
  // announce it, and how the payment ended is the one thing a screen-reader
  // user must hear: each outcome is a live region (DS-A11Y-2).
  Widget _outcome(BuildContext context, CashuMeltResult result) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toString();
    return switch (result) {
      CashuMeltResult_Paid(:final amountSats, :final feePaidSats) =>
        MostroDialog(
          icon: Icons.check_circle_rounded,
          title: l10n.cashuMeltPaidTitle(_fmtSats(amountSats, locale)),
          body: l10n.cashuMeltPaidFee(_fmtSats(feePaidSats, locale)),
          primary: _close(l10n),
          liveRegion: true,
        ),
      CashuMeltResult_Pending() => MostroDialog(
        icon: Icons.schedule_rounded,
        title: l10n.cashuMeltPendingTitle,
        body: l10n.cashuMeltPendingBody,
        primary: _close(l10n),
        liveRegion: true,
      ),
    };
  }

  Widget _failed(BuildContext context, Object failure) {
    final l10n = AppLocalizations.of(context);
    return MostroDialog(
      icon: Icons.error_outline_rounded,
      iconTone: ModalTone.destructive,
      title: l10n.cashuMeltFailedTitle,
      body: cashuErrorMessage(failure, l10n),
      primary: _close(l10n),
      liveRegion: true,
    );
  }

  Widget _confirmation(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final book = OrderBookPalette.of(context);
    final locale = Localizations.localeOf(context).toString();
    final quote = widget.quote;
    String sats(BigInt value) =>
        '${_fmtSats(value, locale)} ${l10n.aboutSatoshisSuffix}';
    return MostroDialog(
      title: l10n.cashuMeltConfirmTitle,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.refreshed) ...[
            Text(
              l10n.cashuMeltQuoteRefreshed,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: book.textBody,
              ),
            ),
            const SizedBox(height: 12),
          ],
          _MeltRow(label: l10n.cashuMeltAmount, value: sats(quote.amountSats)),
          _MeltRow(
            label: l10n.cashuMeltFees,
            value: sats(quote.feeReserveSats + quote.inputFeeSats),
          ),
          Divider(color: book.border),
          _MeltRow(
            label: l10n.cashuMeltTotal,
            value: sats(quote.maxTotalSats),
            emphasise: true,
          ),
          const SizedBox(height: 12),
          Text(
            l10n.cashuMeltFeesNote,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: book.textMuted,
            ),
          ),
        ],
      ),
      secondary: ModalAction(
        label: l10n.cancel,
        onPressed: _paying ? null : () => Navigator.of(context).pop(),
      ),
      primary: ModalAction(
        label: l10n.cashuPayButton,
        onPressed: _paying ? null : _pay,
        busy: _paying,
      ),
    );
  }
}

/// How often the invoice dialog asks whether its invoice was paid. Rust skips
/// a round the collector or a connect is already doing, so a tick can come
/// back `Waiting` without the mint being asked.
const _mintPollEvery = Duration(seconds: 3);

/// The invoice that funds the wallet, from creation to outcome, in one dialog.
///
/// First the QR, the amount, the mint and the time left to pay it
/// (DS-CMP-21), while [claim] is
/// polled every [_mintPollEvery]. The same dialog then shows how it ended —
/// received, expired unpaid, or failed with the reason — with Close as its
/// only button. Closing early loses nothing: the quote is stored, and a later
/// payment is collected the next time the app opens, which the dialog says.
class _MintInvoiceDialog extends StatefulWidget {
  const _MintInvoiceDialog({
    required this.quote,
    required this.mintUrl,
    required this.claim,
  });

  final CashuMintQuote quote;

  /// The mint the invoice is from, when known.
  final String? mintUrl;

  final Future<CashuMintQuoteState> Function() claim;

  @override
  State<_MintInvoiceDialog> createState() => _MintInvoiceDialogState();
}

class _MintInvoiceDialogState extends State<_MintInvoiceDialog>
    with InvoiceClock {
  Timer? _poll;

  /// The invoice's whole lifetime, as seen when it was shown: it sets when the
  /// countdown turns urgent.
  Duration? _window;

  /// A check is running: the next tick waits for it rather than stack one.
  bool _checking = false;

  CashuMintQuoteState? _ended;
  Object? _failure;

  @override
  void initState() {
    super.initState();
    final expiresAt = widget.quote.expiresAt.toInt();
    if (expiresAt > 0) {
      // The clock [InvoiceClock] counts with, or the two disagree.
      final now = clock.now().millisecondsSinceEpoch ~/ 1000;
      _window = Duration(seconds: expiresAt > now ? expiresAt - now : 0);
      trackInvoiceDeadline(expiresAt);
    }
    _poll = Timer.periodic(_mintPollEvery, (_) => _check());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _check() async {
    if (_checking) return;
    _checking = true;
    try {
      final state = await widget.claim();
      if (!mounted || state is CashuMintQuoteState_Waiting) return;
      _poll?.cancel();
      setState(() => _ended = state);
    } catch (e) {
      if (!mounted) return;
      _poll?.cancel();
      setState(() => _failure = e);
    } finally {
      _checking = false;
    }
  }

  Future<void> _copy(AppLocalizations l10n) async {
    await Clipboard.setData(ClipboardData(text: widget.quote.invoice));
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.invoiceCopied)));
    }
  }

  ModalAction _close(AppLocalizations l10n) => ModalAction(
    label: l10n.closeButtonLabel,
    onPressed: () => Navigator.of(context).pop(),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toString();
    // Each outcome replaces the invoice in place, with no route change to
    // announce it: a live region, as for a payment (DS-A11Y-2).
    return switch ((_ended, _failure)) {
      (CashuMintQuoteState_Issued(:final amountSats), _) => MostroDialog(
        icon: Icons.check_circle_rounded,
        title: l10n.cashuMintReceivedTitle(_fmtSats(amountSats, locale)),
        primary: _close(l10n),
        liveRegion: true,
      ),
      (CashuMintQuoteState_Expired(), _) => MostroDialog(
        icon: Icons.timer_off_outlined,
        title: l10n.cashuMintExpiredTitle,
        body: l10n.cashuMintExpiredBody,
        primary: _close(l10n),
        liveRegion: true,
      ),
      (_, final failure?) => MostroDialog(
        icon: Icons.error_outline_rounded,
        iconTone: ModalTone.destructive,
        title: l10n.cashuMintFailedTitle,
        body: cashuErrorMessage(failure, l10n),
        primary: _close(l10n),
        liveRegion: true,
      ),
      _ => _invoice(context, l10n, locale),
    };
  }

  Widget _invoice(BuildContext context, AppLocalizations l10n, String locale) {
    final book = OrderBookPalette.of(context);
    final quote = widget.quote;
    final mintUrl = widget.mintUrl;
    return MostroDialog(
      title: l10n.cashuMintInvoiceTitle,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // No logo: the invoice belongs to the mint, not to a node (#851).
          // Checked before drawing, as for a token: the mint writes the
          // invoice, and one past a QR's capacity must still be payable.
          if (MostroQr.fits(quote.invoice))
            Center(child: MostroQr(data: quote.invoice))
          else ...[
            Text(
              l10n.cashuInvoiceTooLargeForQr,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: book.textBody),
            ),
            const SizedBox(height: 8),
            SelectableText(
              quote.invoice,
              style: TextStyle(fontSize: 11, color: book.textMuted),
            ),
          ],
          const SizedBox(height: 12),
          _MeltRow(
            label: l10n.cashuMeltAmount,
            value:
                '${_fmtSats(quote.amountSats, locale)} '
                '${l10n.aboutSatoshisSuffix}',
          ),
          if (mintUrl != null)
            _MeltRow(label: l10n.cashuMintDialogTitle, value: mintUrl),
          // Gone once it runs out, not left at 00:00: whether it expired
          // unpaid is the mint's to say, after a grace (C3b-2), and a device
          // clock ahead of the mint's runs out early. Until the mint says so
          // the invoice is only waiting, which the row below says.
          ValueListenableBuilder<Duration?>(
            valueListenable: invoiceRemaining,
            builder:
                (context, remaining, _) =>
                    remaining == null || remaining == Duration.zero
                        ? const SizedBox.shrink()
                        : _CountdownRow(remaining: remaining, window: _window),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              // A looping spinner stops with the system's reduced motion
              // (DS-MOT-3): a still clock says the same.
              if (MediaQuery.disableAnimationsOf(context))
                Icon(Icons.schedule_rounded, size: 14, color: book.limeIcon)
              else
                SizedBox.square(
                  dimension: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: book.limeIcon,
                  ),
                ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.cashuMintInvoiceWaiting,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: book.textBody,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            l10n.cashuMintInvoiceNote,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: book.textMuted,
            ),
          ),
        ],
      ),
      // Copy is the answer while it waits: whoever pays from another app on
      // this phone needs the invoice. Closing is the way out, and costs
      // nothing (DS-CMP-2). Each outcome has Close alone.
      secondary: _close(l10n),
      primary: ModalAction(
        label: l10n.cashuCopyToken,
        onPressed: () => _copy(l10n),
      ),
    );
  }
}

/// The time left to pay an invoice, labelled and toned like every countdown
/// of the app (DS-CMP-21): lime while there is time, since paying it is the
/// user's turn; amber under an hour; coral in the last minute of a window
/// this short. Turning urgent is announced once; the figure never is.
class _CountdownRow extends StatelessWidget {
  const _CountdownRow({required this.remaining, required this.window});

  final Duration remaining;
  final Duration? window;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final book = OrderBookPalette.of(context);
    final pal = SettingsPalette.of(context);
    final tone = countdownTone(remaining, window: window);
    final figure = formatCountdown(
      remaining,
      hours: l10n.invoiceCountdownHours,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        spacing: 12,
        children: [
          Text(
            l10n.countdownExpiresInLabel,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: book.textBody,
            ),
          ),
          CountdownUrgencyAnnouncer(
            urgent: tone == CountdownTone.urgent,
            message: '${l10n.countdownExpiresInLabel} $figure',
            child: Text(
              figure,
              style: TextStyle(
                fontFamily: AppFonts.figures,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: switch (tone) {
                  CountdownTone.calm => book.limeIcon,
                  CountdownTone.warning => book.yellowInk,
                  CountdownTone.urgent => pal.danger,
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One line of the payment confirmation: label, then the figure — on the
/// next line when both do not fit (a narrow phone, large text, German).
class _MeltRow extends StatelessWidget {
  const _MeltRow({
    required this.label,
    required this.value,
    this.emphasise = false,
  });

  final String label;
  final String value;
  final bool emphasise;

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    final weight = emphasise ? FontWeight.w600 : FontWeight.w500;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        spacing: 12,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: weight,
              color: book.textBody,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontFamily: AppFonts.figures,
              fontSize: 14,
              fontWeight: weight,
              color: book.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

/// How much to export, or to receive over Lightning. An export is bounded by
/// the balance: a send larger than the wallet holds fails at the mint with a
/// far less obvious message. A receive has no bound here: the mint's limits
/// are Rust's to check, answered as a marker.
class _AmountDialog extends StatefulWidget {
  const _AmountDialog({required this.title, this.maxSats});

  final String title;

  /// The most that can be asked for; `null` for no bound.
  final int? maxSats;

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
    final maxSats = widget.maxSats;
    if (maxSats != null && amount > maxSats) {
      setState(() => _error = l10n.cashuErrorAmountTooLarge(maxSats));
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
      title: widget.title,
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
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // A cdk token carries a signature and DLEQ proof per proof, so
          // a wallet funded from many small proofs exports tens of KB —
          // far past the ~2.9 KB a version-40 QR holds. Checked before
          // drawing, so the one dialog showing the user their money never
          // paints an encoder's exception.
          //
          // No logo: the token belongs to no node (#851), and a cleared
          // centre would cost the capacity the biggest tokens need.
          if (MostroQr.fits(token))
            MostroQr(data: token)
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

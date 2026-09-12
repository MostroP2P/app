import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:mostro/core/app_routes.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/cashu/cashu_error_messages.dart';
import 'package:mostro/features/cashu/providers/cashu_wallet_provider.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/widgets/platform_aware_qr_scanner.dart';
import 'package:mostro/src/rust/api/types.dart';

/// The embedded Cashu wallet — phase C3 of `docs/cashu/README.md`.
///
/// Deliberately minimal: balance, redeem a token, export a token. It exists to
/// fund and drain escrows against the node's mint, not to be a general Cashu
/// wallet. Melt/mint to Lightning, multiple mints and backup UX are later
/// phases.
///
/// Reachable only when the active node runs Cashu — the Settings entry point is
/// gated, and every Rust call behind it refuses on a Lightning node anyway, so
/// a deep link here shows the disconnected state rather than doing anything.
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

  @override
  void initState() {
    super.initState();
    // Connecting is lazy and idempotent; doing it here means the balance is
    // real by the time the user reads it, rather than after they tap something.
    WidgetsBinding.instance.addPostFrameCallback((_) => _connect());
  }

  Future<void> _connect() async {
    try {
      await ref.read(cashuWalletControllerProvider).connect();
    } catch (e) {
      if (mounted) _showError(e);
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
      () => showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        builder:
            (sheetContext) => Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
              ),
              child: PlatformAwareQrScanner(
                hint: l10n.cashuReceiveHint,
                onDetected: (value) => Navigator.of(sheetContext).pop(value),
              ),
            ),
      ),
    );

    if (token == null || token.trim().isEmpty || !mounted) return;

    await _run(() async {
      final amount = await ref
          .read(cashuWalletControllerProvider)
          .receiveToken(token.trim());
      if (mounted) _showMessage(l10n.cashuReceived(amount.toInt()));
    });
  }

  Future<void> _send(int balanceSats) async {
    final amount = await _prompt(
      () => showDialog<int>(
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
    return showDialog<void>(
      context: context,
      // Not dismissible: closing this by tapping outside used to be the fastest
      // way to lose an exported token. `barrierDismissible` covers the tap;
      // `PopScope` covers the Android back gesture, which it does not.
      barrierDismissible: false,
      builder:
          (_) => PopScope(canPop: false, child: _TokenDialog(token: token)),
    );
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
    final colors = Theme.of(context).extension<AppColors>()!;
    final status = ref.watch(cashuWalletProvider).valueOrNull;
    // `null` here means "not read yet or unreadable", which is not the same as
    // an empty wallet — see CashuWalletStatus.balance_sats.
    final balance = status?.balanceSats;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.cashuWalletTitle),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed:
              () =>
                  context.canPop()
                      ? context.pop()
                      : context.go(AppRoute.settings),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          _BalanceCard(status: status, colors: colors),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _busy ? null : _receive,
                  icon: const Icon(Icons.qr_code_scanner),
                  label: Text(l10n.cashuReceiveButton),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
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
                  icon: const Icon(Icons.upload_outlined),
                  label: Text(l10n.cashuSendButton),
                ),
              ),
            ],
          ),
          if (_lastToken != null) ...[
            const SizedBox(height: AppSpacing.lg),
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: colors.backgroundCard,
                borderRadius: BorderRadius.circular(AppRadius.card),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.cashuLastTokenPending,
                    style: TextStyle(color: colors.textSubtle, fontSize: 13),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () => _showToken(_lastToken!),
                        child: Text(l10n.cashuShowLastToken),
                      ),
                      TextButton(
                        onPressed: () => setState(() => _lastToken = null),
                        child: Text(l10n.cashuLastTokenDone),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          TextButton.icon(
            onPressed: _busy ? null : _sync,
            icon: const Icon(Icons.refresh),
            label: Text(l10n.cashuSyncButton),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            l10n.cashuWalletExplanation,
            style: TextStyle(color: colors.textSubtle, fontSize: 13),
          ),
        ],
      ),
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

/// Balance, mint, and — when the wallet could not bind — that it did not.
class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.status, required this.colors});

  final CashuWalletStatus? status;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final connected = status?.connected ?? false;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: colors.backgroundCard,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.cashuBalanceLabel,
            style: TextStyle(color: colors.textSecondary, fontSize: 14),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            // An unreadable balance renders as "—", never as a number. Showing
            // "0 Satoshis" for a failed read is the one thing a bearer-money
            // wallet must not do.
            status?.balanceSats == null
                ? '—'
                : '${_fmtSats(status!.balanceSats!, Localizations.localeOf(context).toString())} ${l10n.aboutSatoshisSuffix}',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: AppSpacing.md),
          if (!connected)
            Text(
              l10n.cashuNotConnected,
              style: TextStyle(color: colors.destructiveRed, fontSize: 13),
            )
          // Rust always names the mint when connected; guarded anyway so a
          // future status without one renders nothing rather than "Mint: ".
          else if (status?.mintUrl case final mintUrl?)
            Text(
              l10n.cashuMintLabel(mintUrl),
              style: TextStyle(color: colors.textSubtle, fontSize: 13),
            ),
        ],
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
    if (amount > widget.maxSats) {
      setState(() => _error = l10n.cashuErrorAmountTooLarge(widget.maxSats));
      return;
    }
    Navigator.of(context).pop(amount);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.cashuSendButton),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(
          labelText: l10n.cashuAmountLabel,
          errorText: _error,
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(onPressed: _submit, child: Text(l10n.confirm)),
      ],
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.cashuTokenTitle),
      // Bounded width on purpose: `QrImageView` lays out through a
      // `LayoutBuilder`, and `AlertDialog` asks its content for intrinsic
      // dimensions — which a LayoutBuilder cannot answer. Without this the
      // dialog throws on a narrow screen.
      content: SizedBox(
        width: 280,
        child: SingleChildScrollView(
          child: Column(
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
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  color: Colors.white,
                  child: QrImageView(
                    data: token,
                    size: 200,
                    backgroundColor: Colors.white,
                  ),
                )
              else
                Text(
                  l10n.cashuTokenTooLargeForQr,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13),
                ),
              const SizedBox(height: AppSpacing.md),
              SelectableText(token, style: const TextStyle(fontSize: 11)),
              const SizedBox(height: AppSpacing.md),
              Text(
                l10n.cashuTokenWarning,
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: token));
            if (context.mounted) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text(l10n.cashuTokenCopied)));
            }
          },
          child: Text(l10n.cashuCopyToken),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.done),
        ),
      ],
    );
  }
}

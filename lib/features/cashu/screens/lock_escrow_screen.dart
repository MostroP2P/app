import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:mostro/core/app_routes.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/core/settings_palette.dart';
import 'package:mostro/features/cashu/cashu_error_messages.dart';
import 'package:mostro/features/cashu/providers/cashu_wallet_provider.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/widgets/redesign_app_bar.dart';
import 'package:mostro/src/rust/api/types.dart';

/// Seller-side escrow funding — phase C5 of `docs/cashu/README.md`.
///
/// The Cashu sibling of `pay_lightning_invoice_screen.dart`: instead of paying
/// a hold invoice, the seller locks a 2-of-3 token at the node's mint and
/// submits it. Same place in the flow, same finality.
///
/// Everything is shown before the seller commits. Once an escrow is locked and
/// recorded, the screen only ever offers to re-send that same token: the core
/// knows (`CashuEscrowQuote.pendingSubmission`), so a retry never swaps twice.
class LockEscrowScreen extends ConsumerStatefulWidget {
  const LockEscrowScreen({super.key, required this.orderId});

  final String orderId;

  @override
  ConsumerState<LockEscrowScreen> createState() => _LockEscrowScreenState();
}

class _LockEscrowScreenState extends ConsumerState<LockEscrowScreen> {
  CashuEscrowQuote? _quote;
  String? _error;
  bool _locking = false;

  /// The latest quote request. Loads overlap — a balance change and the
  /// return from the funding route can both start one — and only the newest
  /// may land, or an older, lower balance would bring "fund your wallet" back.
  int _quoteRequest = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadQuote());
  }

  /// [clearError] once the reason for the last error may be gone — funds
  /// arrived — but not after a failed lock, whose message must stay visible
  /// next to the re-send it leads to.
  Future<void> _loadQuote({bool clearError = false}) async {
    final request = ++_quoteRequest;
    if (clearError) setState(() => _error = null);
    try {
      // No connect here: the quote connects the wallet itself when it needs
      // the balance, and a recorded escrow is quoted without the wallet at
      // all — so an unreachable wallet mint never blocks its re-send.
      final quote =
          await ref.read(cashuEscrowControllerProvider).quote(widget.orderId);
      if (mounted && request == _quoteRequest) setState(() => _quote = quote);
    } catch (e) {
      if (mounted && request == _quoteRequest) {
        setState(() => _error = e.toString());
      }
    }
  }

  Future<void> _lock() async {
    if (_locking) return;
    setState(() => _locking = true);
    final l10n = AppLocalizations.of(context);
    try {
      await ref.read(cashuEscrowControllerProvider).lock(widget.orderId);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.lockEscrowSubmitted)));
      context.go(AppRoute.tradeDetailPath(widget.orderId));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _locking = false;
        _error = e.toString();
      });
      // Whether an escrow is now recorded — and the button must re-send it —
      // is the core's to say, not a guess from the error.
      await _loadQuote();
    }
  }

  /// Funding happens on the wallet screen. Coming back must show the new
  /// balance, or the only way forward stays "fund your wallet".
  Future<void> _fundWallet() async {
    await context.push(AppRoute.cashuWallet);
    if (mounted) await _loadQuote(clearError: true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final book = OrderBookPalette.of(context);
    final pal = SettingsPalette.of(context);
    final quote = _quote;
    final pending = quote?.pendingSubmission ?? false;
    // A recorded escrow re-sends without touching the balance.
    final short =
        quote != null && !pending && quote.balanceSats < quote.totalSats;

    // Ecash can also arrive while this screen is open (a paste on another
    // screen, a sync): a balance change re-reads the quote.
    ref.listen(cashuWalletProvider, (previous, next) {
      final before = previous?.valueOrNull?.balanceSats;
      final after = next.valueOrNull?.balanceSats;
      if (after != null && after != before && !_locking) {
        _loadQuote(clearError: true);
      }
    });

    return Scaffold(
      backgroundColor: book.bg,
      appBar: redesignAppBar(
        context,
        title: l10n.lockEscrowTitle,
        onBack: () => context.canPop()
            ? context.pop()
            : context.go(AppRoute.tradeDetailPath(widget.orderId)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          Text(
            l10n.lockEscrowExplanation,
            style: TextStyle(fontSize: 14, color: book.textBody),
          ),
          const SizedBox(height: AppSpacing.lg),
          if (quote == null && _error == null)
            const Center(child: CircularProgressIndicator())
          else if (quote != null) ...[
            _Row(label: l10n.lockEscrowAmount, value: '${quote.amountSats}'),
            // No fee token until the daemon collects one (TA-1f).
            if (quote.feeSats > BigInt.zero)
              _Row(label: l10n.lockEscrowFee, value: '${quote.feeSats}'),
            const Divider(),
            _Row(
              label: l10n.lockEscrowTotal,
              value: '${quote.totalSats}',
              emphasise: true,
            ),
            _Row(label: l10n.lockEscrowBalance, value: '${quote.balanceSats}'),
            const SizedBox(height: AppSpacing.md),
            Text(
              l10n.lockEscrowMint(quote.mintUrl),
              style: TextStyle(color: book.textMuted, fontSize: 13),
            ),
            Text(
              l10n.lockEscrowLocktime(quote.locktimeDays),
              style: TextStyle(color: book.textMuted, fontSize: 13),
            ),
          ],
          if (pending) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              l10n.lockEscrowPendingSubmission,
              style: TextStyle(color: book.textMuted, fontSize: 13),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              cashuErrorMessage(_error!, l10n),
              style: TextStyle(fontSize: 14, color: pal.danger),
            ),
          ],
          const SizedBox(height: AppSpacing.xl),
          if (short)
            OutlinedButton.icon(
              onPressed: _fundWallet,
              style: OutlinedButton.styleFrom(
                foregroundColor: book.textBody,
                backgroundColor: pal.buttonFill,
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
              ),
              icon: const Icon(Icons.account_balance_wallet_outlined),
              label: Text(l10n.lockEscrowFundWallet),
            )
          else
            FilledButton(
              onPressed: quote == null || _locking ? null : _lock,
              style: FilledButton.styleFrom(
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
              ),
              child: _locking
                  ? SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: book.onLime,
                      ),
                    )
                  : Text(pending
                      ? l10n.lockEscrowRetry
                      : l10n.lockEscrowConfirm),
            ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.label,
    required this.value,
    this.emphasise = false,
  });

  final String label;
  final String value;
  final bool emphasise;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final style = emphasise
        ? const TextStyle(fontWeight: FontWeight.w600)
        : const TextStyle();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          Text('$value ${l10n.aboutSatoshisSuffix}', style: style),
        ],
      ),
    );
  }
}

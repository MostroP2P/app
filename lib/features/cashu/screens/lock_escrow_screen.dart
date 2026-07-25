import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:mostro/core/app_routes.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/cashu/cashu_error_messages.dart';
import 'package:mostro/features/cashu/providers/cashu_wallet_provider.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/src/rust/api/types.dart';

/// Seller-side escrow funding — phase C5 of `docs/cashu/README.md`.
///
/// The Cashu sibling of `pay_lightning_invoice_screen.dart`: instead of paying
/// a hold invoice, the seller locks a 2-of-3 token at the node's mint and
/// submits it. Same place in the flow, same finality.
///
/// Everything is shown before the seller commits, because the numbers are not
/// obvious: the escrow is the order amount, the fee is a *separate* token worth
/// the whole Mostro fee, and both leave the wallet at once.
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

  /// True once a lock attempt has swapped funds at the mint but the submission
  /// may not have reached the node.
  ///
  /// The token is persisted before the publish result is checked, and the
  /// daemon's handler is idempotent on a re-submission — so retrying is both
  /// safe and the only way out of a lost publish. Without this the seller is
  /// left with locked funds and a trade that looks stuck.
  bool _needsRetry = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadQuote());
  }

  Future<void> _loadQuote() async {
    try {
      // Connect first: the quote reports the balance, and an unconnected wallet
      // reports zero — which would send the seller off to fund a wallet that is
      // not actually empty.
      await ref.read(cashuWalletControllerProvider).connect();
      final quote =
          await ref.read(cashuEscrowControllerProvider).quote(widget.orderId);
      if (mounted) setState(() => _quote = quote);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
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
      if (mounted) {
        setState(() {
          _locking = false;
          _error = e.toString();
          // Anything past the mint swap leaves a token behind. The markers
          // below are raised *before* it, so those are clean failures.
          _needsRetry = !_isPreLockFailure(e.toString());
        });
      }
    }
  }

  /// Failures raised before any funds move, so there is nothing to retry.
  bool _isPreLockFailure(String raw) => const [
        'CashuInsufficientFunds',
        'CashuNodeFeeUnknown',
        'CashuEscrowRequestMissing',
        'CashuWrongTradeKey',
        'CashuNotEnabled',
        'CashuNotConnected',
        'NotTheSeller',
        'DeviceClockInvalid',
        'InvalidEscrowParties',
      ].any(raw.contains);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = Theme.of(context).extension<AppColors>()!;
    final quote = _quote;
    final short = quote != null && quote.balanceSats < quote.totalSats;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.lockEscrowTitle),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.canPop()
              ? context.pop()
              : context.go(AppRoute.tradeDetailPath(widget.orderId)),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          Text(
            l10n.lockEscrowExplanation,
            style: TextStyle(color: colors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.lg),
          if (quote == null && _error == null)
            const Center(child: CircularProgressIndicator())
          else if (quote != null) ...[
            _Row(label: l10n.lockEscrowAmount, value: '${quote.amountSats}'),
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
              style: TextStyle(color: colors.textSubtle, fontSize: 13),
            ),
            Text(
              l10n.lockEscrowLocktime(quote.locktimeDays),
              style: TextStyle(color: colors.textSubtle, fontSize: 13),
            ),
          ],
          if (_needsRetry) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              l10n.lockEscrowPendingSubmission,
              style: TextStyle(color: colors.textSubtle, fontSize: 13),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              cashuErrorMessage(_error!, l10n),
              style: TextStyle(color: colors.destructiveRed),
            ),
          ],
          const SizedBox(height: AppSpacing.xl),
          if (short)
            OutlinedButton.icon(
              onPressed: () => context.push(AppRoute.cashuWallet),
              icon: const Icon(Icons.account_balance_wallet_outlined),
              label: Text(l10n.lockEscrowFundWallet),
            )
          else
            FilledButton(
              onPressed: quote == null || _locking ? null : _lock,
              child: _locking
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(_needsRetry
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

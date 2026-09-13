import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mostro/features/order/models/bond_rules.dart';
import 'package:mostro/src/rust/api/bond.dart' as bond_api;
import 'package:mostro/src/rust/api/orders.dart' as orders_api;
import 'package:mostro/src/rust/api/types.dart'
    show BondClaim, BondClaimUpdate, TradeInfo;

const kBondExplainerOpenKey = 'bond_explainer_open';

/// Whether the pay-bond screen's "why Mostro asks for a deposit" accordion
/// is open. Open the first time, then whatever the user last left it at,
/// remembered across orders (handoff 14, implementation notes).
class BondExplainerNotifier extends Notifier<bool> {
  BondExplainerNotifier({Future<SharedPreferences> Function()? prefs})
    : _prefs = prefs ?? SharedPreferences.getInstance;

  final Future<SharedPreferences> Function() _prefs;

  /// Set once the user changed the state: a stored value that lands later
  /// must not undo that choice.
  bool _touched = false;

  @override
  bool build() {
    _touched = false;
    _load();
    return true;
  }

  Future<void> _load() async {
    try {
      final prefs = await _prefs();
      if (_touched) return;
      state = bondExplainerOpens(stored: prefs.getBool(kBondExplainerOpenKey));
    } catch (_) {
      // No durable preference: the default stands.
    }
  }

  Future<void> set(bool open) async {
    _touched = true;
    state = open;
    try {
      final prefs = await _prefs();
      await prefs.setBool(kBondExplainerOpenKey, open);
    } catch (_) {
      // Remembered for this session at least.
    }
  }

  Future<void> toggle() => set(!state);
}

final bondExplainerOpenProvider = NotifierProvider<BondExplainerNotifier, bool>(
  BondExplainerNotifier.new,
);

/// The same-take re-request behind a seam (docs/ANTI_ABUSE_BOND.md §9): a
/// row restored without its bolt11 asks the daemon for it again.
final requestBondInvoiceAgainProvider = Provider<
  Future<TradeInfo> Function(String orderId)
>((ref) => (orderId) => orders_api.requestBondInvoiceAgain(orderId: orderId));

/// A maker's way out of the bond window behind a seam
/// (docs/ANTI_ABUSE_BOND.md §6.2): the local wipe of an order the daemon
/// never published.
final abandonBondedOrderProvider =
    Provider<Future<void> Function(String orderId)>(
      (ref) => (orderId) => bond_api.abandonBondedOrder(orderId: orderId),
    );

/// The core's on-demand expiry of one bond window (what its periodic sweep
/// would do next): called when the pay-bond countdown ends so the row does
/// not linger as "pay deposit" in the lists.
final closeExpiredBondWindowProvider =
    Provider<Future<bool> Function(String orderId)>(
      (ref) => (orderId) => bond_api.closeExpiredBondWindow(orderId: orderId),
    );

/// The core's estimate of the bond the active node would ask for an order of
/// [sats] (`max(pct × amount, floor)`, docs/ANTI_ABUSE_BOND.md §3.4), or null
/// when the node's policy is unknown or not enabled. A warning figure only:
/// the daemon sends the exact bolt11.
final bondEstimateProvider = FutureProvider.autoDispose.family<int?, int>((
  ref,
  sats,
) async {
  final estimate = await bond_api.estimateBondSats(
    orderAmountSats: BigInt.from(sats),
  );
  return estimate?.toInt();
});

// ── Payout claims (docs/ANTI_ABUSE_BOND.md §6.4) ─────────────────────────────

/// Claim phase changes pushed by the core (new claim, submission, ack,
/// payout, expiry). Screens filter by `orderId`.
final bondClaimUpdatesProvider = StreamProvider.autoDispose<BondClaimUpdate>((
  ref,
) async* {
  final stream = await bond_api.onBondClaimUpdated();
  while (true) {
    yield await stream.next();
  }
});

/// The claim for one order, re-read on every claim update for it.
final bondClaimProvider = FutureProvider.autoDispose.family<BondClaim?, String>(
  (ref, orderId) async {
    ref.listen(bondClaimUpdatesProvider, (_, next) {
      if (next.valueOrNull?.orderId == orderId) ref.invalidateSelf();
    });
    return bond_api.getBondClaim(orderId: orderId);
  },
);

/// Every claim, most recently changed first.
final bondClaimsProvider = FutureProvider.autoDispose<List<BondClaim>>((
  ref,
) async {
  ref.listen(bondClaimUpdatesProvider, (_, _) => ref.invalidateSelf());
  return bond_api.listBondClaims();
});

/// The submission behind a seam: publish the bolt11 for a claim's share to
/// the node that issued it.
final submitBondPayoutInvoiceProvider =
    Provider<Future<void> Function(String orderId, String invoice)>(
      (ref) =>
          (orderId, invoice) => bond_api.submitBondPayoutInvoice(
            orderId: orderId,
            invoice: invoice,
          ),
    );

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mostro/features/order/models/bond_rules.dart';
import 'package:mostro/src/rust/api/orders.dart' as orders_api;
import 'package:mostro/src/rust/api/types.dart' show TradeInfo;

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

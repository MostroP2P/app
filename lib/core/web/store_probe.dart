/// Store read-back signal for the headless web smoke test.
///
/// The bridge probe proves a Rust call returned; it says nothing about the
/// persistent store. On web that store is IndexedDB, and the bond rows in it
/// (payout claims, trades parked at `WaitingTakerBond` / `WaitingMakerBond`)
/// only ever reach the UI after a serde decode in the wasm core and an FRB
/// decode in Dart. A release build that breaks either one shows an empty My
/// Trades and nothing else. So with `SMOKE_BOND_STORE=1` the smoke test seeds
/// those rows, reloads, and compares them with what this publishes
/// (docs/ANTI_ABUSE_BOND.md T5.1).
///
/// Only on request: the smoke test sets `mostroStoreProbeRequested` before the
/// page loads. The shipped bundle stays the one under test, but a production
/// launch neither decodes every row for nothing nor leaves the user's bond
/// rows on `window`.
library;

import 'dart:convert';

import 'package:mostro/core/web/store_probe_signal.dart';
import 'package:mostro/src/rust/api/bond.dart' as bond_api;
import 'package:mostro/src/rust/api/orders.dart' as orders_api;

export 'package:mostro/core/web/store_probe_signal.dart'
    show storeProbeRequested;

/// Reads every claim and every trade that carries a bond, and publishes a
/// summary of them to the page. A no-op off web, where the publish is a stub;
/// callers skip it there so the reads are not made for nothing.
Future<void> publishStoreProbe() async {
  try {
    final claims = await bond_api.listBondClaims();
    final trades = await orders_api.listTrades();
    markStoreProbe(
      jsonEncode({
        'claims': [
          for (final claim in claims)
            {'orderId': claim.orderId, 'phase': claim.phase.name},
        ],
        'trades': [
          for (final trade in trades)
            if (trade.bond != null)
              {
                'id': trade.id,
                'status': trade.order.status.name,
                'bondState': trade.bond!.state.name,
              },
        ],
      }),
    );
  } catch (e) {
    markStoreProbeFailed(e);
  }
}

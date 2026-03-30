import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ── TradeStatusFilter ─────────────────────────────────────────────────────────

/// Possible values for the My Trades status filter dropdown.
enum TradeStatusFilter {
  all('All'),
  pending('Pending'),
  active('Active'),
  fiatSent('Fiat Sent'),
  success('Success'),
  canceled('Canceled'),
  dispute('Dispute');

  const TradeStatusFilter(this.label);
  final String label;
}

// ── TradeRole ─────────────────────────────────────────────────────────────────

/// Whether the local user created this trade or took it.
enum TradeRole { creator, taker }

// ── TradeListItem model ───────────────────────────────────────────────────────

/// Immutable UI-layer model for one trade row in the My Trades list.
///
/// Populated from the Rust bridge trade session once FFI bindings are wired.
/// For now the list is empty; mock data can be added in tests.
@immutable
class TradeListItem {
  const TradeListItem({
    required this.orderId,
    required this.isSelling,
    required this.status,
    required this.role,
    required this.fiatAmount,
    required this.fiatCurrency,
    required this.paymentMethod,
    required this.createdAt,
  });

  /// Unique trade identifier (Nostr event ID hex).
  final String orderId;

  /// true → "Selling Bitcoin"; false → "Buying Bitcoin".
  final bool isSelling;

  /// Current trade status.
  final TradeStatusFilter status;

  /// Whether the local user is the trade creator or taker.
  final TradeRole role;

  /// Human-readable fiat amount (e.g. "966").
  final String fiatAmount;

  /// ISO 4217 fiat currency code (e.g. "ARS").
  final String fiatCurrency;

  /// Payment method string (e.g. "Mercado Pago").
  final String paymentMethod;

  /// Unix timestamp (seconds) when this trade was created.
  final int createdAt;
}

// ── Providers ─────────────────────────────────────────────────────────────────

/// Currently selected status filter for the My Trades dropdown.
///
/// Defaults to [TradeStatusFilter.all].
final selectedStatusFilterProvider =
    StateProvider<TradeStatusFilter>((_) => TradeStatusFilter.all);

/// All trades, filtered by [selectedStatusFilterProvider].
///
/// Returns an empty list until the Rust bridge sessions are wired (Phase 11+).
/// The list is sorted newest-first by [TradeListItem.createdAt].
final filteredTradesWithOrderStateProvider =
    Provider<List<TradeListItem>>((ref) {
  final filter = ref.watch(selectedStatusFilterProvider);

  // TODO(bridge): Watch all active sessions via the Rust bridge and map each
  // SessionState to a TradeListItem.  For now returns an empty list so the
  // empty-state UI is exercised.
  const allTrades = <TradeListItem>[];

  final filtered = filter == TradeStatusFilter.all
      ? allTrades
      : allTrades.where((t) => t.status == filter).toList();

  // Sort newest first.
  final sorted = [...filtered]
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  return sorted;
});

/// Unseen trade update count for the My Trades tab badge.
///
/// Wired to [tradesNotificationCountProvider] in BottomNavBar.
/// Returns 0 until bridge events are integrated.
final orderBookNotificationCountProvider = Provider<int>((_) => 0);

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A closed range of a slider filter.
typedef FilterRange = ({double min, double max});

/// Canonical default range for the rating filter — also the slider's bounds.
const defaultRatingRange = (min: 0.0, max: 5.0);

/// Canonical default range for the premium filter — also the slider's bounds.
const defaultPremiumRange = (min: -10.0, max: 10.0);

/// Where the order-book filters are kept across launches (issue #575).
///
/// One JSON value rather than four keys: the four are always read together,
/// and one read is one await — four would be four chances for a pick made
/// during start-up to be overwritten by the disk.
const kOrderFiltersKey = 'order_book_filters';

/// What narrows the order book: the four controls of the Filters dialog.
///
/// Empty lists and the default ranges mean "no filter" — that is the value
/// the book opens with on a fresh install.
@immutable
class OrderFilters {
  const OrderFilters({
    this.currencies = const [],
    this.paymentMethods = const [],
    this.rating = defaultRatingRange,
    this.premium = defaultPremiumRange,
  });

  /// Fiat codes (multi-select). Empty = any currency.
  final List<String> currencies;

  /// Payment methods (multi-select), matched case-insensitively against an
  /// order's comma-separated list. Empty = any method.
  final List<String> paymentMethods;

  final FilterRange rating;
  final FilterRange premium;

  /// How many of the four controls narrow the book — what the filter chip
  /// counts. A multi-select counts once however many values it holds: the
  /// chip says which controls are on, the dialog says what they hold.
  int get activeCount =>
      (currencies.isNotEmpty ? 1 : 0) +
      (paymentMethods.isNotEmpty ? 1 : 0) +
      (rating != defaultRatingRange ? 1 : 0) +
      (premium != defaultPremiumRange ? 1 : 0);

  bool get isActive => activeCount > 0;

  OrderFilters copyWith({
    List<String>? currencies,
    List<String>? paymentMethods,
    FilterRange? rating,
    FilterRange? premium,
  }) => OrderFilters(
    currencies: currencies ?? this.currencies,
    paymentMethods: paymentMethods ?? this.paymentMethods,
    rating: rating ?? this.rating,
    premium: premium ?? this.premium,
  );

  Map<String, Object?> toJson() => {
    'currencies': currencies,
    'paymentMethods': paymentMethods,
    'rating': [rating.min, rating.max],
    'premium': [premium.min, premium.max],
  };

  /// Reads what an earlier session stored, trusting none of it.
  ///
  /// Storage outlives the app version that wrote it, and the dialog's
  /// `RangeSlider` asserts its values lie inside its bounds — so a range is
  /// clamped to them, and one that is inverted or not a pair of numbers
  /// falls back to the default. A list keeps its non-empty strings, once
  /// each. Anything else about the value, or the value itself, falls back to
  /// "no filter" for that control alone.
  ///
  /// Codes and methods are deliberately not checked against today's
  /// catalogue: a currency still traded on the book can drop out of
  /// `fiat.json`, and the filter would still match its orders. The dialog
  /// shows every selected value, catalogued or not, so none can get stuck.
  factory OrderFilters.fromStored(String? raw) {
    if (raw == null) return const OrderFilters();
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return const OrderFilters();
    }
    if (decoded is! Map) return const OrderFilters();
    return OrderFilters(
      currencies: _strings(decoded['currencies']),
      paymentMethods: _strings(decoded['paymentMethods']),
      rating: _range(decoded['rating'], defaultRatingRange),
      premium: _range(decoded['premium'], defaultPremiumRange),
    );
  }

  static List<String> _strings(Object? raw) {
    if (raw is! List) return const [];
    final seen = <String>{};
    for (final value in raw) {
      if (value is String && value.trim().isNotEmpty) seen.add(value.trim());
    }
    return List.unmodifiable(seen);
  }

  static FilterRange _range(Object? raw, FilterRange bounds) {
    if (raw is! List || raw.length != 2) return bounds;
    final [lo, hi] = raw;
    if (lo is! num || hi is! num) return bounds;
    final min = lo.toDouble(), max = hi.toDouble();
    if (!min.isFinite || !max.isFinite || min > max) return bounds;
    return (
      min: min.clamp(bounds.min, bounds.max),
      max: max.clamp(bounds.min, bounds.max),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is OrderFilters &&
      listEquals(other.currencies, currencies) &&
      listEquals(other.paymentMethods, paymentMethods) &&
      other.rating == rating &&
      other.premium == premium;

  @override
  int get hashCode => Object.hash(
    Object.hashAll(currencies),
    Object.hashAll(paymentMethods),
    rating,
    premium,
  );
}

/// The order-book filters, kept across launches (issue #575).
///
/// Built like `TradeListFilterNotifier`, the My Trades filter: loaded once
/// when first read, saved on every committed change, best effort both ways —
/// a failed read or write is logged and the filters still apply for the
/// session.
///
/// A device preference, not identity data: `resetIdentityScopedState`
/// leaves it alone, as it does the theme and the trade-list filter. The
/// filters say what the person holding the phone wants to see, and a new
/// identity does not change that.
class OrderFiltersNotifier extends StateNotifier<OrderFilters> {
  OrderFiltersNotifier({Future<SharedPreferences> Function()? prefs})
    : _prefs = prefs ?? SharedPreferences.getInstance,
      super(const OrderFilters()) {
    _load();
  }

  final Future<SharedPreferences> Function() _prefs;

  /// Set by the first change, so a load that answers late cannot undo it.
  bool _chosen = false;

  Future<void> _load() async {
    try {
      final prefs = await _prefs();
      // A pick made while the disk was being read is newer than the disk.
      if (!mounted || _chosen) return;
      state = OrderFilters.fromStored(prefs.getString(kOrderFiltersKey));
    } catch (e) {
      debugPrint('[order-book] filters load failed: $e');
    }
  }

  /// Applies [next] and stores it.
  ///
  /// With [persist] false the change applies but is not written: a slider
  /// reports every frame of a drag, and only where it comes to rest is worth
  /// a disk write (`onChangeEnd` calls again with [persist] true).
  Future<void> set(OrderFilters next, {bool persist = true}) async {
    _chosen = true;
    state = next;
    if (persist) await _save();
  }

  /// Back to "no filter", on disk too — otherwise `Reset` would look like it
  /// worked until the next launch brought the old filters back.
  Future<void> clear() => set(const OrderFilters());

  Future<void> _save() async {
    final snapshot = state;
    try {
      final prefs = await _prefs();
      if (snapshot.isActive) {
        await prefs.setString(kOrderFiltersKey, jsonEncode(snapshot.toJson()));
      } else {
        await prefs.remove(kOrderFiltersKey);
      }
    } catch (e) {
      // The filters still apply for this session.
      debugPrint('[order-book] filters save failed: $e');
    }
  }
}

final orderFiltersProvider =
    StateNotifierProvider<OrderFiltersNotifier, OrderFilters>(
      (ref) => OrderFiltersNotifier(),
    );

/// Whether any filter currently narrows the order book.
final hasActiveOrderFiltersProvider = Provider<bool>(
  (ref) => ref.watch(orderFiltersProvider.select((f) => f.isActive)),
);

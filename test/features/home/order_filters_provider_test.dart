import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/features/home/providers/order_filters_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The order-book filters outlive the app (issue #575).
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  String stored(Object? value) => jsonEncode(value);

  group('OrderFilters.fromStored', () {
    test('nothing stored is no filter', () {
      expect(OrderFilters.fromStored(null), const OrderFilters());
    });

    test('reads back what toJson wrote', () {
      const filters = OrderFilters(
        currencies: ['ARS', 'USD'],
        paymentMethods: ['Mercado Pago'],
        rating: (min: 4.0, max: 5.0),
        premium: (min: -3.0, max: 2.0),
      );
      expect(OrderFilters.fromStored(stored(filters.toJson())), filters);
    });

    test('a value that is not JSON, or not an object, is no filter', () {
      expect(OrderFilters.fromStored('{not json'), const OrderFilters());
      expect(OrderFilters.fromStored(stored([1, 2])), const OrderFilters());
      expect(OrderFilters.fromStored(stored('ARS')), const OrderFilters());
    });

    test('a range is clamped to the slider bounds', () {
      // RangeSlider asserts its values lie inside min..max: a stored range
      // from a version with wider bounds must not break the dialog.
      final filters = OrderFilters.fromStored(
        stored({
          'rating': [-1, 9],
          'premium': [-40, 3],
        }),
      );
      expect(filters.rating, defaultRatingRange);
      expect(filters.premium, (min: -10.0, max: 3.0));
    });

    test('an inverted or malformed range falls back to its default alone', () {
      final filters = OrderFilters.fromStored(
        stored({
          'currencies': ['ARS'],
          'rating': [4, 2],
          'premium': ['a', 'b'],
        }),
      );
      expect(filters.rating, defaultRatingRange);
      expect(filters.premium, defaultPremiumRange);
      // The broken controls do not take the good one with them.
      expect(filters.currencies, ['ARS']);
    });

    test('a range that is not a pair falls back to its default', () {
      final filters = OrderFilters.fromStored(
        stored({
          'rating': [4],
          'premium': 3,
        }),
      );
      expect(filters.rating, defaultRatingRange);
      expect(filters.premium, defaultPremiumRange);
    });

    test('a list keeps its non-empty strings, trimmed, once each', () {
      final filters = OrderFilters.fromStored(
        stored({
          'currencies': ['ARS', ' ARS ', '', 7, null, 'USD'],
          'paymentMethods': 'Pix',
        }),
      );
      expect(filters.currencies, ['ARS', 'USD']);
      expect(filters.paymentMethods, isEmpty);
    });

    test('a code the catalogue no longer lists is kept, not dropped', () {
      // The filter still matches that currency's orders; the dialog shows
      // every selected value, so it can still be deselected.
      final filters = OrderFilters.fromStored(
        stored({
          'currencies': ['XYZ'],
        }),
      );
      expect(filters.currencies, ['XYZ']);
    });
  });

  group('OrderFilters.activeCount', () {
    test('counts the controls in use, not the values they hold', () {
      expect(const OrderFilters().activeCount, 0);
      expect(
        const OrderFilters(currencies: ['ARS', 'USD', 'EUR']).activeCount,
        1,
      );
      expect(
        const OrderFilters(
          currencies: ['ARS'],
          paymentMethods: ['Pix'],
          rating: (min: 3.0, max: 5.0),
          premium: (min: -10.0, max: 0.0),
        ).activeCount,
        4,
      );
    });
  });

  group('OrderFiltersNotifier', () {
    test('restores the filters chosen in an earlier session', () async {
      SharedPreferences.setMockInitialValues({
        kOrderFiltersKey: stored(
          const OrderFilters(currencies: ['ARS']).toJson(),
        ),
      });
      final notifier = OrderFiltersNotifier();
      await pumpEventQueue();
      expect(notifier.state.currencies, ['ARS']);
    });

    test('persists a change', () async {
      final notifier = OrderFiltersNotifier();
      await notifier.set(const OrderFilters(paymentMethods: ['Pix']));

      final prefs = await SharedPreferences.getInstance();
      expect(
        OrderFilters.fromStored(prefs.getString(kOrderFiltersKey)),
        const OrderFilters(paymentMethods: ['Pix']),
      );
    });

    test(
      'a change made while loading is not overwritten by the load',
      () async {
        SharedPreferences.setMockInitialValues({
          kOrderFiltersKey: stored(
            const OrderFilters(currencies: ['ARS']).toJson(),
          ),
        });
        final disk = Completer<SharedPreferences>();
        final notifier = OrderFiltersNotifier(prefs: () => disk.future);

        final saved = notifier.set(const OrderFilters(currencies: ['USD']));
        disk.complete(await SharedPreferences.getInstance());
        await saved;
        await pumpEventQueue();

        expect(notifier.state.currencies, ['USD']);
      },
    );

    test('a slider drag applies without writing; its end writes', () async {
      final notifier = OrderFiltersNotifier();
      await pumpEventQueue();
      final prefs = await SharedPreferences.getInstance();

      await notifier.set(
        const OrderFilters(rating: (min: 2.0, max: 5.0)),
        persist: false,
      );
      expect(notifier.state.rating, (min: 2.0, max: 5.0));
      expect(prefs.getString(kOrderFiltersKey), isNull);

      await notifier.set(const OrderFilters(rating: (min: 3.0, max: 5.0)));
      expect(
        OrderFilters.fromStored(prefs.getString(kOrderFiltersKey)).rating,
        (min: 3.0, max: 5.0),
      );
    });

    test('clear empties the stored copy, not only the state', () async {
      SharedPreferences.setMockInitialValues({
        kOrderFiltersKey: stored(
          const OrderFilters(currencies: ['ARS']).toJson(),
        ),
      });
      final notifier = OrderFiltersNotifier();
      await pumpEventQueue();

      await notifier.clear();

      expect(notifier.state, const OrderFilters());
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey(kOrderFiltersKey), isFalse);
    });

    test('a failed read leaves the book unfiltered and usable', () async {
      final notifier = OrderFiltersNotifier(
        prefs: () => Future.error(StateError('disk gone')),
      );
      await pumpEventQueue();
      expect(notifier.state, const OrderFilters());

      // A write that fails the same way still applies for the session.
      await notifier.set(const OrderFilters(currencies: ['EUR']));
      expect(notifier.state.currencies, ['EUR']);
    });
  });
}

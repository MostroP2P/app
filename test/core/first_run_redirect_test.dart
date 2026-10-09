import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/app_routes.dart';

void main() {
  group('firstRunRedirect', () {
    test('sends every other route to the walkthrough until the first run '
        'is complete', () {
      expect(
        firstRunRedirect(done: false, location: AppRoute.home),
        AppRoute.walkthrough,
      );
    });

    test('lets both first-run routes through until it is complete', () {
      for (final location in [AppRoute.walkthrough, AppRoute.chooseNode]) {
        expect(
          firstRunRedirect(done: false, location: location),
          isNull,
          reason: location,
        );
      }
    });

    test('sends a completed user who reaches the node choice home', () {
      // A deep link must not switch nodes past the trade-in-progress warning
      // of the Settings selector.
      expect(
        firstRunRedirect(done: true, location: AppRoute.chooseNode),
        AppRoute.home,
      );
    });

    test('leaves every other route alone once complete', () {
      expect(firstRunRedirect(done: true, location: AppRoute.home), isNull);
      expect(
        firstRunRedirect(done: true, location: AppRoute.walkthrough),
        isNull,
      );
    });
  });
}

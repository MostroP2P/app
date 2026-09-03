import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/app_theme.dart';

void main() {
  group('theme construction', () {
    // MaterialApp.router rebuilds on every locale, theme-mode and route
    // change, and it asks for both themes each time. ThemeData is immutable,
    // so there is nothing to gain from rebuilding it.
    test('returns the same light theme instance every time', () {
      expect(identical(buildLightTheme(), buildLightTheme()), isTrue);
    });

    test('returns the same dark theme instance every time', () {
      expect(identical(buildDarkTheme(), buildDarkTheme()), isTrue);
    });

    test('keeps the two themes distinct', () {
      expect(identical(buildLightTheme(), buildDarkTheme()), isFalse);
      expect(buildLightTheme().brightness, isNot(buildDarkTheme().brightness));
    });
  });
}

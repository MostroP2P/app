import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Registers the licence of each bundled font family with the
/// [LicenseRegistry], next to the package licences Flutter already collects.
///
/// The OFL (Outfit, Manrope) and the MIT licence of the avatar animals
/// (NymAnimals, drawn from Fluent Emoji High Contrast) let them ship inside
/// the app only with their copyright notice and licence, as does the OFL of
/// the flags (NotoFlags, a subset of Noto Color Emoji), and `pubspec.yaml`
/// bundles those texts as assets for exactly this.
void registerFontLicenses() {
  LicenseRegistry.addLicense(() async* {
    for (final (family, asset) in const [
      ('Outfit', 'assets/fonts/outfit/OFL.txt'),
      ('Manrope', 'assets/fonts/manrope/OFL.txt'),
      ('Fluent Emoji High Contrast', 'assets/fonts/nym_animals/LICENSE.txt'),
      ('Noto Color Emoji', 'assets/fonts/noto_flags/LICENSE.txt'),
    ]) {
      yield LicenseEntryWithLineBreaks([
        family,
      ], await rootBundle.loadString(asset));
    }
  });
}

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Loads the bundled UI fonts into the test engine.
///
/// Without this, `flutter test` draws every glyph as a full em square. That is
/// harmless for a golden that only has to stay equal to itself, but it is not
/// harmless for a layout that *measures* text: "Confirm" comes out 105 px wide
/// instead of ~60, and a footer that fits one row in the app stacks in the
/// test. Any test whose layout depends on text width must call this.
Future<void> loadAppFonts() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final (family, files) in const [
    ('Outfit', [
      'Outfit-Regular.ttf',
      'Outfit-Medium.ttf',
      'Outfit-SemiBold.ttf',
      'Outfit-Bold.ttf',
    ]),
    ('Manrope', [
      'Manrope-Medium.ttf',
      'Manrope-SemiBold.ttf',
      'Manrope-Bold.ttf',
    ]),
  ]) {
    final loader = FontLoader(family);
    for (final file in files) {
      final path = 'assets/fonts/${family.toLowerCase()}/$file';
      loader.addFont(
        File(path).readAsBytes().then((b) => ByteData.sublistView(b)),
      );
    }
    await loader.load();
  }
  await _loadMaterialIcons();
}

/// Loads Flutter's own icon font, which `flutter test` also leaves out: an
/// `Icon` renders as an empty box without it, so a golden with an icon in it
/// cannot catch the icon changing.
///
/// The file ships inside the SDK, not with the app, so it is looked for by
/// walking up from the running executable rather than at a fixed path — which
/// layer of `bin/cache` it sits under differs between SDK installs.
Future<void> _loadMaterialIcons() async {
  const relative = 'artifacts/material_fonts/MaterialIcons-Regular.otf';
  var dir = File(Platform.resolvedExecutable).parent;
  for (var i = 0; i < 6; i++) {
    final font = File('${dir.path}/$relative');
    if (font.existsSync()) {
      final loader = FontLoader('MaterialIcons')
        ..addFont(font.readAsBytes().then((b) => ByteData.sublistView(b)));
      await loader.load();
      return;
    }
    if (dir.parent.path == dir.path) break;
    dir = dir.parent;
  }
  // Not fatal: the glyph falls back to a box, as it did before this existed.
}

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/l10n/app_localizations.dart';

/// French puts 0 and 1 in the singular, and the restore sheet's counts reach
/// both: "0 ordre trouvé", never "1 ordre trouvé" for zero nor
/// "1 ordres" for one.
void main() {
  late AppLocalizations fr;

  setUpAll(() async {
    fr = await AppLocalizations.delegate.load(const Locale('fr'));
  });

  test('orders found', () {
    expect(fr.restoreStageFound(0), '0 ordre trouvé');
    expect(fr.restoreStageFound(1), '1 ordre trouvé');
    expect(fr.restoreStageFound(3), '3 ordres trouvés');
  });

  test('orders recovered while loading', () {
    expect(fr.restoreSheetLoading(1, 3), '1 ordre récupéré sur 3');
    expect(fr.restoreSheetLoading(2, 3), '2 ordres récupérés sur 3');
  });

  test('the counter read aloud', () {
    expect(fr.restoreLoadingCountSemantics(1, 3), '1 ordre sur 3');
    expect(fr.restoreLoadingCountSemantics(2, 3), '2 ordres sur 3');
  });

  test('orders that did not load', () {
    expect(
      fr.restorePartialNotice(1, 3),
      "1 ordre sur 3 n'a pas pu être chargé",
    );
    expect(
      fr.restorePartialNotice(2, 3),
      "2 ordres sur 3 n'ont pas pu être chargés",
    );
  });
}

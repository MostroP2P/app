import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/l10n/app_localizations.dart';

/// French puts 0 and 1 in the singular, and the restore sheet's counts reach
/// both: "0 commande trouvée", never "1 commande trouvée" for zero nor
/// "1 commandes" for one.
void main() {
  late AppLocalizations fr;

  setUpAll(() async {
    fr = await AppLocalizations.delegate.load(const Locale('fr'));
  });

  test('orders found', () {
    expect(fr.restoreStageFound(0), '0 commande trouvée');
    expect(fr.restoreStageFound(1), '1 commande trouvée');
    expect(fr.restoreStageFound(3), '3 commandes trouvées');
  });

  test('orders recovered while loading', () {
    expect(fr.restoreSheetLoading(1, 3), '1 commande récupérée sur 3');
    expect(fr.restoreSheetLoading(2, 3), '2 commandes récupérées sur 3');
  });

  test('the counter read aloud', () {
    expect(fr.restoreLoadingCountSemantics(1, 3), '1 commande sur 3');
    expect(fr.restoreLoadingCountSemantics(2, 3), '2 commandes sur 3');
  });

  test('orders that did not load', () {
    expect(
      fr.restorePartialNotice(1, 3),
      "1 commande sur 3 n'a pas pu être chargée",
    );
    expect(
      fr.restorePartialNotice(2, 3),
      "2 commandes sur 3 n'ont pas pu être chargées",
    );
  });
}

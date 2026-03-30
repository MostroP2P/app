// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Italian (`it`).
class AppLocalizationsIt extends AppLocalizations {
  AppLocalizationsIt([String locale = 'it']) : super(locale);

  @override
  String get appName => 'Mostro';

  @override
  String get loading => 'Caricamento…';

  @override
  String get error => 'Errore';

  @override
  String get cancel => 'Annulla';

  @override
  String get confirm => 'Conferma';

  @override
  String get done => 'Fine';

  @override
  String get skip => 'Salta';

  @override
  String get chatTimestampYesterday => 'Ieri';

  @override
  String get disputesEmptyState => 'Le tue controversie appariranno qui';

  @override
  String get disputeAttachFile => 'Allega file';

  @override
  String get disputeWriteMessageHint => 'Scrivi un messaggio…';

  @override
  String get disputeSend => 'Invia';
}

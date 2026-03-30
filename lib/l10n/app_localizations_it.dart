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

  @override
  String get orderDispute => 'Disputa ordine';

  @override
  String get disputeAdminAssigned =>
      'Un amministratore è stato assegnato alla tua disputa. Ti contatterà qui a breve.';

  @override
  String get disputeChatClosed =>
      'Questa disputa è stata risolta. La chat è chiusa.';

  @override
  String get messageCopied => 'Copiato';

  @override
  String get disputeLoadError => 'Impossibile caricare le dispute. Riprova.';

  @override
  String get disputeMessagingComingSoon =>
      'Messaggistica per controversie in arrivo';

  @override
  String get disputeAttachmentsComingSoon => 'Allegati file in arrivo';

  @override
  String get disputeNotFound => 'Controversia non trovata.';

  @override
  String get disputeNotFoundForOrder =>
      'Nessuna controversia trovata per questo ordine.';
}

// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppLocalizationsDe extends AppLocalizations {
  AppLocalizationsDe([String locale = 'de']) : super(locale);

  @override
  String get appName => 'Mostro';

  @override
  String get loading => 'Laden…';

  @override
  String get error => 'Fehler';

  @override
  String get cancel => 'Abbrechen';

  @override
  String get confirm => 'Bestätigen';

  @override
  String get done => 'Fertig';

  @override
  String get skip => 'Überspringen';

  @override
  String get chatTimestampYesterday => 'Gestern';

  @override
  String get disputesEmptyState => 'Deine Streitfälle werden hier angezeigt';

  @override
  String get disputeAttachFile => 'Datei anhängen';

  @override
  String get disputeWriteMessageHint => 'Nachricht schreiben…';

  @override
  String get disputeSend => 'Senden';

  @override
  String get orderDispute => 'Bestellstreit';

  @override
  String get disputeAdminAssigned =>
      'Ein Administrator wurde Ihrem Streitfall zugewiesen. Er wird sich hier in Kürze bei Ihnen melden.';

  @override
  String get disputeChatClosed =>
      'Dieser Streitfall wurde gelöst. Der Chat ist geschlossen.';

  @override
  String get messageCopied => 'Kopiert';

  @override
  String get disputeLoadError =>
      'Streitfälle konnten nicht geladen werden. Bitte versuchen Sie es erneut.';
}

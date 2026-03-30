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

  @override
  String get disputeMessagingComingSoon =>
      'Streitfall-Nachrichten demnächst verfügbar';

  @override
  String get disputeAttachmentsComingSoon => 'Dateianhänge demnächst verfügbar';

  @override
  String get disputeNotFound => 'Streitfall nicht gefunden.';

  @override
  String get disputeNotFoundForOrder =>
      'Kein Streitfall für diese Bestellung gefunden.';

  @override
  String get disputeResolved => 'Gelöst';

  @override
  String get disputeSuccessfullyCompleted => 'Erfolgreich abgeschlossen';

  @override
  String get disputeCoopCancelMessage =>
      'Die Bestellung wurde kooperativ storniert. Es wurden keine Mittel übertragen.';

  @override
  String disputeWithBuyer(String handle) {
    return 'Streit mit Käufer: $handle';
  }

  @override
  String disputeWithSeller(String handle) {
    return 'Streit mit Verkäufer: $handle';
  }

  @override
  String orderLabel(String orderId) {
    return 'Bestellung $orderId';
  }

  @override
  String get disputeInitiated => 'Eingeleitet';

  @override
  String get disputeInProgress => 'In Bearbeitung';

  @override
  String get disputeStatusClosed => 'Geschlossen';

  @override
  String get disputeLostFundsToBuyer =>
      'Der Administrator hat den Streitfall zugunsten des Käufers entschieden. Die Sats wurden an den Käufer freigegeben.';

  @override
  String get disputeLostFundsToSeller =>
      'Der Administrator hat die Bestellung storniert und die Sats an den Verkäufer zurückgegeben. Sie haben keine Sats erhalten.';
}

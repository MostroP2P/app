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
      'Ein Administrator wurde deinem Streitfall zugewiesen. Er wird sich hier in Kürze bei dir melden.';

  @override
  String get disputeChatClosed =>
      'Dieser Streitfall wurde gelöst. Der Chat ist geschlossen.';

  @override
  String get messageCopied => 'Kopiert';

  @override
  String get disputeLoadError =>
      'Streitfälle konnten nicht geladen werden. Bitte versuche es erneut.';

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
      'Der Administrator hat die Bestellung storniert und die Sats an den Verkäufer zurückgegeben. Du hast keine Sats erhalten.';

  @override
  String get walkthroughSlideOneTitle => 'Bitcoin frei handeln — kein KYC';

  @override
  String get walkthroughSlideOneBody =>
      'Mostro ist eine Peer-to-Peer-Börse, mit der du Bitcoin gegen jede Währung und Zahlungsmethode tauschen kannst — ohne KYC und ohne deine Daten an irgendjemanden weiterzugeben. Es basiert auf Nostr, was es zensurresistent macht. Niemand kann dich am Handeln hindern.';

  @override
  String get walkthroughSlideTwoTitle => 'Privatsphäre als Standard';

  @override
  String get walkthroughSlideTwoBody =>
      'Mostro generiert für jeden Austausch eine neue Identität, sodass deine Trades nicht verknüpft werden können. Du kannst auch selbst entscheiden, wie viel Privatsphäre du möchtest:\n• Reputationsmodus – Andere können deine erfolgreichen Trades und dein Vertrauenslevel sehen.\n• Vollständiger Privatsphäre-Modus – Es wird keine Reputation aufgebaut, aber deine Aktivität ist vollständig anonym.\nWechsle jederzeit den Modus im Konto-Bildschirm, wo du auch deine geheimen Wörter sichern solltest — sie sind die einzige Möglichkeit, dein Konto wiederherzustellen.';

  @override
  String get walkthroughSlideThreeTitle => 'Sicherheit bei jedem Schritt';

  @override
  String get walkthroughSlideThreeBody =>
      'Mostro verwendet Hold Invoices (zurückgehaltene Rechnungen): Die Sats verbleiben bis zum Ende des Handels in der Wallet des Verkäufers. Das schützt beide Seiten. Die App ist außerdem so gestaltet, dass sie intuitiv und einfach für alle Arten von Nutzern ist.';

  @override
  String get walkthroughSlideFourTitle => 'Vollständig verschlüsselter Chat';

  @override
  String get walkthroughSlideFourBody =>
      'Jeder Trade hat seinen eigenen privaten Chat, der Ende-zu-Ende verschlüsselt ist. Nur die beiden beteiligten Nutzer können ihn lesen. Im Streitfall kannst du den gemeinsamen Schlüssel einem Administrator geben, um bei der Lösung zu helfen.';

  @override
  String get walkthroughSlideFiveTitle => 'Ein Angebot annehmen';

  @override
  String get walkthroughSlideFiveBody =>
      'Durchsuche das Orderbuch, wähle ein Angebot, das für dich passt, und folge dem Trade-Ablauf Schritt für Schritt. Du kannst das Profil des anderen Nutzers prüfen, sicher chatten und den Trade problemlos abschließen.';

  @override
  String get walkthroughSlideSixTitle => 'Findest du nicht, was du brauchst?';

  @override
  String get walkthroughSlideSixBody =>
      'Du kannst auch dein eigenes Angebot erstellen und warten, bis jemand es annimmt. Lege den Betrag und die bevorzugte Zahlungsmethode fest — Mostro erledigt den Rest.';

  @override
  String get tabBuyBtc => 'BTC KAUFEN';

  @override
  String get tabSellBtc => 'BTC VERKAUFEN';

  @override
  String get filterButtonLabel => 'FILTERN';

  @override
  String offersCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Angebote',
      one: '1 Angebot',
    );
    return '$_temp0';
  }

  @override
  String get noOrdersAvailable => 'Keine Bestellungen verfügbar';

  @override
  String get justNow => 'Gerade eben';

  @override
  String minutesAgo(int m) {
    return 'Vor ${m}m';
  }

  @override
  String hoursAgo(int h) {
    return 'Vor ${h}h';
  }

  @override
  String daysAgo(int d) {
    return 'Vor ${d}T';
  }

  @override
  String get creatingNewOrderTitle => 'NEUE BESTELLUNG ERSTELLEN';

  @override
  String get youWantToBuyBitcoin => 'Du möchtest Bitcoin kaufen';

  @override
  String get youWantToSellBitcoin => 'Du möchtest Bitcoin verkaufen';

  @override
  String get rangeOrderLabel => 'Bereichsbestellung';

  @override
  String get payLightningInvoiceTitle => 'Lightning-Rechnung bezahlen';

  @override
  String get invoiceCopied => 'Rechnung kopiert';

  @override
  String get addInvoiceTitle => 'Rechnung hinzufügen';

  @override
  String get submitButtonLabel => 'Absenden';

  @override
  String get orderAlreadyTaken => 'Die Bestellung wurde bereits angenommen';

  @override
  String get orderIdCopied => 'Bestell-ID kopiert';

  @override
  String get orderDetailsTitle => 'BESTELLDETAILS';

  @override
  String get timeRemainingLabel => 'Verbleibende Zeit:';

  @override
  String get fiatSentButtonLabel => 'FIAT GESENDET';

  @override
  String get disputeButtonLabel => 'STREITFALL';

  @override
  String get contactButtonLabel => 'KONTAKT';

  @override
  String get rateButtonLabel => 'BEWERTEN';

  @override
  String get viewDisputeButtonLabel => 'STREITFALL ANZEIGEN';

  @override
  String get comingSoonMessage => 'Demnächst verfügbar';

  @override
  String get tradeStatusActive => 'Aktiv';

  @override
  String get tradeStatusFiatSent => 'Fiat gesendet';

  @override
  String get tradeStatusCompleted => 'Abgeschlossen';

  @override
  String get tradeStatusCancelled => 'Storniert';

  @override
  String get tradeStatusDisputed => 'Strittiger Trade';

  @override
  String get releaseButtonLabel => 'FREIGEBEN';

  @override
  String get accountScreenTitle => 'Konto';

  @override
  String get secretWordsTitle => 'Geheime Wörter';

  @override
  String get toRestoreYourAccount => 'Um dein Konto wiederherzustellen';

  @override
  String get privacyCardTitle => 'Datenschutz';

  @override
  String get controlPrivacySettings =>
      'Verwalte deine Datenschutzeinstellungen';

  @override
  String get reputationMode => 'Reputationsmodus';

  @override
  String get reputationModeSubtitle => 'Standard-Datenschutz mit Reputation';

  @override
  String get fullPrivacyMode => 'Vollständiger Privatsphäre-Modus';

  @override
  String get fullPrivacyModeSubtitle => 'Maximale Anonymität';

  @override
  String get generateNewUserButton => 'Neuen Benutzer generieren';

  @override
  String get importMostroUserButton => 'Mostro-Benutzer importieren';

  @override
  String get generateNewUserDialogTitle => 'Neuen Benutzer generieren?';

  @override
  String get generateNewUserDialogContent =>
      'Dadurch wird eine brandneue Identität erstellt. Deine aktuellen geheimen Wörter werden nicht mehr funktionieren — stelle sicher, dass du sie gesichert hast, bevor du fortfährst.';

  @override
  String get continueButtonLabel => 'Weiter';

  @override
  String get importMnemonicDialogTitle => 'Mnemonik importieren';

  @override
  String get importMnemonicHintText => 'Gib deine 12- oder 24-Wort-Phrase ein…';

  @override
  String get importButtonLabel => 'Importieren';

  @override
  String get refreshUserDialogTitle => 'Benutzer aktualisieren?';

  @override
  String get refreshUserDialogContent =>
      'Dadurch werden deine Trades und Bestellungen von der Mostro-Instanz erneut abgerufen. Verwende dies, wenn du glaubst, dass deine Daten nicht synchron sind oder Bestellungen fehlen.';

  @override
  String get hideButtonLabel => 'Verbergen';

  @override
  String get showButtonLabel => 'Anzeigen';

  @override
  String get settingsScreenTitle => 'Einstellungen';

  @override
  String get languageSettingTitle => 'Sprache';

  @override
  String get appearanceSettingTitle => 'Erscheinungsbild';

  @override
  String get appearanceDialogTitle => 'Erscheinungsbild';

  @override
  String get defaultFiatCurrencyTitle => 'Standard-Fiat-Währung';

  @override
  String get allCurrencies => 'Alle Währungen';

  @override
  String get lightningAddressSettingTitle => 'Lightning-Adresse';

  @override
  String get tapToSetSubtitle => 'Tippen zum Einrichten';

  @override
  String get nwcWalletSettingTitle => 'NWC-Wallet';

  @override
  String get nwcConnectPrompt => 'Verbinde deine Lightning-Wallet über NWC';

  @override
  String get relaysSettingTitle => 'Relays';

  @override
  String get manageRelayConnections => 'Relay-Verbindungen verwalten';

  @override
  String get pushNotificationsSettingTitle => 'Push-Benachrichtigungen';

  @override
  String get manageNotificationPreferences =>
      'Benachrichtigungseinstellungen verwalten';

  @override
  String get logReportSettingTitle => 'Protokollbericht';

  @override
  String get viewDiagnosticLogs => 'Diagnoseprotokolle anzeigen';

  @override
  String get mostroNodeSettingTitle => 'Mostro-Knoten';

  @override
  String get themeDark => 'Dunkel';

  @override
  String get themeLight => 'Hell';

  @override
  String get themeSystemDefault => 'Systemstandard';

  @override
  String get lightningAddressDialogTitle => 'Lightning-Adresse';

  @override
  String get lightningAddressHintText => 'benutzer@domain.com';

  @override
  String get invalidLightningAddressFormat =>
      'Muss im Format benutzer@domain oder benutzer@domain.tld vorliegen';

  @override
  String get clearButtonLabel => 'Löschen';

  @override
  String get saveButtonLabel => 'Speichern';

  @override
  String get connectWalletTitle => 'Wallet verbinden';

  @override
  String get scanQrCodeTitle => 'QR-Code scannen';

  @override
  String get pasteNwcUri => 'NWC-URI einfügen';

  @override
  String get selectLanguageTitle => 'Sprache auswählen';

  @override
  String get selectCurrencyDialogTitle => 'Währung auswählen';

  @override
  String get addRelayDialogTitle => 'Relay hinzufügen';

  @override
  String get addButtonLabel => 'Hinzufügen';

  @override
  String get relayHintText => 'wss://relay.example.com';

  @override
  String get relayErrorMustStartWithWss => 'Muss mit wss:// beginnen';

  @override
  String get relayErrorUrlTooShort => 'URL ist zu kurz';

  @override
  String get relayErrorDuplicate => 'Relay bereits in der Liste';

  @override
  String nwcConnectedBalance(String balance) {
    return 'NWC — Verbunden. Guthaben: $balance';
  }

  @override
  String get pasteQrCodeHeading => 'QR-Code-Inhalt einfügen';

  @override
  String get pasteButtonLabel => 'Einfügen';

  @override
  String get clipboardEmptyError => 'Zwischenablage ist leer';

  @override
  String get enterValueError => 'Bitte einen Wert eingeben';

  @override
  String get pasteOrScanQrCode => 'QR-Code einfügen oder scannen';

  @override
  String get mostroNodeTitle => 'Mostro-Knoten';

  @override
  String get currentNodeLabel => 'Aktueller Knoten';

  @override
  String get trustedBadgeLabel => 'Vertrauenswürdig';

  @override
  String get useDefaultButtonLabel => 'Standard verwenden';

  @override
  String get confirmButtonLabel => 'Bestätigen';

  @override
  String get invalidHexPubkey =>
      'Muss eine hexadezimale Zeichenfolge mit 64 Zeichen sein';

  @override
  String get notificationsScreenTitle => 'Benachrichtigungen';

  @override
  String get markAllAsReadMenuItem => 'Alle als gelesen markieren';

  @override
  String get clearAllMenuItem => 'Alle löschen';

  @override
  String get youMustBackUpYourAccount => 'Du musst dein Konto sichern';

  @override
  String get tapToViewAndSaveSecretWords =>
      'Tippe, um deine geheimen Wörter anzuzeigen und zu speichern.';

  @override
  String get noNotifications => 'Keine Benachrichtigungen';

  @override
  String get markAsRead => 'Als gelesen markieren';

  @override
  String get deleteNotificationLabel => 'Löschen';

  @override
  String get rateScreenHeader => 'BEWERTEN';

  @override
  String get successfulOrder => 'Erfolgreiche Bestellung';

  @override
  String get submitRatingButton => 'ABSENDEN';

  @override
  String get closeRatingButton => 'SCHLIESSEN';

  @override
  String get aboutScreenTitle => 'Über';

  @override
  String get mostroTagline => 'Peer-to-Peer Bitcoin-Handel über Nostr';

  @override
  String get viewDocumentationButton => 'Dokumentation anzeigen';

  @override
  String get linkCopiedToClipboard => 'Link in die Zwischenablage kopiert';

  @override
  String get defaultNodeSection => 'Standardknoten';

  @override
  String get pubkeyLabel => 'Öffentlicher Schlüssel';

  @override
  String get relaysLabel => 'Relays';

  @override
  String get pubkeyCopiedToClipboard =>
      'Öffentlicher Schlüssel in die Zwischenablage kopiert';

  @override
  String get footerTagline => 'Open-Source. Nicht-verwahrt. Privat.';

  @override
  String get drawerTitle => 'MOSTRO';

  @override
  String get betaBadgeLabel => 'Beta';

  @override
  String get drawerAccountMenuItem => 'Konto';

  @override
  String get drawerSettingsMenuItem => 'Einstellungen';

  @override
  String get drawerAboutMenuItem => 'Über';

  @override
  String get navOrderBook => 'Orderbuch';

  @override
  String get navMyTrades => 'Meine Trades';

  @override
  String get navChat => 'Chat';

  @override
  String get loadingOrders => 'Aufträge werden geladen…';

  @override
  String get errorLoadingOrders =>
      'Aufträge konnten nicht geladen werden. Bitte Verbindung prüfen.';

  @override
  String get retry => 'Erneut versuchen';

  @override
  String disableRelayLabel(String url) {
    return 'Relay $url deaktivieren';
  }

  @override
  String enableRelayLabel(String url) {
    return 'Relay $url aktivieren';
  }

  @override
  String get removeRelayTooltip => 'Relay entfernen';

  @override
  String get relayAddFailed => 'Relay konnte nicht hinzugefügt werden';

  @override
  String get relayRemoveFailed => 'Relay konnte nicht entfernt werden';

  @override
  String get backupConfirmCheckbox =>
      'Ich habe meine Wörter aufgeschrieben und sicher gespeichert';

  @override
  String get cancelTradeDialogTitle => 'Handel abbrechen?';

  @override
  String get cancelTradeDialogContent =>
      'Kooperativen Abbruch angefragt. Die andere Partei muss ebenfalls zustimmen, damit der Handel vollständig abgebrochen wird.';

  @override
  String get noButtonLabel => 'Nein';

  @override
  String get yesCancelButtonLabel => 'Ja, abbrechen';

  @override
  String get cancelRequestSent => 'Abbruchanfrage gesendet';

  @override
  String get cancelRequestFailed =>
      'Abbrechen fehlgeschlagen. Bitte erneut versuchen.';

  @override
  String get fiatSentFailed =>
      'Fiat-Zahlung konnte nicht bestätigt werden. Bitte erneut versuchen.';

  @override
  String get releaseFailed =>
      'Freigabe fehlgeschlagen. Bitte erneut versuchen.';

  @override
  String get orderPillYouAreSelling => 'SIE VERKAUFEN';

  @override
  String get orderPillYouAreBuying => 'SIE KAUFEN';

  @override
  String get orderPillSelling => 'VERKAUF';

  @override
  String get orderPillBuying => 'KAUF';

  @override
  String get myOrderSellTitle => 'IHR VERKAUFSANGEBOT';

  @override
  String get myOrderBuyTitle => 'IHR KAUFANGEBOT';

  @override
  String get cancelOrderButton => 'Angebot stornieren';

  @override
  String get cancelOrderDialogTitle => 'Angebot stornieren';

  @override
  String get cancelOrderDialogContent =>
      'Sind Sie sicher, dass Sie dieses Angebot stornieren möchten? Diese Aktion kann nicht rückgängig gemacht werden.';

  @override
  String get cancelOrderFailed =>
      'Stornierung fehlgeschlagen. Bitte erneut versuchen.';

  @override
  String get closeButtonLabel => 'Schließen';

  @override
  String get copyButtonLabel => 'Kopieren';

  @override
  String get orderStatusWaitingForTaker => 'Warte auf Taker';

  @override
  String get orderStatusWaitingBuyerInvoice => 'Warte auf Käufer-Rechnung';

  @override
  String get orderStatusWaitingPayment => 'Warte auf Zahlung';

  @override
  String get orderStatusInProgress => 'In Bearbeitung';

  @override
  String get orderStatusExpired => 'Abgelaufen';

  @override
  String get copyOrderIdTooltip => 'Auftrags-ID kopieren';

  @override
  String get orderNotFoundTitle => 'Auftrag nicht gefunden';

  @override
  String get orderNotFoundMessage => 'Dieser Auftrag ist nicht mehr verfügbar.';

  @override
  String get orderCancelledSuccess => 'Auftrag erfolgreich storniert.';

  @override
  String get aboutAppInfoTitle => 'App-Informationen';

  @override
  String get aboutDocumentationTitle => 'Dokumentation';

  @override
  String get aboutMostroNodeTitle => 'Mostro-Knoten';

  @override
  String get aboutVersionLabel => 'Version';

  @override
  String get aboutGithubRepoLabel => 'GitHub-Repository';

  @override
  String get aboutCommitHashLabel => 'Commit-Hash';

  @override
  String get aboutLicenseLabel => 'Lizenz';

  @override
  String get aboutLicenseName => 'MIT';

  @override
  String get aboutGithubRepoName => 'mostro-mobile';

  @override
  String get aboutDocsUsersEnglish => 'Nutzer (Englisch)';

  @override
  String get aboutDocsUsersSpanish => 'Nutzer (Spanisch)';

  @override
  String get aboutDocsTechnical => 'Technisch';

  @override
  String get aboutDocsRead => 'Lesen';

  @override
  String get aboutCopiedToClipboard => 'In die Zwischenablage kopiert';

  @override
  String get aboutLicenseDialogTitle => 'MIT-Lizenz';

  @override
  String get aboutNodeLoadingText => 'Knoteninformationen werden geladen…';

  @override
  String get aboutNodeUnavailable => 'Knoteninformationen nicht verfügbar';

  @override
  String get aboutNodeRetry => 'Erneut versuchen';

  @override
  String get aboutGeneralInfoSection => 'Allgemeine Informationen';

  @override
  String get aboutTechnicalDetailsSection => 'Technische Details';

  @override
  String get aboutLightningNetworkSection => 'Lightning-Netzwerk';

  @override
  String get aboutMostroPublicKeyLabel => 'Öffentlicher Mostro-Schlüssel';

  @override
  String get aboutMaxOrderAmountLabel => 'Maximaler Auftragsbetrag';

  @override
  String get aboutMinOrderAmountLabel => 'Minimaler Auftragsbetrag';

  @override
  String get aboutOrderLifespanLabel => 'Auftragslaufzeit';

  @override
  String get aboutServiceFeeLabel => 'Servicegebühr';

  @override
  String get aboutFiatCurrenciesLabel => 'Fiat-Währungen';

  @override
  String get aboutMostroVersionLabel => 'Mostro-Version';

  @override
  String get aboutMostroCommitLabel => 'Mostro-Commit';

  @override
  String get aboutOrderExpirationLabel => 'Auftragsablauf';

  @override
  String get aboutHoldInvoiceExpLabel => 'Hold-Invoice-Ablauf';

  @override
  String get aboutHoldInvoiceCltvLabel => 'Hold-Invoice CLTV';

  @override
  String get aboutInvoiceExpWindowLabel => 'Rechnungsablauffenster';

  @override
  String get aboutProofOfWorkLabel => 'Proof of Work';

  @override
  String get aboutMaxOrdersPerResponseLabel => 'Max. Aufträge/Antwort';

  @override
  String get aboutLndVersionLabel => 'LND-Version';

  @override
  String get aboutLndNodePublicKeyLabel => 'Öffentlicher LND-Knotenschlüssel';

  @override
  String get aboutLndCommitLabel => 'LND-Commit';

  @override
  String get aboutLndNodeAliasLabel => 'LND-Knotenalias';

  @override
  String get aboutSupportedChainsLabel => 'Unterstützte Chains';

  @override
  String get aboutSupportedNetworksLabel => 'Unterstützte Netzwerke';

  @override
  String get aboutLndNodeUriLabel => 'LND-Knoten-URI';

  @override
  String get aboutSatoshisSuffix => 'Satoshis';

  @override
  String get aboutHoursSuffix => 'Stunden';

  @override
  String get aboutSecondsSuffix => 'Sekunden';

  @override
  String get aboutBlocksSuffix => 'Blöcke';

  @override
  String get aboutFiatCurrenciesAll => 'Alle';

  @override
  String get aboutMostroPublicKeyExplanation =>
      'Der öffentliche Nostr-Schlüssel des Mostro-Daemons. Alle Aufträge und verschlüsselten Nachrichten dieser Instanz werden von diesem Schlüssel veröffentlicht oder weitergeleitet.';

  @override
  String get aboutMaxOrderAmountExplanation =>
      'Der maximale Fiat-Betrag für einen einzelnen Auftrag auf dieser Mostro-Instanz.';

  @override
  String get aboutMinOrderAmountExplanation =>
      'Der minimale Fiat-Betrag für einen einzelnen Auftrag auf dieser Mostro-Instanz.';

  @override
  String get aboutOrderLifespanExplanation =>
      'Wie lange ein ausstehender Auftrag offen bleibt, bevor er automatisch abläuft, wenn kein Abnehmer gefunden wird.';

  @override
  String get aboutServiceFeeExplanation =>
      'Der Prozentsatz des Handelsbetrags, der vom Mostro-Daemon als Servicegebühr erhoben wird.';

  @override
  String get aboutFiatCurrenciesExplanation =>
      'Die auf dieser Mostro-Instanz akzeptierten Fiat-Währungen. \'Alle\' bedeutet, dass es keine Einschränkungen gibt.';

  @override
  String get aboutMostroVersionExplanation =>
      'Die Version der Mostro-Daemon-Software, die auf dieser Instanz ausgeführt wird.';

  @override
  String get aboutMostroCommitExplanation =>
      'Der Git-Commit-Hash des Mostro-Daemon-Builds zur Identifizierung der genauen Software-Revision.';

  @override
  String get aboutOrderExpirationExplanation =>
      'Die Zeitüberschreitung in Sekunden, nach der ein auf Aktion wartender Handel (z.B. Rechnung oder Zahlung) automatisch storniert wird.';

  @override
  String get aboutHoldInvoiceExpExplanation =>
      'Das Zeitfenster in Sekunden, in dem die Lightning-Hold-Invoice abgerechnet werden muss.';

  @override
  String get aboutHoldInvoiceCltvExplanation =>
      'Das CLTV-Delta (Blockanzahl) für Hold-Invoices, das steuert, wie lange der HTLC gesperrt bleiben kann.';

  @override
  String get aboutInvoiceExpWindowExplanation =>
      'Das Zeitfenster in Sekunden, in dem der Käufer nach Handelsbeginn eine Lightning-Rechnung einreichen muss.';

  @override
  String get aboutProofOfWorkExplanation =>
      'Die minimale Proof-of-Work-Schwierigkeit für Nostr-Events auf dieser Instanz. 0 bedeutet, dass kein PoW erforderlich ist.';

  @override
  String get aboutMaxOrdersPerResponseExplanation =>
      'Die maximale Anzahl von Aufträgen in einer einzelnen Relay-Antwort. Begrenzt die Bandbreitennutzung.';

  @override
  String get aboutLndVersionExplanation =>
      'Die Version des LND-Knotens (Lightning Network Daemon), der mit dieser Mostro-Instanz verbunden ist.';

  @override
  String get aboutLndNodePublicKeyExplanation =>
      'Der öffentliche Schlüssel des LND-Knotens zur Identifizierung und Verifizierung des Lightning-Netzwerk-Knotens.';

  @override
  String get aboutLndCommitExplanation =>
      'Der Git-Commit-Hash des LND-Builds zur Identifizierung der genauen Software-Revision des Lightning-Knotens.';

  @override
  String get aboutLndNodeAliasExplanation =>
      'Der lesbare Alias des LND-Knotens, wie vom Knotenbetreiber konfiguriert.';

  @override
  String get aboutSupportedChainsExplanation =>
      'Die vom LND-Knoten unterstützten Blockchain(s) (z.B. \'bitcoin\').';

  @override
  String get aboutSupportedNetworksExplanation =>
      'Die Netzwerke, in denen der LND-Knoten betrieben wird (z.B. \'mainnet\', \'testnet\').';

  @override
  String get aboutLndNodeUriExplanation =>
      'Die Verbindungs-URI des LND-Knotens im Format pubkey@host:port. Wird zum Öffnen direkter Zahlungskanäle verwendet.';

  @override
  String get openDisputeFailed =>
      'Streit konnte nicht eröffnet werden. Bitte erneut versuchen.';

  @override
  String get tradeWaitingInvoiceBuyerInstruction =>
      'Sende deine Lightning-Rechnung, damit der Verkäufer die Gelder sperren kann.';

  @override
  String get tradeWaitingInvoiceSellerInstruction =>
      'Warte auf die Lightning-Rechnung des Käufers.';

  @override
  String get tradeWaitingPaymentBuyerInstruction =>
      'Der Verkäufer bezahlt die Hold-Rechnung. Bitte warten.';

  @override
  String get tradeWaitingPaymentSellerInstruction =>
      'Bezahle die Hold-Rechnung, um die Gelder zu sperren und den Handel zu starten.';

  @override
  String get tradeLoadError =>
      'Beim Laden des Handels ist ein Fehler aufgetreten.';
}

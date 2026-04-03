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
  String get aboutAppInfoTitle => 'App Information';

  @override
  String get aboutDocumentationTitle => 'Documentation';

  @override
  String get aboutMostroNodeTitle => 'Mostro Node';

  @override
  String get aboutVersionLabel => 'Version';

  @override
  String get aboutGithubRepoLabel => 'GitHub Repository';

  @override
  String get aboutCommitHashLabel => 'Commit Hash';

  @override
  String get aboutLicenseLabel => 'License';

  @override
  String get aboutLicenseName => 'MIT';

  @override
  String get aboutGithubRepoName => 'mostro-mobile';

  @override
  String get aboutDocsUsersEnglish => 'Users (English)';

  @override
  String get aboutDocsUsersSpanish => 'Users (Spanish)';

  @override
  String get aboutDocsTechnical => 'Technical';

  @override
  String get aboutDocsRead => 'Read';

  @override
  String get aboutCopiedToClipboard => 'Copied to clipboard';

  @override
  String get aboutLicenseDialogTitle => 'MIT License';

  @override
  String get aboutNodeLoadingText => 'Loading node information…';

  @override
  String get aboutNodeUnavailable => 'Node information unavailable';

  @override
  String get aboutNodeRetry => 'Retry';

  @override
  String get aboutGeneralInfoSection => 'General Info';

  @override
  String get aboutTechnicalDetailsSection => 'Technical Details';

  @override
  String get aboutLightningNetworkSection => 'Lightning Network';

  @override
  String get aboutMostroPublicKeyLabel => 'Mostro Public Key';

  @override
  String get aboutMaxOrderAmountLabel => 'Max Order Amount';

  @override
  String get aboutMinOrderAmountLabel => 'Min Order Amount';

  @override
  String get aboutOrderLifespanLabel => 'Order Lifespan';

  @override
  String get aboutServiceFeeLabel => 'Service Fee';

  @override
  String get aboutFiatCurrenciesLabel => 'Fiat Currencies';

  @override
  String get aboutMostroVersionLabel => 'Mostro Version';

  @override
  String get aboutMostroCommitLabel => 'Mostro Commit';

  @override
  String get aboutOrderExpirationLabel => 'Order Expiration';

  @override
  String get aboutHoldInvoiceExpLabel => 'Hold Invoice Exp.';

  @override
  String get aboutHoldInvoiceCltvLabel => 'Hold Invoice CLTV';

  @override
  String get aboutInvoiceExpWindowLabel => 'Invoice Exp. Window';

  @override
  String get aboutProofOfWorkLabel => 'Proof of Work';

  @override
  String get aboutMaxOrdersPerResponseLabel => 'Max Orders/Response';

  @override
  String get aboutLndVersionLabel => 'LND Version';

  @override
  String get aboutLndNodePublicKeyLabel => 'LND Node Public Key';

  @override
  String get aboutLndCommitLabel => 'LND Commit';

  @override
  String get aboutLndNodeAliasLabel => 'LND Node Alias';

  @override
  String get aboutSupportedChainsLabel => 'Supported Chains';

  @override
  String get aboutSupportedNetworksLabel => 'Supported Networks';

  @override
  String get aboutLndNodeUriLabel => 'LND Node URI';

  @override
  String get aboutSatoshisSuffix => 'Satoshis';

  @override
  String get aboutHoursSuffix => 'hours';

  @override
  String get aboutSecondsSuffix => 'sec';

  @override
  String get aboutBlocksSuffix => 'blocks';

  @override
  String get aboutFiatCurrenciesAll => 'All';

  @override
  String get aboutMostroPublicKeyExplanation =>
      'The Nostr public key of the Mostro daemon. All orders and encrypted messages on this instance are published or routed by this key.';

  @override
  String get aboutMaxOrderAmountExplanation =>
      'The maximum fiat amount allowed for a single order on this Mostro instance.';

  @override
  String get aboutMinOrderAmountExplanation =>
      'The minimum fiat amount required for a single order on this Mostro instance.';

  @override
  String get aboutOrderLifespanExplanation =>
      'How long a pending order stays open before it automatically expires if no taker is found.';

  @override
  String get aboutServiceFeeExplanation =>
      'The percentage of the trade amount charged by the Mostro daemon as a service fee.';

  @override
  String get aboutFiatCurrenciesExplanation =>
      'The fiat currencies accepted on this Mostro instance. \'All\' means there are no restrictions.';

  @override
  String get aboutMostroVersionExplanation =>
      'The version of the Mostro daemon software running this instance.';

  @override
  String get aboutMostroCommitExplanation =>
      'The Git commit hash of the Mostro daemon build, used to identify the exact software revision.';

  @override
  String get aboutOrderExpirationExplanation =>
      'The timeout in seconds after which a trade waiting for action (e.g. invoice or payment) is automatically canceled.';

  @override
  String get aboutHoldInvoiceExpExplanation =>
      'The time window in seconds during which the Lightning hold invoice must be settled.';

  @override
  String get aboutHoldInvoiceCltvExplanation =>
      'The CLTV delta (block count) used for hold invoices, controlling how long the HTLC can remain locked.';

  @override
  String get aboutInvoiceExpWindowExplanation =>
      'The time window in seconds within which the buyer must submit a Lightning invoice after the trade is initiated.';

  @override
  String get aboutProofOfWorkExplanation =>
      'The minimum proof-of-work difficulty required for Nostr events on this instance. 0 means no PoW is required.';

  @override
  String get aboutMaxOrdersPerResponseExplanation =>
      'The maximum number of orders returned in a single relay response. Limits bandwidth usage.';

  @override
  String get aboutLndVersionExplanation =>
      'The version of the LND (Lightning Network Daemon) node connected to this Mostro instance.';

  @override
  String get aboutLndNodePublicKeyExplanation =>
      'The public key of the LND node. Used to identify and verify the Lightning Network node.';

  @override
  String get aboutLndCommitExplanation =>
      'The Git commit hash of the LND build, identifying the exact software revision of the Lightning node.';

  @override
  String get aboutLndNodeAliasExplanation =>
      'The human-readable alias of the LND node as configured by the node operator.';

  @override
  String get aboutSupportedChainsExplanation =>
      'The blockchain(s) supported by the LND node (e.g. \'bitcoin\').';

  @override
  String get aboutSupportedNetworksExplanation =>
      'The network(s) the LND node operates on (e.g. \'mainnet\', \'testnet\').';

  @override
  String get aboutLndNodeUriExplanation =>
      'The connection URI of the LND node in the format pubkey@host:port. Used to open direct payment channels.';
}

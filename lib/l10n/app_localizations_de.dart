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
  String get actionFailedAnnouncement => 'Aktion fehlgeschlagen';

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
  String get disputeSolverNotAssigned =>
      'Noch hat kein Schlichter diesen Streitfall übernommen. Du kannst schreiben, sobald einer ihn übernimmt.';

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
  String get tabBuyBtc => 'BTC kaufen';

  @override
  String get tabSellBtc => 'BTC verkaufen';

  @override
  String get filterButtonLabel => 'Filtern';

  @override
  String filtersActiveCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Filter aktiv',
      one: '1 Filter aktiv',
    );
    return '$_temp0';
  }

  @override
  String get noOrdersAvailable => 'Keine Bestellungen verfügbar';

  @override
  String get justNow => 'gerade eben';

  @override
  String minutesAgo(int m) {
    return 'vor ${m}m';
  }

  @override
  String hoursAgo(int h) {
    return 'vor ${h}h';
  }

  @override
  String daysAgo(int d) {
    return 'vor ${d}T';
  }

  @override
  String get invoiceRejected =>
      'Der Node hat diese Rechnung abgelehnt. Prüfe Betrag und Ablauf und füge eine neue hinzu.';

  @override
  String get invoiceCopied => 'Rechnung kopiert';

  @override
  String get submitButtonLabel => 'Absenden';

  @override
  String get orderAlreadyTaken => 'Die Bestellung wurde bereits angenommen';

  @override
  String get nodeProtocolUnsupported =>
      'Dieser Mostro-Node nutzt eine Protokollversion, die diese App nicht unterstützt. Wähle in den Einstellungen einen anderen Node oder prüfe, ob ein App-Update verfügbar ist';

  @override
  String get nodeCapabilitiesUnknown =>
      'Es wird noch geprüft, was der ausgewählte Mostro-Node unterstützt. Versuche es gleich noch einmal';

  @override
  String get mostroMaintenanceMode =>
      'Der Mostro-Node, mit dem du verbunden bist, wird gerade gewartet. Versuche es später noch einmal oder verbinde dich in den Einstellungen mit einem anderen Mostro-Node';

  @override
  String get storageUnavailable =>
      'Die App kann keine Orders erstellen oder annehmen, solange ihre lokale Datenbank nicht verfügbar ist. Starte die App neu und versuche es erneut';

  @override
  String get orderIdCopied => 'Bestell-ID kopiert';

  @override
  String get comingSoonMessage => 'Demnächst verfügbar';

  @override
  String get tradeStatusActive => 'Aktiv';

  @override
  String get tradeStatusCompleted => 'Abgeschlossen';

  @override
  String get tradeStatusCancelled => 'Storniert';

  @override
  String get tradeStatusDisputed => 'Strittiger Trade';

  @override
  String get accountScreenTitle => 'Konto';

  @override
  String get secretWordsTitle => 'Geheime Wörter';

  @override
  String get privacyCardTitle => 'Datenschutz';

  @override
  String get reputationMode => 'Reputationsmodus';

  @override
  String get reputationModeSubtitle =>
      'Deine Trades zählen für deine öffentliche Reputation';

  @override
  String get fullPrivacyMode => 'Vollständiger Privatsphäre-Modus';

  @override
  String get fullPrivacyModeSubtitle =>
      'Jeder Trade nutzt eine neue Identität, ohne Reputation';

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
  String get importMnemonicDialogTitle => 'Geheime Wörter importieren';

  @override
  String get importMnemonicHintText => 'Gib deine 12 geheimen Wörter ein';

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
  String get showWordsButton => 'Wörter anzeigen';

  @override
  String get settingsScreenTitle => 'Einstellungen';

  @override
  String get languageSettingTitle => 'Sprache';

  @override
  String get appearanceSettingTitle => 'Erscheinungsbild';

  @override
  String get appearanceDialogTitle => 'Erscheinungsbild';

  @override
  String get allCurrencies => 'Alle Währungen';

  @override
  String get lightningAddressSettingTitle => 'Lightning-Adresse';

  @override
  String get nwcWalletSettingTitle => 'NWC-Wallet';

  @override
  String get relaysSettingTitle => 'Relays';

  @override
  String get pushNotificationsSettingTitle => 'Push-Benachrichtigungen';

  @override
  String get logReportSettingTitle => 'Protokollbericht';

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
  String get scanQrCodeTitle => 'QR-Code scannen';

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
  String get pasteQrCodeHeading => 'QR-Code-Inhalt einfügen';

  @override
  String get pasteButtonLabel => 'Einfügen';

  @override
  String get clipboardEmptyError => 'Zwischenablage ist leer';

  @override
  String get enterValueError => 'Bitte einen Wert eingeben';

  @override
  String get trustedBadgeLabel => 'Vertrauenswürdig';

  @override
  String get confirmButtonLabel => 'Bestätigen';

  @override
  String get selectMostroNode => 'Knoten wählen';

  @override
  String get addCustomNode => 'Eigenen Knoten hinzufügen';

  @override
  String get nodePubkeyFieldLabel => 'Öffentlicher Schlüssel';

  @override
  String get nodePubkeyFieldHint => '64-stelliges Hex oder npub…';

  @override
  String get nodeNameOptionalLabel => 'Name (optional)';

  @override
  String get invalidPubkeyFormat =>
      'Gib einen gültigen öffentlichen Schlüssel ein (64-stelliges Hex oder npub)';

  @override
  String get privateKeyNotAllowed =>
      'Das ist ein privater Schlüssel — teile ihn niemals. Gib den öffentlichen Schlüssel des Knotens ein';

  @override
  String get nodeAlreadyExists => 'Dieser Knoten ist bereits in der Liste';

  @override
  String get nodeAddedSuccess => 'Knoten hinzugefügt';

  @override
  String nodeSwitchedSuccess(String nodeName) {
    return 'Du verwendest jetzt $nodeName';
  }

  @override
  String get errorSwitchingNode => 'Knotenwechsel fehlgeschlagen';

  @override
  String get cannotRemoveActiveNode =>
      'Der aktive Knoten kann nicht entfernt werden — wechsle zuerst zu einem anderen Knoten';

  @override
  String get deleteCustomNodeTitle => 'Knoten entfernen';

  @override
  String get deleteCustomNodeMessage =>
      'Diesen eigenen Knoten aus deiner Liste entfernen?';

  @override
  String get deleteCustomNodeConfirm => 'Entfernen';

  @override
  String get nodeRemovedSuccess => 'Knoten entfernt';

  @override
  String get nodeStorageUnavailable =>
      'Die lokale Datenbank ist nicht bereit. Starte die App neu und versuche es erneut';

  @override
  String nodeSelectorSubtitle(String code) {
    return 'Aufträge und Währungen für $code, deine Währung';
  }

  @override
  String get nodeSelectorSubtitleNoCurrency => 'Offene Aufträge je Knoten';

  @override
  String nodeMissingCurrencyChip(String code) {
    return 'OHNE $code';
  }

  @override
  String get nodeOrdersNowLabel => 'Aufträge jetzt';

  @override
  String get nodeNoOrdersLabel => 'keine Aufträge';

  @override
  String nodeOrdersInCurrency(int count, String code) {
    return '· $count in $code';
  }

  @override
  String get nodeFeeLabel => 'Gebühr';

  @override
  String get nodeFeeTooltip =>
      'Mostro teilt die Gebühr zwischen beiden Parteien auf.';

  @override
  String get nodePerTradeLabel => 'pro Handel';

  @override
  String get nodeCustodyLightning => 'Lightning-Verwahrung';

  @override
  String nodeCustodyCashu(String mint) {
    return 'Cashu-Verwahrung · $mint';
  }

  @override
  String get nodeCustodyUnknown => 'Verwahrung —';

  @override
  String nodeBondPct(String pct) {
    return 'Kaution $pct%';
  }

  @override
  String get nodeBondNone => 'Keine Kaution';

  @override
  String nodeStatusOnline(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Aufträge',
      one: '1 Auftrag',
    );
    return 'Online · $_temp0';
  }

  @override
  String get nodeStatusNoUsefulOrders => 'Keine Aufträge in deinen Währungen';

  @override
  String nodeStatusUnreachable(String ago) {
    return 'Antwortet nicht · letztes Signal $ago';
  }

  @override
  String get nodeStatusUnreachableNoSignal => 'Antwortet nicht';

  @override
  String get nodeDisclaimerShort =>
      'Jeder Knoten wird von einem unabhängigen Dritten betrieben. Mostro haftet weder für dessen Verhalten noch für deine Geschäfte.';

  @override
  String get nodeVerifyKeyWarning =>
      'Prüfe den Schlüssel beim Betreiber. Ein gefälschter Knoten kann deine Aufträge sehen.';

  @override
  String get nodeInvalidPubkeyShort =>
      'Das ist kein gültiger öffentlicher Schlüssel.';

  @override
  String get nodeNameFieldHint => 'Lokaler Mostro';

  @override
  String get nodePubkeyCopied => 'Schlüssel kopiert';

  @override
  String get nodeNotSelectableOffline => 'Dieser Knoten antwortet nicht';

  @override
  String get nodeStatsLoading => 'Knotendaten werden geladen';

  @override
  String get nodeSwitchConfirmTitle => 'Knoten wechseln?';

  @override
  String nodeSwitchConfirmBody(String currentNode, String newNode) {
    return 'Du hast einen laufenden Handel auf $currentNode. Er bleibt dort; das Orderbuch zeigt jetzt $newNode.';
  }

  @override
  String get nodeSwitchConfirmAction => 'Knoten wechseln';

  @override
  String get nodeTradesCheckFailed =>
      'Deine Geschäfte konnten nicht geprüft werden. Versuch es erneut.';

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
  String get closeRatingButton => 'SCHLIESSEN';

  @override
  String get aboutScreenTitle => 'Über';

  @override
  String get linkCopiedToClipboard => 'Link in die Zwischenablage kopiert';

  @override
  String get pubkeyLabel => 'Öffentlicher Schlüssel';

  @override
  String get relaysLabel => 'Relays';

  @override
  String get footerTagline => 'Open-Source. Nicht-verwahrt. Privat.';

  @override
  String get drawerTitle => 'Mostro';

  @override
  String get drawerTagline => 'P2P-Handel';

  @override
  String get drawerStageBadge => 'Alpha';

  @override
  String drawerVersion(String version) {
    return 'Version $version';
  }

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
  String get backupRitualSecondFailureMessage =>
      'Das war erneut falsch. Bitte überprüfe und sichere deine geheimen Wörter und verifiziere dann von vorne.';

  @override
  String get cancelTradeDialogTitle => 'Handel abbrechen?';

  @override
  String get cancelTradeDialogContent =>
      'Kooperativen Abbruch angefragt. Die andere Partei muss ebenfalls zustimmen, damit der Handel vollständig abgebrochen wird.';

  @override
  String get cancelTradeDialogContentNotStarted =>
      'Der Handel hat noch nicht begonnen und wird daher sofort abgebrochen. Die andere Partei muss nicht zustimmen.';

  @override
  String get cancelTradeDialogContentMaybeStarted =>
      'Hat der Handel noch nicht begonnen, wird er sofort abgebrochen. Hat er bereits begonnen, muss die andere Partei ebenfalls zustimmen.';

  @override
  String get noButtonLabel => 'Nein';

  @override
  String get yesButtonLabel => 'Ja';

  @override
  String get yesCancelButtonLabel => 'Ja, abbrechen';

  @override
  String get cancelRequestSent => 'Abbruchanfrage gesendet';

  @override
  String get cancelRequestFailed =>
      'Abbrechen fehlgeschlagen. Bitte erneut versuchen.';

  @override
  String get tradeCardCancelRequestedByMeTitle => 'Stornierung angefragt';

  @override
  String get tradeCardCancelRequestedByMeMessage =>
      'Du hast die Stornierung dieses Handels angefragt. Er bleibt offen, bis die Gegenpartei ebenfalls storniert. Antwortet sie nicht, kannst du einen Streitfall eröffnen.';

  @override
  String get tradeCardCancelRequestedByPeerTitle =>
      'Die Gegenpartei möchte stornieren';

  @override
  String get tradeCardCancelRequestedByPeerMessage =>
      'Sie hat die Stornierung dieses Handels angefragt. Nimm an, um ihn ohne Geldbewegung zu beenden, oder handle weiter.';

  @override
  String get tradeCancelRequestedByMeNotice =>
      'Du hast die Stornierung dieses Handels angefragt. Er bleibt offen, bis die Gegenpartei ebenfalls storniert. Antwortet sie nicht, kannst du einen Streitfall eröffnen.';

  @override
  String get tradeCancelRequestedByPeerNotice =>
      'Die Gegenpartei hat die Stornierung dieses Handels angefragt. Nimm an, um ihn ohne Geldbewegung zu beenden, oder handle weiter.';

  @override
  String get acceptCancelButton => 'Stornierung annehmen';

  @override
  String get cancelTradeDialogContentAccept =>
      'Die Gegenpartei hat die Stornierung angefragt. Wenn du jetzt stornierst, endet der Handel für beide, ohne dass Geld bewegt wird.';

  @override
  String get fiatSentFailed =>
      'Fiat-Zahlung konnte nicht bestätigt werden. Bitte erneut versuchen.';

  @override
  String get releaseFailed =>
      'Freigabe fehlgeschlagen. Bitte erneut versuchen.';

  @override
  String get cancelTradeButton => 'Handel abbrechen';

  @override
  String get payHoldInvoiceButton => 'Hold-Rechnung bezahlen';

  @override
  String get openDisputeButton => 'Streitfall eröffnen';

  @override
  String get releaseSatsButton => 'Sats freigeben';

  @override
  String get confirmReleaseSatsButton => 'Bestätigen und Sats freigeben';

  @override
  String get shareOrderButton => 'Bestellung teilen';

  @override
  String get orderPillYouAreSelling => 'SIE VERKAUFEN';

  @override
  String get orderPillYouAreBuying => 'SIE KAUFEN';

  @override
  String get myOrderSellTitle => 'Deine Verkaufsorder';

  @override
  String get myOrderBuyTitle => 'Deine Kauforder';

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
  String get aboutDocumentationTitle => 'Dokumentation';

  @override
  String get aboutMostroNodeTitle => 'Mostro-Knoten';

  @override
  String get aboutVersionLabel => 'Version';

  @override
  String get aboutCommitHashLabel => 'Commit-Hash';

  @override
  String get aboutLicenseLabel => 'Lizenz';

  @override
  String get aboutLicenseName => 'AGPLv3+';

  @override
  String get aboutGithubRepoName => 'MostroP2P/app';

  @override
  String get aboutCopiedToClipboard => 'In die Zwischenablage kopiert';

  @override
  String get aboutLicenseDialogTitle => 'GNU Affero General Public License v3';

  @override
  String get aboutNodeLoadingText => 'Knoteninformationen werden geladen…';

  @override
  String get aboutNodeUnavailable => 'Knoteninformationen nicht verfügbar';

  @override
  String get aboutNodeRetry => 'Erneut versuchen';

  @override
  String get aboutLightningNetworkSection => 'Lightning-Netzwerk';

  @override
  String get aboutFiatCurrenciesLabel => 'Fiat-Währungen';

  @override
  String get aboutMostroVersionLabel => 'Mostro-Version';

  @override
  String get aboutMostroCommitLabel => 'Mostro-Commit';

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
  String get aboutSupportedChainsLabel => 'Unterstützte Chains';

  @override
  String get aboutSupportedNetworksLabel => 'Unterstützte Netzwerke';

  @override
  String get aboutSatoshisSuffix => 'Satoshis';

  @override
  String get aboutBlocksSuffix => 'Blöcke';

  @override
  String get aboutFiatCurrenciesAll => 'Alle';

  @override
  String get aboutAntiAbuseBondSection => 'Anti-Missbrauchs-Kaution';

  @override
  String get aboutBondEnabledValue => 'Aktiviert';

  @override
  String get aboutBondDisabledValue => 'Deaktiviert';

  @override
  String get aboutBondUnsupportedValue => 'Nicht unterstützt';

  @override
  String get aboutBondStatusLabel => 'Kautionsstatus';

  @override
  String get aboutBondAppliesToLabel => 'Gilt für';

  @override
  String get aboutBondAppliesToTakers => 'Annehmende Seite';

  @override
  String get aboutBondAppliesToMakers => 'Erstellende Seite';

  @override
  String get aboutBondAppliesToBoth => 'Beide Seiten';

  @override
  String get aboutBondAmountLabel => 'Kautionsbetrag';

  @override
  String get aboutBondBaseAmountLabel => 'Mindestkaution';

  @override
  String get aboutBondNodeShareLabel => 'Anteil des Knotens beim Einzug';

  @override
  String get aboutBondSlashOnTimeoutLabel => 'Einzug bei Zeitüberschreitung';

  @override
  String get aboutBondClaimWindowLabel =>
      'Frist für die Auszahlungsanforderung';

  @override
  String aboutBondClaimWindowValue(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Tage',
      one: '$count Tag',
    );
    return '$_temp0';
  }

  @override
  String get openDisputeFailed =>
      'Streit konnte nicht eröffnet werden. Bitte erneut versuchen.';

  @override
  String get openDisputeTitle => 'Streitfall eröffnen';

  @override
  String get openDisputeConfirmation =>
      'Möchtest du wirklich einen Streitfall eröffnen? Dies eskaliert den Handel an einen Administrator und kann nicht rückgängig gemacht werden.';

  @override
  String get disputeAlreadyOpen =>
      'Für diesen Handel ist bereits ein Streit eröffnet.';

  @override
  String get tradeNotDisputable =>
      'Ein Streit kann erst eröffnet werden, wenn die Gelder für diesen Handel gesperrt sind.';

  @override
  String get tradeWaitingInvoiceBuyerInstruction =>
      'Sende deine Lightning-Rechnung, damit der Verkäufer die Gelder sperren kann.';

  @override
  String get tradeWaitingInvoiceSellerInstruction =>
      'Warte auf die Lightning-Rechnung des Käufers.';

  @override
  String get tradeWaitingPaymentSellerInstruction =>
      'Bezahle die Hold-Rechnung, um die Gelder zu sperren und den Handel zu starten.';

  @override
  String get tradeLoadError =>
      'Beim Laden des Handels ist ein Fehler aufgetreten.';

  @override
  String get tradeWaitingForHoldInvoice => 'Warte auf Hold-Rechnung...';

  @override
  String get shareButtonLabel => 'Teilen';

  @override
  String get shareFailed => 'Rechnung konnte nicht geteilt werden';

  @override
  String get waitingForPaymentConfirmation =>
      'Warte auf Zahlungsbestätigung...';

  @override
  String get orderNoLongerActive => 'Diese Bestellung ist nicht mehr aktiv';

  @override
  String get tradeNoLongerYours =>
      'Du bist nicht mehr an diesem Handel beteiligt';

  @override
  String get sessionTimeoutMessage =>
      'Keine Antwort erhalten; prüfe deine Verbindung und versuche es später erneut';

  @override
  String get noRelayAcceptedMessage =>
      'Kein Relay hat deine Nachricht angenommen. Prüfe deine Relays in den Einstellungen und versuche es erneut';

  @override
  String get noIdentityFoundMessage =>
      'Keine Identität gefunden — versuche, die App neu zu starten.';

  @override
  String get failedToLoadSecretWordsMessage =>
      'Geheime Wörter konnten nicht geladen werden. Bitte versuche es erneut.';

  @override
  String get privacyModesInfoTitle => 'Datenschutzmodi';

  @override
  String get privacyModesInfoContent =>
      'Im Reputationsmodus können andere deine erfolgreichen Trades sehen.\n\nDer vollständige Datenschutzmodus hält deine Aktivität völlig anonym — es wird keine Reputation aufgebaut.';

  @override
  String get failedToGenerateIdentityMessage =>
      'Identität konnte nicht generiert werden. Bitte versuche es erneut.';

  @override
  String get invalidMnemonicMessage =>
      'Ungültige geheime Wörter. Bitte überprüfe deine Wörter und versuche es erneut.';

  @override
  String get enterValidMnemonicError => 'Gib deine 12 geheimen Wörter ein.';

  @override
  String get orderBookRefreshedMessage => 'Orderbuch aktualisiert';

  @override
  String get refreshFailedMessage => 'Aktualisierung fehlgeschlagen';

  @override
  String get refreshButtonLabel => 'Aktualisieren';

  @override
  String get okButtonLabel => 'OK';

  @override
  String get moreInformationTooltip => 'Weitere Informationen';

  @override
  String get backedUpBadgeLabel => 'Gesichert';

  @override
  String get backupBannerTitle => 'Sichere deine Reputation';

  @override
  String get backupBannerSubtitle =>
      'Sichere deine 12 Wörter — es dauert 60 Sekunden.';

  @override
  String get failedToSaveBackupStatusMessage =>
      'Sicherungsstatus konnte nicht gespeichert werden. Bitte versuche es erneut.';

  @override
  String get backupRitualStep1Title =>
      'Schritt 1 von 3 · Schreibe deine Wörter auf';

  @override
  String get backupRitualStep2Title => 'Schritt 2 von 3 · Überprüfen';

  @override
  String get backupRitualStep3Title => 'Schritt 3 von 3 · Fertig';

  @override
  String get backupRitualWarningTitle => 'Schreibe sie auf Papier. ';

  @override
  String get backupRitualWarningBody =>
      'Speichere sie nicht in Fotos, Screenshots oder der Cloud — wer diese 12 Wörter hat, kann deine Reputation stehlen.';

  @override
  String get wordsHiddenOnLeaveNote =>
      'Sie werden ausgeblendet, wenn du diesen Bildschirm verlässt';

  @override
  String get wroteThemDownVerifyButton =>
      'Ich habe sie aufgeschrieben — überprüfen';

  @override
  String get tapCorrectWordsTitle => 'Tippe auf die richtigen Wörter';

  @override
  String get verifyInstructionsBody =>
      'Wir fragen 3 zufällig ab. Wenn du sie richtig hast, wissen wir, dass sie sicher aufgeschrieben sind.';

  @override
  String optionsForWordLabel(int number) {
    return 'OPTIONEN FÜR WORT #$number';
  }

  @override
  String get wrongPickMessage =>
      'Nicht ganz — überprüfe dein Papier und versuche es erneut.';

  @override
  String get allWordsCorrectMessage => 'Alle 3 Wörter richtig';

  @override
  String get reviewWordsButton => 'Wörter ansehen';

  @override
  String get accountBackedUpTitle => 'Dein Konto ist gesichert';

  @override
  String get accountBackedUpBody =>
      'Deine Reputation ist sicher. Falls du dein Telefon verlierst, stelle dein Konto mit deinen 12 Wörtern wieder her.';

  @override
  String wordNumberLabel(int number) {
    return 'Wort #$number';
  }

  @override
  String get backupTriggerBody =>
      'Deine Reputation liegt in einem Schlüssel, den nur du besitzt. Wenn du dein Telefon verlierst, verlierst du diese Reputation — ';

  @override
  String get backupTriggerBodyHighlight => 'sichere ihn in 60 Sekunden.';

  @override
  String get backupStepWriteDown => 'Schreibe deine 12 Wörter auf Papier';

  @override
  String get backupStepVerifyRandom =>
      'Wir fragen 3 zufällig zur Bestätigung ab';

  @override
  String get backupStepSecured => 'Fertig — dein Konto ist gesichert';

  @override
  String get backupNowButton => 'Jetzt sichern';

  @override
  String get backupLaterButton => 'Mache ich später';

  @override
  String get nwcConnectionFailedMessage =>
      'Verbindung fehlgeschlagen. Bitte überprüfe deine NWC-URI und versuche es erneut.';

  @override
  String get clipboardInvalidNwcUriMessage =>
      'Die Zwischenablage enthält keine gültige NWC-URI.';

  @override
  String get scanQrButtonLabel => 'QR scannen';

  @override
  String get connectButtonLabel => 'Verbinden';

  @override
  String get walletDisconnectedMessage => 'Wallet getrennt';

  @override
  String get relayLabel => 'Relay';

  @override
  String get disconnectButtonLabel => 'Trennen';

  @override
  String relaysMoreSuffix(int count) {
    return '(+$count weitere)';
  }

  @override
  String get chooseNotificationEventsSubtitle =>
      'Wähle, welche Ereignisse eine Benachrichtigung in der App anzeigen.';

  @override
  String get notifTradeUpdatesTitle => 'Trade-Updates';

  @override
  String get notifTradeUpdatesSubtitle =>
      'Statusänderungen bei deinen aktiven Trades';

  @override
  String get notifNewMessagesTitle => 'Neue Nachrichten';

  @override
  String get notifNewMessagesSubtitle =>
      'Nachrichten von deiner Handelsgegenpartei';

  @override
  String get notifPaymentAlertsTitle => 'Zahlungshinweise';

  @override
  String get notifPaymentAlertsSubtitle =>
      'Bestätigungen und Fehler von Lightning-Zahlungen';

  @override
  String get notifDisputeUpdatesTitle => 'Streitfall-Updates';

  @override
  String get notifDisputeUpdatesSubtitle =>
      'Admin-Aktionen und Streitbeilegungen';

  @override
  String get searchCurrenciesHint => 'Währungen suchen…';

  @override
  String get noCurrenciesFoundMessage => 'Keine Währungen gefunden';

  @override
  String get shareLogsTooltip => 'Protokolle teilen';

  @override
  String get noLogsToShareTooltip => 'Keine Protokolle zum Teilen';

  @override
  String get noLogEntriesMessage => 'Keine Protokolleinträge';

  @override
  String get failedToShareLogsMessage =>
      'Protokolle konnten nicht geteilt werden';

  @override
  String get logReportShareHeading => 'Mostro-Protokollbericht';

  @override
  String get tradeFilterAll => 'Alle';

  @override
  String get tradeFilterPending => 'Ausstehend';

  @override
  String get tradeFilterWaitingInvoice => 'Warte auf Rechnung';

  @override
  String get tradeFilterWaitingPayment => 'Warte auf Zahlung';

  @override
  String get tradeFilterActive => 'Aktiv';

  @override
  String get tradeFilterFiatSent => 'Fiat gesendet';

  @override
  String get tradeFilterSuccess => 'Erfolgreich';

  @override
  String get tradeFilterCanceled => 'Storniert';

  @override
  String get tradeFilterDispute => 'Streitfall';

  @override
  String get menuTooltip => 'Menü';

  @override
  String get noTradesTitle => 'Keine Trades';

  @override
  String get noTradesSubtitle =>
      'Deine aktiven und abgeschlossenen Trades erscheinen hier.';

  @override
  String get couldNotLoadTradesMessage => 'Trades konnten nicht geladen werden';

  @override
  String get sellingBitcoin => 'Bitcoin verkaufen';

  @override
  String get buyingBitcoin => 'Bitcoin kaufen';

  @override
  String get tradeInstructionActiveBuyer =>
      'Sobald du das Geld gesendet hast, markiere es unten. Öffne nur einen Streitfall, wenn der Verkäufer nicht mehr antwortet.';

  @override
  String get tradeInstructionFiatSentBuyer =>
      'Fiat-Zahlung als gesendet markiert. Warte darauf, dass der Verkäufer den Empfang bestätigt und deine Sats freigibt.';

  @override
  String get tradeInstructionActiveSeller =>
      'Kontaktiere den Käufer mit den Zahlungsanweisungen über den Chat oben.';

  @override
  String get tradeInstructionFiatSentSeller =>
      'Der Käufer hat bestätigt, die Fiat-Zahlung gesendet zu haben. Sobald du den Empfang prüfst, gib die Sats frei.';

  @override
  String get tradeInstructionDisputed =>
      'Ein Streitschlichter wurde zugewiesen. Er wird dich über die App kontaktieren.';

  @override
  String get tradeInstructionPending =>
      'Deine Bestellung ist veröffentlicht und wartet auf eine Gegenpartei. Du kannst sie jederzeit stornieren.';

  @override
  String get tradeInstructionCancelled =>
      'Dieser Trade wurde storniert. Es wurden keine Gelder ausgetauscht.';

  @override
  String get tradeInstructionInProgress => 'Trade läuft.';

  @override
  String get theAgreedAmount => 'den vereinbarten Betrag';

  @override
  String get tradeHeadlinePending =>
      'Warte darauf, dass jemand deine Bestellung annimmt';

  @override
  String get tradeHeadlineInProgress => 'Der Handel wird vorbereitet';

  @override
  String get tradeHeadlineWaitingInvoiceBuyer =>
      'Teile eine Lightning-Rechnung, um deine Sats zu erhalten';

  @override
  String get tradeHeadlineWaitingInvoiceSeller =>
      'Warte darauf, dass der Käufer eine Rechnung teilt';

  @override
  String get tradeHeadlineWaitingPaymentBuyer =>
      'Warte darauf, dass der Verkäufer die Sats sperrt';

  @override
  String get tradeHeadlineWaitingPaymentSeller =>
      'Bezahle die Hold-Invoice, um die Sats zu sperren';

  @override
  String tradeHeadlineActiveBuyer(String amount) {
    return 'Sende $amount an den Verkäufer';
  }

  @override
  String tradeHeadlineActiveSeller(String amount) {
    return 'Warte darauf, dass der Käufer $amount sendet';
  }

  @override
  String get tradeHeadlineFiatSentBuyer =>
      'Warte darauf, dass der Verkäufer deine Sats freigibt';

  @override
  String tradeHeadlineFiatSentSeller(String amount) {
    return 'Bestätige, dass du $amount erhalten hast';
  }

  @override
  String get tradeHeadlineDisputed => 'Streitfall läuft';

  @override
  String get tradeHeadlineCancelled => 'Bestellung storniert';

  @override
  String get tradeHeadlineLoading => 'Trade wird geladen…';

  @override
  String get tradeTimerPendingConsequence =>
      'Bei Ablauf wird die Bestellung aus dem Buch entfernt. Es wirkt sich nicht auf deine Reputation aus.';

  @override
  String get tradeTimerWaitingInvoiceConsequence =>
      'Bei Ablauf wird der Trade storniert und die Bestellung kehrt ins Buch zurück.';

  @override
  String get tradeStepOrderTaken => 'Bestellung angenommen';

  @override
  String get tradeStepInvoiceBuyer => 'Der Verkäufer sperrt die Sats';

  @override
  String get tradeStepInvoiceSeller => 'Du sperrst die Sats';

  @override
  String get tradeStepFiatBuyer => 'Du sendest die Fiat-Zahlung';

  @override
  String get tradeStepFiatSeller => 'Der Käufer sendet die Fiat-Zahlung';

  @override
  String get tradeStepReleaseBuyer => 'Der Verkäufer gibt deine Sats frei';

  @override
  String get tradeStepReleaseSeller => 'Du bestätigst und gibst die Sats frei';

  @override
  String get tradeStepRate => 'Ihr bewertet den Handel';

  @override
  String tradeCreatedAtLabel(String date) {
    return 'erstellt $date';
  }

  @override
  String stepIndicator(int current, int total) {
    return 'SCHRITT $current VON $total';
  }

  @override
  String get addLightningInvoiceButton => 'Lightning-Rechnung hinzufügen';

  @override
  String get viewDisputeButton => 'Streitfall ansehen';

  @override
  String get yourTradeTimelineTitle => 'DEIN TRADE';

  @override
  String get messageSendFailed =>
      'Nachricht konnte nicht gesendet werden. Bitte versuche es erneut.';

  @override
  String get invalidTradeId => 'Ungültige Trade-ID';

  @override
  String get selectForDetailsHint => 'Wähle ℹ oder 👤\nfür Details';

  @override
  String noMessagesYet(String handle) {
    return 'Noch keine Nachrichten.\nSag $handle hallo!';
  }

  @override
  String get exchangeInfoTooltip => 'Tausch-Info';

  @override
  String get userInfoTooltip => 'Benutzer-Info';

  @override
  String chattingWith(String handle) {
    return 'Du chattest mit $handle';
  }

  @override
  String get unknownPeerHandle => 'Unbekannt';

  @override
  String get messagesTab => 'Nachrichten';

  @override
  String get disputesTab => 'Streitfälle';

  @override
  String get tradeInformationTitle => 'Trade-Informationen';

  @override
  String get orderIdLabel => 'Bestell-ID';

  @override
  String get fiatAmountLabel => 'Fiat-Betrag';

  @override
  String get satsAmountLabel => 'Sats-Betrag';

  @override
  String get statusLabel => 'Status';

  @override
  String get paymentMethodLabel => 'Zahlungsmethode';

  @override
  String get createdLabel => 'Erstellt';

  @override
  String get tradeDetailsPlaceholder =>
      'Details verfügbar, sobald der Trade-Provider bereit ist (Phase 10+)';

  @override
  String get userInformationTitle => 'Benutzerinformationen';

  @override
  String get peerPublicKeyLabel => 'Öffentlicher Schlüssel des Partners';

  @override
  String get yourSharedKeyLabel => 'Dein gemeinsamer Schlüssel';

  @override
  String get sharedKeyPlaceholder =>
      'Verfügbar nach der Bridge-Integration (Phase 10+)';

  @override
  String get sharedKeySafetyNote =>
      'Bewahre deinen gemeinsamen Schlüssel sicher auf — er wird für die Streitbeilegung benötigt';

  @override
  String get fileTypeVideo => 'Video';

  @override
  String get fileTypeImage => 'Bild';

  @override
  String get fileTypeArchive => 'Archiv';

  @override
  String get fileTypeFile => 'Datei';

  @override
  String buyingSatsAmount(String sats) {
    return 'Kaufe $sats Sats';
  }

  @override
  String sellingSatsAmount(String sats) {
    return 'Verkaufe $sats Sats';
  }

  @override
  String get viewOrderLink => 'Bestellung ansehen';

  @override
  String timeLeftLabel(String time) {
    return '$time übrig';
  }

  @override
  String get invoiceNoLongerExpected =>
      'Diese Order wartet nicht mehr auf eine Rechnung. Status wird aktualisiert…';

  @override
  String get invoiceSubmitInFlight =>
      'Für diese Order wird bereits eine Rechnung gesendet. Warte auf die Antwort.';

  @override
  String get waitingForTradeAmount =>
      'Warte auf den Trade-Betrag — bitte versuche es gleich noch einmal.';

  @override
  String get fetchingTradeAmount => 'Trade-Betrag wird abgerufen…';

  @override
  String get enterInvoiceManually => 'Rechnung manuell eingeben';

  @override
  String get submitButton => 'Absenden';

  @override
  String get buyerReputation => 'Reputation des Käufers';

  @override
  String get sellerReputation => 'Reputation des Verkäufers';

  @override
  String get ratingStatLabel => 'Bewertung';

  @override
  String get tradesStatLabel => 'Trades';

  @override
  String get daysActiveStatLabel => 'Tage aktiv';

  @override
  String timeRemainingLabel(String time) {
    return 'Verbleibende Zeit: $time';
  }

  @override
  String orderAmountOutOfRange(int min, int max) {
    return 'Der Betrag muss für diesen Mostro-Knoten zwischen $min und $max Sats liegen';
  }

  @override
  String orderAmountOutOfRangeFiat(int min, int max, String currency) {
    return 'Der Betrag muss für diesen Mostro-Knoten zwischen $min und $max $currency liegen';
  }

  @override
  String get priceTypeMarket => 'Markt';

  @override
  String get priceTypeFixed => 'Fest';

  @override
  String get priceTypeInfoTooltip => 'Info zum Preistyp';

  @override
  String get premiumSectionLabel => 'Aufschlag';

  @override
  String get fixedPriceRangeNotAvailable =>
      'Festpreis ist für Bereichsangebote nicht verfügbar. Deaktiviere den Bereich, um einen Festpreis zu verwenden.';

  @override
  String get priceTypesDialogTitle => 'Preistypen';

  @override
  String get priceTypesDialogContent =>
      'Marktpreis: Der Preis deiner Order folgt dem Marktkurs mit einem angewendeten Aufschlag/Abschlag-Prozentsatz.\n\nFestpreis: Du legst einen genauen Preis in Satoshis fest.';

  @override
  String get newOrderTitle => 'Neue Order';

  @override
  String get amountSectionSell => 'Wie viel du verkaufst';

  @override
  String get amountSectionBuy => 'Wie viel du kaufst';

  @override
  String get amountModeSingle => 'Einzeln';

  @override
  String get amountModeRange => 'Bereich';

  @override
  String get amountMinLabel => 'Minimum';

  @override
  String get amountMaxLabel => 'Maximum';

  @override
  String paymentMethodsChosenCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count gewählt',
      one: '1 gewählt',
      zero: 'keine gewählt',
    );
    return '$_temp0';
  }

  @override
  String get paymentMethodAdd => 'Hinzufügen';

  @override
  String get paymentMethodSearchHint => 'Methoden suchen';

  @override
  String get customPaymentMethodLabel => 'Eigene Zahlungsmethode';

  @override
  String get priceSectionTitle => 'Preis';

  @override
  String premiumSellAbove(String premium) {
    return 'Du verkaufst $premium% über dem Marktpreis';
  }

  @override
  String premiumSellBelow(String premium) {
    return 'Du verkaufst $premium% unter dem Markt';
  }

  @override
  String premiumBuyBelow(String premium) {
    return 'Du zahlst $premium% weniger als der Markt';
  }

  @override
  String premiumBuyAbove(String premium) {
    return 'Du zahlst $premium% mehr';
  }

  @override
  String get premiumExactMarket => 'Exakter Marktpreis';

  @override
  String get fixedPriceNote =>
      'Bei Festpreis folgt die Order nicht dem Markt: der Sats-Betrag bleibt genau so, wie du ihn eingibst.';

  @override
  String get previewHintNoAmount =>
      'Gib einen Betrag ein und du siehst hier, wie die Order aussieht.';

  @override
  String previewSellMarket(String amount, String premium, String active) {
    return 'Du verkaufst BTC für $amount zum Marktpreis $premium$active';
  }

  @override
  String previewSellMarketExact(String amount, String active) {
    return 'Du verkaufst BTC für $amount zum Marktpreis$active';
  }

  @override
  String previewBuyMarket(String amount, String premium, String active) {
    return 'Du kaufst BTC für $amount zum Marktpreis $premium$active';
  }

  @override
  String previewBuyMarketExact(String amount, String active) {
    return 'Du kaufst BTC für $amount zum Marktpreis$active';
  }

  @override
  String previewSellFixed(String sats, String amount, String active) {
    return 'Du verkaufst $sats für $amount zum Festpreis$active';
  }

  @override
  String previewBuyFixed(String sats, String amount, String active) {
    return 'Du kaufst $sats für $amount zum Festpreis$active';
  }

  @override
  String previewActiveSuffix(String hours) {
    return ' · $hours aktiv';
  }

  @override
  String get publishOrder => 'Order veröffentlichen';

  @override
  String removePaymentMethod(String method) {
    return '$method entfernen';
  }

  @override
  String get satsUnitLabel => 'Sats';

  @override
  String satsAmount(String amount) {
    return '$amount sats';
  }

  @override
  String durationHours(int hours) {
    return '$hours h';
  }

  @override
  String get paymentMethodsLabel => 'Zahlungsmethoden';

  @override
  String get customPaymentMethodHint => 'Eigene Zahlungsmethode...';

  @override
  String amountRangeError(String min, String max) {
    return 'Der Betrag muss zwischen $min und $max liegen';
  }

  @override
  String get enterAmountTitle => 'Betrag eingeben';

  @override
  String minMaxRangeLabel(String min, String max, String currency) {
    return 'Min: $min – Max: $max $currency';
  }

  @override
  String get ratingFailed =>
      'Bewertung fehlgeschlagen. Bitte versuche es erneut.';

  @override
  String get submitUppercaseButton => 'ABSENDEN';

  @override
  String selectStarTooltip(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Sterne auswählen',
      one: '1 Stern auswählen',
    );
    return '$_temp0';
  }

  @override
  String get disputeDetailsTitle => 'Streitfall-Details';

  @override
  String get disputeIdLabel => 'Streitfall-ID';

  @override
  String disputeReasonLabel(String reason) {
    return 'Grund: $reason';
  }

  @override
  String get adminLabel => 'Administrator';

  @override
  String get disputeScreenTitle => 'Streitfall';

  @override
  String get filtersDialogTitle => 'Filter';

  @override
  String get resetButton => 'Zurücksetzen';

  @override
  String get currencyLabel => 'Währung';

  @override
  String get ratingLabel => 'Bewertung';

  @override
  String get applyButton => 'Anwenden';

  @override
  String get successLabel => 'Erfolg';

  @override
  String get copyButton => 'Kopieren';

  @override
  String get shareButton => 'Teilen';

  @override
  String sendSatsToAddress(String sats) {
    return 'Sende $sats Sats an:';
  }

  @override
  String get changeButton => 'Ändern';

  @override
  String get unableToOpenNotification =>
      'Benachrichtigungsdetails können nicht geöffnet werden.';

  @override
  String get reasonBestPremium => 'Beste Prämie';

  @override
  String get reasonMostReputable => 'Am angesehensten';

  @override
  String get marketPriceCaption => 'Marktpreis';

  @override
  String reputationTradesLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Trades',
      one: 'Trade',
    );
    return '$_temp0';
  }

  @override
  String reputationDaysLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Tage',
      one: 'Tag',
    );
    return '$_temp0';
  }

  @override
  String get sortNewest => 'Neueste';

  @override
  String ordersCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Orders',
      one: '1 Order',
    );
    return '$_temp0';
  }

  @override
  String get sortBestPremium => 'Beste Prämie';

  @override
  String get sortBestReputation => 'Beste Reputation';

  @override
  String get sortSheetTitle => 'Sortieren nach';

  @override
  String get orderCardPremiumCaption => 'Prämie';

  @override
  String orderFixedAmount(String sats) {
    return 'Fester Betrag · für $sats';
  }

  @override
  String get reputationNew => 'Neu';

  @override
  String get reputationNoTrades => 'keine Trades';

  @override
  String get bottomNavBook => 'Orderbuch';

  @override
  String get bottomNavTrades => 'Trades';

  @override
  String get fabDismissHint => 'Zum Schließen außerhalb tippen';

  @override
  String get addOrderFabLabel => 'Order erstellen';

  @override
  String get ordersEmptyHint =>
      'Neue Orders erscheinen hier, sobald sie veröffentlicht werden.';

  @override
  String get ordersEmptyFilteredHint =>
      'Keine Orders entsprechen Ihren Filtern.';

  @override
  String get clearFiltersButton => 'Filter entfernen';

  @override
  String get hideEarlierEvents => 'Frühere Ereignisse ausblenden';

  @override
  String viewEarlierEvents(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count frühere Ereignisse anzeigen',
      one: '1 früheres Ereignis anzeigen',
    );
    return '$_temp0';
  }

  @override
  String get goToTrade => 'Zum Trade';

  @override
  String get disputeWord => 'Streitfall';

  @override
  String get tradeWord => 'Trade';

  @override
  String get notifFilterAll => 'Alle';

  @override
  String get notifFilterDisputes => 'Streitfälle';

  @override
  String notifFilterDisputesCount(int count) {
    return 'Streitfälle · $count';
  }

  @override
  String get notifFilterSystem => 'System';

  @override
  String notifFilterSystemCount(int count) {
    return 'System · $count';
  }

  @override
  String get payingStatus => 'Zahlung läuft...';

  @override
  String get payWithWalletButton => 'Mit Wallet bezahlen';

  @override
  String get generatingInvoiceNwc => 'Rechnung wird über NWC erstellt...';

  @override
  String get unableToGenerateInvoice =>
      'Rechnung konnte nicht automatisch erstellt werden';

  @override
  String get avatarIconLabel => 'Avatar-Symbol';

  @override
  String get disputeDescResolvedBuyerFavour =>
      'Streitfall zugunsten des Käufers entschieden';

  @override
  String get disputeDescResolvedYourFavour =>
      'Streitfall zu deinen Gunsten entschieden';

  @override
  String get disputeDescResolvedSellerFavour =>
      'Streitfall zugunsten des Verkäufers entschieden';

  @override
  String get disputeDescCooperativeCancel => 'Bestellung kooperativ storniert';

  @override
  String get disputeDescResolved => 'Streitfall gelöst';

  @override
  String get disputeDescYouOpened => 'Du hast diesen Streitfall eröffnet';

  @override
  String get disputeDescCounterpartOpened =>
      'Die Gegenpartei hat diesen Streitfall eröffnet';

  @override
  String get notificationsBellNoUnread =>
      'Benachrichtigungen, keine ungelesenen Benachrichtigungen';

  @override
  String get notificationsBellBackupActive =>
      'Benachrichtigungen, Backup-Erinnerung aktiv';

  @override
  String notificationsBellUnread(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Benachrichtigungen, $count ungelesen',
      one: 'Benachrichtigungen, 1 ungelesen',
    );
    return '$_temp0';
  }

  @override
  String drawerBadgeNewCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count neu',
      one: '1 neu',
    );
    return '$_temp0';
  }

  @override
  String get bondSlashedViewPolicy => 'Richtlinie ansehen';

  @override
  String get bondSlashedViewTrade => 'Handel ansehen';

  @override
  String bondSlashedTradeNoticeDispute(String sats) {
    return 'Der Node hat deine Einlage von $sats Sats in diesem Streitfall eingezogen.';
  }

  @override
  String bondSlashedTradeNoticeTimeout(String sats) {
    return 'Der Node hat deine Einlage von $sats Sats eingezogen, weil ein Schritt abgelaufen ist.';
  }

  @override
  String get bondSlashedTitle => 'Kaution eingezogen';

  @override
  String bondSlashedMessageTimeout(String amount, String orderId) {
    return 'Deine Anti-Missbrauchs-Kaution von $amount Sats für Bestellung $orderId wurde nach einer Zeitüberschreitung im Wartezustand eingezogen. Der Status deiner Bestellung bleibt unverändert.';
  }

  @override
  String bondSlashedMessageDispute(String amount, String orderId) {
    return 'Deine Anti-Missbrauchs-Kaution von $amount Sats für Bestellung $orderId wurde nach der Beilegung eines Streits eingezogen. Der Status deiner Bestellung bleibt unverändert.';
  }

  @override
  String get bondSlashedCauseTimeout => 'Zeitüberschreitung im Wartezustand';

  @override
  String get bondSlashedCauseDispute => 'Streitbeilegung';

  @override
  String get bondSlashedDetailOrder => 'Bestellung';

  @override
  String get bondSlashedDetailAmount => 'Kautionsbetrag';

  @override
  String get bondSlashedDetailCause => 'Grund';

  @override
  String get bondSlashedDetailFiat => 'Fiat';

  @override
  String get bondSlashedDetailPaymentMethod => 'Zahlungsmethode';

  @override
  String aboutDaysValue(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Tage',
      one: '$count Tag',
    );
    return '$_temp0';
  }

  @override
  String get aboutCashuEscrowSection => 'Cashu-Treuhand';

  @override
  String get aboutCashuMintUrlLabel => 'Mint';

  @override
  String get aboutCashuMintNotAdvertised => 'Nicht angegeben';

  @override
  String get aboutCashuLocktimeLabel => 'Treuhand-Sperrfrist';

  @override
  String get aboutCashuSettlementMarginLabel => 'Abwicklungspuffer';

  @override
  String get escrowModeLightning => 'Lightning';

  @override
  String get escrowModeCashu => 'Cashu';

  @override
  String get escrowModeUnknown => 'Nicht angegeben';

  @override
  String get settingsEscrowOverrideTitle => 'Treuhand-Backend (Entwicklung)';

  @override
  String get settingsEscrowOverrideSubtitle =>
      'Cashu gegen einen Node testen, der es noch nicht angibt. Nur in Debug-Builds.';

  @override
  String get settingsForceCashuLabel => 'Cashu-Treuhand erzwingen';

  @override
  String get settingsCashuMintOverrideLabel => 'Abweichende Mint-URL';

  @override
  String get settingsCashuMintOverrideApply => 'Übernehmen';

  @override
  String get settingsCashuMintOverrideInvalid =>
      'Das ist keine gültige Mint-URL. Verwende http oder https mit einem Host.';

  @override
  String settingsEscrowEffectiveMode(String mode) {
    return 'Effektives Backend: $mode';
  }

  @override
  String settingsEscrowEffectiveMint(String mint) {
    return 'Effektive Mint: $mint';
  }

  @override
  String get settingsEscrowCashuUnavailable =>
      'Cashu funktioniert ohne Mint nicht – unten eine festlegen.';

  @override
  String get tradeStatusPayoutPending => 'Auszahlung ausstehend';

  @override
  String get tradeHeadlinePayoutPending =>
      'Warten auf die Auszahlung an den Käufer';

  @override
  String get tradeInstructionPayoutPending =>
      'Der Verkäufer hat die Treuhandmittel freigegeben. Die Lightning-Zahlung an den Käufer steht noch aus.';

  @override
  String get tradeScreenTitle => 'Dein Handel';

  @override
  String get tradeChipWaiting => 'WARTEN';

  @override
  String get tradeChipActive => 'AKTIV';

  @override
  String get tradeChipYourTurn => 'DU BIST DRAN';

  @override
  String get tradeChipDispute => 'STREITFALL';

  @override
  String get tradeChatLockedNote =>
      'Noch kein Chat: Bis der Handel aktiv ist, weiß keine Seite, wer die andere ist.';

  @override
  String get tradeChatEncrypted => 'Ende-zu-Ende-verschlüsselter Chat';

  @override
  String get tradeBodyWaitingPaymentBuyer =>
      'Der Verkäufer bezahlt die Hold-Rechnung. Sobald die Sats gesperrt sind, bist du mit der Fiat-Zahlung dran.';

  @override
  String tradeBodyActiveSeller(String method) {
    return 'Teile deine $method-Daten im Chat oben.';
  }

  @override
  String tradeBodyActiveBuyer(String method) {
    return 'Per $method, mit den Daten aus dem Chat. Sobald du gezahlt hast, bestätige es unten.';
  }

  @override
  String tradeBodyFiatSentSeller(String method) {
    return 'Der Käufer hat die Zahlung als gesendet markiert. Prüfe dein $method-Konto, bevor du freigibst.';
  }

  @override
  String get tradeReleaseIrreversible =>
      'Das Freigeben der Sats lässt sich nicht rückgängig machen.';

  @override
  String get tradeTimerYouHave => 'Du hast noch';

  @override
  String get tradeTimerTheyHave => 'Gegenseite hat noch';

  @override
  String get tradeTimerOrderHas => 'Verbleibend';

  @override
  String get tradeTimerNoteCoordinate =>
      'Wenn ihr mehr Zeit braucht, sprecht es im Chat ab, bevor sie abläuft.';

  @override
  String get tradeRoleBuyer => 'Käufer';

  @override
  String get tradeRoleSeller => 'Verkäufer';

  @override
  String reputationTradesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Handel',
      one: '1 Handel',
    );
    return '$_temp0';
  }

  @override
  String reputationDaysOnMostro(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Tage bei Mostro',
      one: '1 Tag bei Mostro',
    );
    return '$_temp0';
  }

  @override
  String get tradeFiatSentAction => 'Ich habe bezahlt';

  @override
  String get tradeCloseAction => 'Schließen';

  @override
  String get tradeSendRatingAction => 'Bewertung senden';

  @override
  String get tradeCompletedTitle => 'Handel abgeschlossen';

  @override
  String tradeRatedCounterpart(String alias, String score) {
    return 'Du hast $alias mit $score bewertet';
  }

  @override
  String get tradeIdLabel => 'ID';

  @override
  String tradeCreatedTodayLabel(String time) {
    return 'erstellt heute $time';
  }

  @override
  String get releaseSheetTitle => 'Sats freigeben?';

  @override
  String get releaseSheetBody =>
      'Das lässt sich nicht rückgängig machen. Gib nur frei, wenn das Geld bereits auf deinem Konto ist.';

  @override
  String get releaseSheetConfirm => 'Ja, freigeben';

  @override
  String get releaseSheetBack => 'Zurück';

  @override
  String get orderSideChipSell => 'Du verkaufst BTC';

  @override
  String get orderSideChipBuy => 'Du kaufst BTC';

  @override
  String orderDetailMarketPremium(String premium) {
    return 'Marktpreis · $premium Aufschlag';
  }

  @override
  String myOrderWaitingNote(String ago) {
    return 'Veröffentlicht $ago. Wir sagen dir Bescheid, sobald jemand sie annimmt: Du kannst diesen Bildschirm schließen.';
  }

  @override
  String get orderStatusTakenWaitingInvoice =>
      'Angenommen · warte auf Rechnung';

  @override
  String get orderStatusTakenWaitingPayment => 'Angenommen · warte auf Zahlung';

  @override
  String get orderDetailCreatedLabel => 'Erstellt';

  @override
  String get orderDetailIdLabel => 'ID';

  @override
  String paymentMethodsMore(String first, int count) {
    return '$first +$count';
  }

  @override
  String get paymentMethodsSheetTitle => 'Zahlungsmethoden';

  @override
  String get cancelOrderSheetTitle => 'Order abbrechen?';

  @override
  String get cancelOrderSheetBody =>
      'Sie wird aus dem Orderbuch entfernt; das lässt sich nicht rückgängig machen.';

  @override
  String get goBackButtonLabel => 'Zurück';

  @override
  String get takeOrderYouPay => 'Du zahlst';

  @override
  String get takeOrderYouReceive => 'Du erhältst';

  @override
  String get takeOrderYouSend => 'Du sendest';

  @override
  String takeOrderSatsFrom(String sats) {
    return 'ab $sats';
  }

  @override
  String takeOrderMarketFooter(String premium) {
    return 'Marktpreis · $premium Aufschlag. Der endgültige Betrag wird beim Annehmen festgelegt.';
  }

  @override
  String takeOrderFixedFooterSeller(String sats) {
    return 'Fester Betrag · der Verkäufer verlangt $sats';
  }

  @override
  String takeOrderFixedFooterBuyer(String sats) {
    return 'Fester Betrag · der Käufer bietet $sats';
  }

  @override
  String get counterpartySeller => 'Verkäufer';

  @override
  String get counterpartyBuyer => 'Käufer';

  @override
  String counterpartyTrades(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Handel',
      one: '$count Handel',
    );
    return '$_temp0';
  }

  @override
  String counterpartyDaysOnMostro(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Tage bei Mostro',
      one: '$count Tag bei Mostro',
    );
    return '$_temp0';
  }

  @override
  String get takeOrderPayWithLabel => 'Du zahlst mit';

  @override
  String get takeOrderPaidWithLabel => 'Du wirst bezahlt mit';

  @override
  String get takeOrderPublishedLabel => 'Veröffentlicht';

  @override
  String get takeOrderNoteBuyer =>
      'Wenn du sie annimmst, sperrt der Verkäufer die Sats in Mostro. Du zahlst erst, wenn sie gesperrt sind.';

  @override
  String get takeOrderNoteSeller =>
      'Wenn du sie annimmst, sperrst du die Sats in Mostro. Der Käufer zahlt danach.';

  @override
  String get takeOrderButton => 'Order annehmen';

  @override
  String get takeOrderTaking => 'Wird angenommen…';

  @override
  String get takeOrderUnavailable => 'Nicht mehr verfügbar';

  @override
  String get takeOrderClosed => 'Geschlossen';

  @override
  String get easterEggWhitepaper =>
      '31. Oktober 2008: neun Seiten, niemandes Erlaubnis. Frohes Halloween.';

  @override
  String get easterEggGenesis =>
      'The Times 03/Jan/2009 Chancellor on brink of second bailout for banks';

  @override
  String get easterEggPizzaDay =>
      '22. Mai 2010: 10.000 BTC für zwei Pizzen. Hoffentlich haben sie geschmeckt.';

  @override
  String get settingsGroupApp => 'Anwendung';

  @override
  String get settingsGroupPayments => 'Zahlungen';

  @override
  String get settingsGroupNetwork => 'Netzwerk';

  @override
  String get settingsGroupHelp => 'Hilfe';

  @override
  String get fiatCurrencySettingTitle => 'Fiat-Währung';

  @override
  String notificationsEnabledOfTotal(int count, int total) {
    return '$count von $total';
  }

  @override
  String get notificationsAllOff => 'Aus';

  @override
  String get lightningAddressUnset => 'Nicht eingerichtet';

  @override
  String get nwcWalletNotConnected => 'Nicht verbunden';

  @override
  String relaysConnectedOfTotal(int connected, int total) {
    return '$connected von $total verbunden';
  }

  @override
  String get relaysSummaryHealthy =>
      'Du empfängst Orders und Nachrichten wie gewohnt';

  @override
  String get relaysSummaryAtRisk =>
      'Du siehst möglicherweise keine neuen Orders mehr';

  @override
  String get relayStatusConnected => 'Verbunden';

  @override
  String get relayStatusOffline => 'Keine Verbindung';

  @override
  String get addRelayButtonLabel => 'Relay hinzufügen';

  @override
  String get relaysFootnote =>
      'Relays übertragen deine Orders und Nachrichten. Mit weniger als zwei verbundenen siehst du möglicherweise keine neuen Orders mehr.';

  @override
  String get lastRelayBlockedMessage =>
      'Lass mindestens ein Relay aktiv: Ohne Relays kannst du keine Orders sehen oder veröffentlichen.';

  @override
  String get nwcExplainerTitle => 'Wallet verbinden';

  @override
  String get nwcExplainerSubtitle => 'Mit Nostr Wallet Connect';

  @override
  String get nwcExplainerBody =>
      'Mostro zieht und zahlt die Rechnungen deiner Trades aus dieser Wallet, sodass du keine Rechnung mehr von Hand kopieren musst.';

  @override
  String get nwcUriFieldLabel => 'Verbindungs-URI';

  @override
  String get nwcUriPlaceholder => 'nostr+walletconnect://…';

  @override
  String get nwcStorageFootnote =>
      'Die URI wird nur auf diesem Gerät gespeichert und nie auf Nostr veröffentlicht.';

  @override
  String get walletConnectedMessage => 'Wallet verbunden';

  @override
  String get nwcConnectedStatus => 'Verbunden';

  @override
  String nwcBalanceSats(String sats) {
    return '$sats Sats';
  }

  @override
  String get notificationsSystemDenied =>
      'Benachrichtigungen sind in den Systemeinstellungen deaktiviert.';

  @override
  String get openSystemSettingsAction => 'Einstellungen öffnen';

  @override
  String get notificationsPrivacyFootnote =>
      'Benachrichtigungen enthalten keine Beträge und keine Gegenparteien. Ein Push läuft über die Server von Google oder Apple und sagt nur, dass es etwas zu sehen gibt.';

  @override
  String get pushMasterToggleTitle => 'Push-Benachrichtigungen';

  @override
  String get pushMasterToggleSubtitle =>
      'Weckt die App, wenn ein Trade-Update oder eine Nachricht eintrifft. Die Benachrichtigung selbst enthält nichts.';

  @override
  String get pushStatusOff => 'Aus – nichts ist beim Push-Server registriert';

  @override
  String pushStatusCleanupPending(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Aus — $count Push-Registrierungen müssen noch entfernt werden',
      one: 'Aus — 1 Push-Registrierung muss noch entfernt werden',
    );
    return '$_temp0';
  }

  @override
  String get pushStatusNoToken => 'Warten auf das Push-Token dieses Geräts';

  @override
  String get pushStatusIdle => 'An – keine offenen Trades zu registrieren';

  @override
  String pushStatusRegistered(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Für $count Trades registriert',
      one: 'Für 1 Trade registriert',
    );
    return '$_temp0';
  }

  @override
  String pushStatusLastRegistered(String ago) {
    return 'Letzte Registrierung: $ago';
  }

  @override
  String get pushStatusUnreachable =>
      'Push-Server nicht erreichbar – neuer Versuch läuft';

  @override
  String get pushStatusNodeRefused =>
      'Dieser Mostro-Node wird vom Push-Server nicht akzeptiert';

  @override
  String get pushStatusRateLimited =>
      'Push-Anfragelimit erreicht – gleich neuer Versuch';

  @override
  String get pushUnsupportedPlatform =>
      'Push-Benachrichtigungen sind auf dieser Plattform nicht verfügbar';

  @override
  String get pushToggleSaveFailed =>
      'Push-Benachrichtigungen konnten nicht geändert werden';

  @override
  String get pushNewMessageBody => 'Du hast eine neue Nachricht';

  @override
  String get notificationPrefSaveFailed =>
      'Einstellung konnte nicht gespeichert werden';

  @override
  String get logsScreenTitle => 'Protokolle';

  @override
  String get logFilterAll => 'Alle';

  @override
  String get logFilterRelays => 'Relays';

  @override
  String get logFilterOrders => 'Orders';

  @override
  String get logFilterPayments => 'Zahlungen';

  @override
  String get verboseLoggingTitle => 'Ausführliches Protokoll';

  @override
  String get verboseLoggingSubtitle => 'Mehr Detail, mehr Verbrauch';

  @override
  String get newLogsChipLabel => 'Neue Einträge';

  @override
  String get noLogsForFilter => 'Keine Einträge für diesen Filter';

  @override
  String get aboutAppSection => 'Anwendung';

  @override
  String get aboutSourceCodeLabel => 'Quellcode';

  @override
  String get aboutUserGuideLabel => 'Benutzerhandbuch';

  @override
  String get aboutTechnicalDocsLabel => 'Technische Dokumentation';

  @override
  String get aboutLanguageSpanish => 'Spanisch';

  @override
  String get aboutLanguageEnglish => 'Englisch';

  @override
  String get aboutConnectedNodeTitle => 'Verbundener Knoten';

  @override
  String get aboutMinOrderCell => 'Min. Auftrag';

  @override
  String get aboutMaxOrderCell => 'Max. Auftrag';

  @override
  String get aboutFeeCell => 'Gebühr';

  @override
  String aboutFeeValue(String value) {
    return '$value %';
  }

  @override
  String get aboutLimitsFootnote => 'Limits in Satoshis pro Auftrag';

  @override
  String get aboutNodeTechnicalDataRow => 'Technische Knotendaten';

  @override
  String aboutFieldCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Felder',
      one: '$count Feld',
    );
    return '$_temp0';
  }

  @override
  String get aboutTechnicalDataTitle => 'Technische Daten';

  @override
  String get aboutPublicKeyLabel => 'Öffentlicher Schlüssel';

  @override
  String get aboutOrderExpiryLabel => 'Auftragsablauf';

  @override
  String get aboutWaitingTimeoutLabel => 'Warte-Timeout';

  @override
  String aboutHoursShort(int count) {
    return '$count h';
  }

  @override
  String aboutSecondsShort(int count) {
    return '$count s';
  }

  @override
  String get aboutAliasLabel => 'Alias';

  @override
  String get aboutNodePublicKeyLabel => 'Öffentlicher Knotenschlüssel';

  @override
  String get aboutNodeUriLabel => 'Knoten-URI';

  @override
  String get aboutCommitLabel => 'Commit';

  @override
  String get aboutChainNetworkLabel => 'Chain und Netzwerk';

  @override
  String get aboutTechnicalFootnote =>
      'Diese Daten identifizieren den Knoten, mit dem du handelst. Nützlich für den Support oder um ihn zu prüfen, bevor du Geld sendest.';

  @override
  String get aboutCopyAllData => 'Alle Daten kopieren';

  @override
  String get tradesGroupNeedsAction => 'Brauchen dich';

  @override
  String get tradesGroupInProgress => 'Laufend';

  @override
  String get tradesGroupClosed => 'Abgeschlossen';

  @override
  String get tradesDirectionSell => 'Du verkaufst';

  @override
  String get tradesDirectionBondClaim => 'Einlage-Anspruch';

  @override
  String get tradesDirectionBuy => 'Du kaufst';

  @override
  String tradesCounterpartyTo(String handle) {
    return 'an $handle';
  }

  @override
  String tradesCounterpartyFrom(String handle) {
    return 'von $handle';
  }

  @override
  String get tradeListChipYourTurn => 'Du bist dran';

  @override
  String get tradeListChipPublished => 'Veröffentlicht';

  @override
  String get tradeListChipInProgress => 'Laufend';

  @override
  String get tradeListChipWaitingInvoice => 'Warte auf Rechnung';

  @override
  String get tradeListChipWaitingPayment => 'Warte auf Zahlung';

  @override
  String get tradeListChipWaitingSats => 'Warte auf Sats';

  @override
  String get tradeListChipDispute => 'Im Streitfall';

  @override
  String get tradeListChipCompleted => 'Abgeschlossen';

  @override
  String get tradeListChipCancelled => 'Storniert';

  @override
  String get tradeListChipExpired => 'Abgelaufen';

  @override
  String get tradeVerbAddInvoice => 'Rechnung hinzufügen';

  @override
  String get tradeVerbPayBond => 'Einlage zahlen';

  @override
  String get tradeHeadlineWaitingBond =>
      'Sperre deine Einlage, um fortzufahren';

  @override
  String get tradeInstructionWaitingBond =>
      'Der Node hält diese Annahme zurück, bis die rückzahlbare Einlage bezahlt ist. Die Order bleibt derweil für andere offen.';

  @override
  String get takeOrderBondNotice =>
      'Dieser Node verlangt von Annehmenden zuerst eine rückzahlbare Einlage; sie kommt zurück, wenn der Handel ehrlich endet.';

  @override
  String takeOrderBondNoticeEstimate(String sats) {
    return 'Dieser Node verlangt von Annehmenden zuerst eine rückzahlbare Einlage von ≈ $sats Sats; sie kommt zurück, wenn der Handel ehrlich endet.';
  }

  @override
  String get tradeVerbPayInvoice => 'Rechnung bezahlen';

  @override
  String get tradeVerbSendPayment => 'Zahlung senden';

  @override
  String get tradeVerbReleaseSats => 'Sats freigeben';

  @override
  String get tradeVerbRate => 'Bewerten';

  @override
  String get tradeListFilterAll => 'Alle';

  @override
  String get tradeListFilterActive => 'Aktiv';

  @override
  String get tradeListFilterCompleted => 'Abgeschlossen';

  @override
  String get tradeListFilterCancelled => 'Storniert';

  @override
  String get tradeListFilterTitle => 'Trades anzeigen';

  @override
  String get relativeTimeNow => 'jetzt';

  @override
  String relativeTimeMinutes(int count) {
    return 'vor $count Min.';
  }

  @override
  String relativeTimeHours(int count) {
    return 'vor $count Std.';
  }

  @override
  String get relativeTimeYesterday => 'gestern';

  @override
  String satsFigureEstimate(String sats) {
    return '≈ $sats Sats';
  }

  @override
  String satsFigureExact(String sats) {
    return '$sats Sats';
  }

  @override
  String get chatGroupActive => 'Aktive Trades';

  @override
  String chatContextSellActive(String amount, String currency) {
    return 'Du verkaufst $amount $currency';
  }

  @override
  String chatContextBuyActive(String amount, String currency) {
    return 'Du kaufst $amount $currency';
  }

  @override
  String chatContextSellClosed(String amount, String currency) {
    return 'Du hast $amount $currency verkauft';
  }

  @override
  String chatContextBuyClosed(String amount, String currency) {
    return 'Du hast $amount $currency gekauft';
  }

  @override
  String get chatTurnAddInvoice => 'du fügst die Rechnung hinzu';

  @override
  String get chatTurnPayBond => 'du zahlst die Einlage';

  @override
  String get chatTurnPayInvoice => 'du zahlst die Rechnung';

  @override
  String get chatTurnSendPayment => 'du zahlst';

  @override
  String get chatTurnRelease => 'du gibst frei';

  @override
  String get chatTurnRate => 'du bewertest';

  @override
  String get chatYouLabel => 'Du:';

  @override
  String get chatListFootnote =>
      'Jede Unterhaltung gehört zu einem Trade und ist Ende-zu-Ende-verschlüsselt. Nach dem Trade bleibt sie hier lesbar.';

  @override
  String get chatListEmptyTitle => 'Noch keine Unterhaltungen';

  @override
  String get chatListEmptyBody =>
      'Der Chat öffnet sich, sobald ein Trade aktiv wird.';

  @override
  String get chatClosedNotice =>
      'Der Trade ist beendet. Die Unterhaltung bleibt hier lesbar.';

  @override
  String disputeOpenedByYou(String time) {
    return 'Von dir eröffnet, $time';
  }

  @override
  String disputeOpenedByPeer(String time) {
    return 'Von der Gegenseite eröffnet, $time';
  }

  @override
  String get invoiceReceiveTitle => 'Deine Sats erhalten';

  @override
  String get invoiceLockTitle => 'Deine Sats sperren';

  @override
  String get bondTitle => 'Sicherheitseinlage';

  @override
  String get bondRefundableLabel => 'RÜCKZAHLBARE EINLAGE';

  @override
  String get bondComesBack => 'kommt beim Abschluss zu dir zurück';

  @override
  String bondFiatComesBack(String fiat) {
    return '≈ $fiat · kommt beim Abschluss zu dir zurück';
  }

  @override
  String bondPaySemantics(String sats) {
    return 'Rückzahlbare Einlage von $sats Sats';
  }

  @override
  String bondReleasesIn(String time) {
    return 'Die Order wird freigegeben, wenn du nicht in $time zahlst';
  }

  @override
  String bondRowHeld(String bold) {
    return 'Die Sats bleiben $bold, sie werden nicht ausgegeben';
  }

  @override
  String get bondRowHeldBold => 'in deiner Wallet gehalten';

  @override
  String bondRowReleased(String bold) {
    return 'Endet der Handel gut, $bold';
  }

  @override
  String get bondRowReleasedBold => 'wird sie von selbst freigegeben';

  @override
  String bondRowLost(String bold) {
    return 'Du verlierst sie nur bei einem Streitfall, und $bold';
  }

  @override
  String bondRowLostTimeout(String bold) {
    return 'Du verlierst sie, wenn du einen Schritt verstreichen lässt oder bei einem Streitfall, und $bold';
  }

  @override
  String get bondRowLostBold => 'du ihn verlierst';

  @override
  String get bondWhyTitle => 'Warum Mostro eine Einlage verlangt';

  @override
  String get bondWhyCustody =>
      'Mostro verwahrt keine Gelder und kann daher niemanden bestrafen, der einen Handel abbricht; das übernimmt die Einlage, und sie schützt alle Nutzer vor Betrügern.';

  @override
  String bondWhyHold(String hold) {
    return 'Es ist eine $hold-Rechnung: deine Wallet reserviert die Sats, ohne sie zu senden; beim Abschluss wird die Reservierung von selbst aufgehoben.';
  }

  @override
  String get bondWhyDispute =>
      'Wenn du einen Streitfall eröffnest und gewinnst, bekommst du sie ebenfalls zurück. Sie wird nur eingezogen, wenn du einen Streitfall verlierst.';

  @override
  String get bondWhyDisputeTimeout =>
      'Wenn du einen Streitfall eröffnest und gewinnst, bekommst du sie ebenfalls zurück. Sie wird nur eingezogen, wenn du einen Streitfall verlierst oder einen Schritt verstreichen lässt.';

  @override
  String get bondReadDocs => 'Dokumentation lesen';

  @override
  String get bondContextOrder => 'Order';

  @override
  String bondContextBuy(String fiat) {
    return 'Du kaufst $fiat';
  }

  @override
  String bondContextSell(String fiat) {
    return 'Du verkaufst $fiat';
  }

  @override
  String get bondContextEquals => 'Einlage entspricht';

  @override
  String bondContextPercent(String pct) {
    return '$pct % des Betrags';
  }

  @override
  String get bondDontPublish => 'Order nicht veröffentlichen';

  @override
  String get bondAbandoned =>
      'Order verworfen. Nichts wurde veröffentlicht und nichts berechnet.';

  @override
  String bondPublishesIn(String time) {
    return 'Noch nicht veröffentlicht: die Order verfällt, wenn du nicht innerhalb von $time zahlst';
  }

  @override
  String get bondInvoiceMissingMaker =>
      'Dieses Gerät hat keine Kopie der Einlage-Rechnung, und der Node sendet sie für eine von dir erstellte Order nicht erneut. Verwirf die Order und erstelle sie neu.';

  @override
  String get bondExpiredBodyMaker =>
      'Sie wurde nicht rechtzeitig bezahlt: die Order wurde nie veröffentlicht und keine Sats haben deine Wallet verlassen.';

  @override
  String get bondExpiredNoticeMaker =>
      'Die Einlage-Rechnung ist abgelaufen; die Order wurde nicht veröffentlicht';

  @override
  String get orderStatusWaitingBond =>
      'Warte auf deine Einlage — noch nicht veröffentlicht';

  @override
  String get bondCancelNotAllowed =>
      'Diese Order kann nicht storniert werden, solange ihre Einlage aussteht. Verwirf sie stattdessen auf dem Einlage-Bildschirm.';

  @override
  String createOrderBondNoticeEstimate(String sats) {
    return 'Dieser Node verlangt eine rückzahlbare Einlage von ≈ $sats Sats, bevor die Order veröffentlicht wird; sie kommt zurück, wenn der Handel ehrlich endet.';
  }

  @override
  String get createOrderBondNotice =>
      'Dieser Node verlangt eine rückzahlbare Einlage, bevor die Order veröffentlicht wird; sie kommt zurück, wenn der Handel ehrlich endet.';

  @override
  String get bondClaimTitle => 'Deinen Anteil einfordern';

  @override
  String get bondClaimShareLabel => 'DEIN ANTEIL';

  @override
  String bondClaimShareSemantics(String sats) {
    return 'Anteil von $sats Sats einzufordern';
  }

  @override
  String bondClaimContext(String context) {
    return 'Aus dem Handel über $context';
  }

  @override
  String bondClaimDeadline(String date) {
    return 'Fordere es vor dem $date ein';
  }

  @override
  String get bondClaimExplainer =>
      'Die Einlage der Gegenseite ist zu deinen Gunsten verfallen. Füge eine Rechnung über genau diesen Betrag hinzu und der Node zahlt ihn dir aus.';

  @override
  String get bondClaimFieldLabel => 'Lightning-Rechnung';

  @override
  String get bondClaimFieldHint => 'lnbc… über genau den Anteil';

  @override
  String get bondClaimSubmit => 'Rechnung senden';

  @override
  String get bondClaimSent => 'Rechnung an den Node gesendet';

  @override
  String get bondClaimSubmittedTitle => 'Rechnung gesendet';

  @override
  String get bondClaimSubmittedBody => 'Warte auf die Bestätigung des Nodes.';

  @override
  String get bondClaimAcknowledgedTitle => 'Auszahlung läuft';

  @override
  String get bondClaimAcknowledgedBody =>
      'Der Node hat deine Rechnung angenommen und zahlt sie. Kann sie nicht geroutet werden, wirst du um eine neue gebeten.';

  @override
  String get bondClaimCompletedTitle => 'Bezahlt';

  @override
  String bondClaimCompletedBody(String sats) {
    return '$sats Sats sind in deiner Wallet angekommen.';
  }

  @override
  String get bondClaimExpiredTitle => 'Das Zeitfenster ist abgelaufen';

  @override
  String bondClaimExpiredBody(String date) {
    return 'Es endete am $date. Der Anteil kann nicht mehr eingefordert werden.';
  }

  @override
  String get bondClaimMissing => 'Kein Anspruch für diese Order gefunden.';

  @override
  String get bondClaimErrorAmount =>
      'Die Rechnung muss über genau den angezeigten Anteil lauten.';

  @override
  String get bondClaimErrorExpired =>
      'Das Zeitfenster ist abgelaufen; der Anteil kann nicht mehr eingefordert werden.';

  @override
  String get bondClaimErrorRejected =>
      'Der Node hat die Rechnung nicht angenommen. Versuche eine andere.';

  @override
  String get bondClaimErrorNotClaimable =>
      'Dieser Anspruch nimmt gerade keine Rechnung an.';

  @override
  String get bondClaimErrorNoKey =>
      'Dieses Gerät hat keinen Schlüssel für diesen Handel und kann den Anteil nicht einfordern.';

  @override
  String get tradeVerbClaimPayout => 'Auszahlung einfordern';

  @override
  String get chatTurnClaimPayout => 'du forderst die Auszahlung ein';

  @override
  String get tradeBadgePayoutPending => 'Auszahlung ausstehend';

  @override
  String get tradeBadgePayoutInProgress => 'Auszahlung läuft';

  @override
  String get tradeBadgePayoutPaid => 'Auszahlung erhalten';

  @override
  String bondBannerPendingTitle(String sats) {
    return '$sats Sats warten darauf, zu dir zurückzukommen';
  }

  @override
  String bondBannerPendingBody(String sats) {
    return 'Die Einlage der Gegenseite ist zu deinen Gunsten verfallen. Füge eine Lightning-Rechnung über $sats Sats hinzu, um sie einzufordern.';
  }

  @override
  String get bondBannerAddInvoice => 'Auszahlungsrechnung hinzufügen';

  @override
  String get bondBannerView => 'Anspruch ansehen';

  @override
  String get bondBannerInProgressTitle => 'Auszahlung läuft';

  @override
  String bondBannerInProgressBody(String sats) {
    return 'Der Node zahlt deinen Anteil von $sats Sats aus.';
  }

  @override
  String get bondBannerPaidTitle => 'Auszahlung erhalten';

  @override
  String bondBannerPaidBody(String sats, String date) {
    return '$sats Sats wurden dir am $date ausgezahlt.';
  }

  @override
  String bondBannerExpired(String date) {
    return 'Der Anspruch auf die Einlage der Gegenseite endete am $date.';
  }

  @override
  String get bondClaimNewTitle => 'Einlage-Auszahlung einzufordern';

  @override
  String bondClaimNewMessage(String sats) {
    return 'Du kannst $sats Sats aus einer verfallenen Einlage einfordern. Füge eine Lightning-Rechnung hinzu, um sie zu erhalten.';
  }

  @override
  String get bondClaimPaidTitle => 'Einlage-Auszahlung erhalten';

  @override
  String bondClaimPaidMessage(String sats) {
    return 'Einlage-Auszahlung von $sats Sats erhalten.';
  }

  @override
  String get bondDontTake => 'Order nicht annehmen';

  @override
  String get bondLockedNowEscrow =>
      'Einlage gesperrt. Sperre jetzt den Handelsbetrag.';

  @override
  String get bondLostRace =>
      'Ein anderer Nutzer hat diese Order angenommen, bevor deine Einlage bezahlt war';

  @override
  String get bondMakerCanceled => 'Der Ersteller hat diese Order storniert';

  @override
  String get bondExpiredNotice =>
      'Die Einlage-Rechnung ist abgelaufen; die Order ist zurück im Orderbuch';

  @override
  String get bondExpiredTitle => 'Die Einlage-Rechnung ist abgelaufen';

  @override
  String get bondExpiredBody =>
      'Sie wurde nicht rechtzeitig bezahlt: Die Order ist zurück im Orderbuch, und keine Sats haben deine Wallet verlassen.';

  @override
  String get bondInvoiceMissing =>
      'Dieses Gerät hat keine Kopie der Einlage-Rechnung. Fordere sie erneut vom Node an, um die Order weiter anzunehmen.';

  @override
  String get bondRequestAgain => 'Rechnung erneut anfordern';

  @override
  String get bondRequestFailed =>
      'Der Node hat die Einlage-Rechnung nicht erneut gesendet';

  @override
  String get invoiceOrderIdCopied => 'Order-ID kopiert';

  @override
  String get invoiceYouReceiveLabel => 'Du erhältst';

  @override
  String get invoiceToPayLabel => 'Zu zahlen';

  @override
  String invoiceReceiveSemantics(String sats) {
    return '$sats Satoshis zu erhalten';
  }

  @override
  String invoicePaySemantics(String sats) {
    return '$sats Satoshis zu zahlen';
  }

  @override
  String invoiceFeeIncluded(String sats) {
    return 'Inklusive $sats Sats Mostro-Gebühr';
  }

  @override
  String invoiceTimeToSend(String time) {
    return 'Du hast $time, um sie zu senden';
  }

  @override
  String invoiceExpiresIn(String time) {
    return 'Die Rechnung läuft in $time ab';
  }

  @override
  String get invoiceFieldLabel => 'Lightning-Rechnung oder -Adresse';

  @override
  String get invoiceFieldHint => 'lnbc… oder nutzer@domain';

  @override
  String get invoiceFieldPromptLabel => 'Rechnung hier einfügen';

  @override
  String get invoiceFieldFilledLabel => 'Lightning-Rechnung';

  @override
  String get invoiceFieldAddressLabel => 'Lightning-Adresse';

  @override
  String get invoiceScanButton => 'Scannen';

  @override
  String get invoiceReplaceButton => 'Ersetzen';

  @override
  String get invoiceFieldSemantics =>
      'Lightning-Rechnung oder -Adresse, erforderlich';

  @override
  String invoiceFilledSemantics(String sats) {
    return 'Lightning-Rechnung über $sats Sats';
  }

  @override
  String get invoiceValidAddress =>
      'Gültige Adresse · die Rechnung wird beim Senden angefordert';

  @override
  String invoiceValidInvoice(String sats) {
    return 'Gültige Rechnung · $sats Sats';
  }

  @override
  String invoiceErrorWrongAmount(String actual, String expected) {
    return 'Die Rechnung lautet auf $actual Sats, es müssen $expected sein';
  }

  @override
  String get invoiceErrorExpired => 'Die Rechnung ist bereits abgelaufen';

  @override
  String invoiceErrorExpiresTooSoon(String minutes) {
    return 'Die Rechnung läuft in weniger als $minutes Minuten ab, der Node braucht mehr Zeit zum Bezahlen';
  }

  @override
  String get invoiceErrorMalformed =>
      'Diese Rechnung ist unvollständig oder falsch kopiert';

  @override
  String get invoiceErrorUnrecognized =>
      'Weder eine Rechnung (lnbc…) noch eine Lightning-Adresse (nutzer@domain)';

  @override
  String get invoiceSellerLabel => 'Verkäufer';

  @override
  String get invoiceBuyerLabel => 'Käufer';

  @override
  String get invoiceYouPayLabel => 'Du zahlst';

  @override
  String get invoiceYouGetLabel => 'Du erhältst';

  @override
  String get invoiceNoTrades => 'keine Trades';

  @override
  String get invoiceSendButton => 'Rechnung senden';

  @override
  String get invoiceCancelTrade => 'Handel abbrechen';

  @override
  String get invoiceOpenWallet => 'In meiner Wallet öffnen';

  @override
  String invoiceHoldNote(String hold) {
    return 'Das ist eine $hold-Rechnung: Die Sats werden zurückgehalten und verlassen deine Wallet erst, wenn du die Zahlung des Käufers bestätigst.';
  }

  @override
  String invoiceQrSemantics(String invoice) {
    return 'QR-Code der Lightning-Rechnung: $invoice';
  }

  @override
  String get invoiceExpiredTitle => 'Die Rechnung ist abgelaufen';

  @override
  String get invoiceExpiredBody =>
      'Sie wurde nicht rechtzeitig bezahlt: Mostro bricht den Handel ab, und keine Sats haben deine Wallet verlassen.';

  @override
  String get invoiceBackToBook => 'Zurück zum Orderbuch';

  @override
  String get invoiceTimeUpTitle => 'Die Zeit ist abgelaufen';

  @override
  String get invoiceTimeUpBody =>
      'Die Rechnung wurde nicht rechtzeitig gesendet: Mostro bricht den Handel ab. Auf deiner Seite wurde nichts gebunden.';

  @override
  String invoiceErrorWrongNetwork(String invoice, String node) {
    return 'Die Rechnung ist für $invoice, der Node nutzt $node';
  }

  @override
  String invoiceCountdownHours(String hours, String minutes) {
    return '$hours Std. $minutes';
  }

  @override
  String get tradeCardWaitingBuyerInvoiceTitle =>
      'Warte auf die Rechnung des Käufers';

  @override
  String get tradeCardWaitingBuyerInvoiceMessage =>
      'Der Handel geht weiter, sobald der Käufer eine Lightning-Rechnung hinzufügt.';

  @override
  String get tradeCardWaitingPaymentTitle =>
      'Warte auf die Zahlung des Verkäufers';

  @override
  String get tradeCardWaitingPaymentMessage =>
      'Der Handel geht weiter, sobald der Verkäufer die Hold-Rechnung bezahlt.';

  @override
  String get tradeCardWaitingTakerBondTitle => 'Kautionszahlung ausstehend';

  @override
  String get tradeCardWaitingTakerBondMessage =>
      'Die Anti-Missbrauchs-Kaution des Nehmers muss vor Handelsbeginn bezahlt werden.';

  @override
  String get tradeCardActiveTitle => 'Handel aktiv';

  @override
  String get tradeCardActiveMessage =>
      'Die Sats sind gesperrt. Der Käufer kann jetzt die Fiat-Zahlung senden.';

  @override
  String get tradeCardFiatSentTitle => 'Fiat als gesendet markiert';

  @override
  String get tradeCardFiatSentMessage =>
      'Der Käufer hat die Fiat-Zahlung als gesendet markiert.';

  @override
  String get tradeCardSettledHoldInvoiceTitle => 'Sats freigegeben';

  @override
  String get tradeCardSettledHoldInvoiceMessage =>
      'Der Verkäufer hat die Sats freigegeben. Die Auszahlung an den Käufer ist unterwegs.';

  @override
  String get tradeCardSuccessTitle => 'Handel abgeschlossen';

  @override
  String get tradeCardSuccessMessage =>
      'Der Handel wurde erfolgreich abgeschlossen.';

  @override
  String get tradeCardCanceledTitle => 'Handel storniert';

  @override
  String get tradeCardCanceledMessage => 'Der Handel wurde storniert.';

  @override
  String get tradeCardExpiredTitle => 'Order abgelaufen';

  @override
  String get tradeCardExpiredMessage =>
      'Die Order ist abgelaufen, bevor der Handel weitergehen konnte.';

  @override
  String get tradeCardCooperativelyCanceledTitle =>
      'Handel einvernehmlich storniert';

  @override
  String get tradeCardCooperativelyCanceledMessage =>
      'Beide Parteien haben der Stornierung des Handels zugestimmt.';

  @override
  String get tradeCardDisputeTitle => 'Streitfall eröffnet';

  @override
  String get tradeCardDisputeMessage =>
      'Zu diesem Handel wurde ein Streitfall eröffnet.';

  @override
  String get tradeCardCanceledByAdminTitle => 'Vom Schlichter storniert';

  @override
  String get tradeCardCanceledByAdminMessage =>
      'Der Streitschlichter hat den Handel storniert.';

  @override
  String get tradeCardSettledByAdminTitle => 'Vom Schlichter beigelegt';

  @override
  String get tradeCardSettledByAdminMessage =>
      'Der Streitschlichter hat die Sats an den Käufer freigegeben.';

  @override
  String get tradeCardCompletedByAdminTitle => 'Vom Schlichter abgeschlossen';

  @override
  String get tradeCardCompletedByAdminMessage =>
      'Der Streitschlichter hat den Handel abgeschlossen.';

  @override
  String get tradeCardUpdatedTitle => 'Handel aktualisiert';

  @override
  String get tradeCardUpdatedMessage =>
      'Der Status dieses Handels hat sich geändert.';

  @override
  String get tradeCardCanceledByMakerMessage =>
      'Der Ersteller hat die Order storniert.';

  @override
  String get tradeCardCanceledBondLostRaceMessage =>
      'Ein anderer Nutzer hat diese Order genommen, bevor die Kaution bezahlt wurde.';

  @override
  String get tradeCardCanceledBondExpiredMessage =>
      'Die Kautionsrechnung ist unbezahlt abgelaufen.';

  @override
  String get chatCardTitle => 'Neue Nachrichten';

  @override
  String get chatCardSolverTitle => 'Nachrichten vom Schlichter';

  @override
  String chatCardMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count neue Nachrichten von deinem Handelspartner',
      one: '1 neue Nachricht von deinem Handelspartner',
    );
    return '$_temp0';
  }

  @override
  String chatCardSolverMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count neue Nachrichten vom Streitschlichter',
      one: '1 neue Nachricht vom Streitschlichter',
    );
    return '$_temp0';
  }

  @override
  String get invalidTradeIndexError =>
      'Dein Konto ist nicht mit diesem Mostro-Knoten synchronisiert, daher wurde die Order abgelehnt. Versuche es gleich noch einmal';

  @override
  String get recoveringTradesMessage =>
      'Konto importiert. Deine Trades werden von Mostro wiederhergestellt…';

  @override
  String recoveredTradesMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Konto importiert. $count Trades wiederhergestellt',
      one: 'Konto importiert. 1 Trade wiederhergestellt',
      zero: 'Konto importiert. Du hattest keine laufenden Trades',
    );
    return '$_temp0';
  }

  @override
  String get recoverTradesFailedMessage =>
      'Konto importiert, aber Mostro hat nicht geantwortet, daher wurden deine laufenden Trades nicht wiederhergestellt';

  @override
  String get paymentMethodsChosenLabel => 'Ausgewählt';

  @override
  String paymentMethodsSelectedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Methoden ausgewählt',
      one: '1 Methode ausgewählt',
      zero: 'Wähle mindestens eine Methode',
    );
    return '$_temp0';
  }

  @override
  String get paymentMethodsConfirm => 'Methoden bestätigen';

  @override
  String get paymentMethodAddCustom => 'Eigene Zahlungsmethode hinzufügen';

  @override
  String get paymentMethodsDiscardTitle => 'Änderungen verwerfen?';

  @override
  String get paymentMethodsDiscardConfirm => 'Verwerfen';

  @override
  String get paymentMethodsKeepEditing => 'Weiter bearbeiten';

  @override
  String get fundsAtRiskTitle => 'Dieser Benutzer hat noch Sats im Spiel';

  @override
  String get fundsAtRiskBody =>
      'Wenn du fortfährst, werden die Schlüssel dieses Benutzers ersetzt, und nichts von dem hier Aufgeführten kann von diesem Gerät aus abgeschlossen oder wiederhergestellt werden. Das wird nicht empfohlen: Du kannst diese Sats verlieren.';

  @override
  String get fundsAtRiskSellerEscrow =>
      'Sats für einen Verkauf treuhänderisch gesperrt';

  @override
  String get fundsAtRiskBondLocked => 'Kaution gesperrt';

  @override
  String get fundsAtRiskPayoutClaim => 'Kautionsauszahlung noch nicht abgeholt';

  @override
  String get fundsAtRiskTradeInProgress => 'Handel läuft';

  @override
  String get fundsAtRiskBondInvoicePending => 'Kautionsrechnung noch zahlbar';

  @override
  String get fundsAtRiskKeep => 'Diesen Benutzer behalten';

  @override
  String get fundsAtRiskContinue => 'Trotzdem fortfahren';

  @override
  String get restoreSheetTitle => 'Dein Konto wird wiederhergestellt';

  @override
  String get restoreSheetWaiting => 'Das kann ein paar Sekunden dauern';

  @override
  String restoreSheetLoading(int done, int total) {
    return '$done von $total Orders wiederhergestellt';
  }

  @override
  String get restoreStageConnecting => 'Verbindung zum Mostro-Node';

  @override
  String get restoreStageConnected => 'Mit dem Mostro-Node verbunden';

  @override
  String get restoreStageRequesting => 'Deine Orders werden angefragt';

  @override
  String restoreStageFound(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Orders gefunden',
      one: '1 Order gefunden',
    );
    return '$_temp0';
  }

  @override
  String get restoreStageLoading => 'Details werden geladen';

  @override
  String get restoreStageNoResponse => 'Keine Antwort';

  @override
  String restoreLoadingCountSemantics(int done, int total) {
    return '$done von $total Orders';
  }

  @override
  String get restoreFailedTitle =>
      'Deine Orders konnten nicht wiederhergestellt werden';

  @override
  String get restoreFailedSubtitle => 'Dein Konto wurde trotzdem importiert';

  @override
  String restoreFailedBody(String place) {
    return 'Prüfe deine Verbindung und versuche es erneut. Du kannst es jederzeit unter $place wiederholen.';
  }

  @override
  String get restoreContinueWithout => 'Ohne Wiederherstellung fortfahren';

  @override
  String get restoreDoneTitle => 'Konto wiederhergestellt';

  @override
  String get restoreDoneSubtitle =>
      'Alles, was der Node hatte, ist wiederhergestellt';

  @override
  String get restoreDoneEmptySubtitle =>
      'Dieses Konto hatte keine Orders auf dem Node';

  @override
  String get restoreSummaryOrders => 'Orders';

  @override
  String get restoreSummaryInProgress => 'Laufend';

  @override
  String restoreActionNotice(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count aktive Orders warten auf dich',
      one: '1 aktive Order wartet auf dich',
    );
    return '$_temp0';
  }

  @override
  String restorePartialNotice(int missing, int total) {
    return '$missing von $total Orders konnten nicht geladen werden';
  }

  @override
  String get attachSheetTitle => 'Datei senden';

  @override
  String get attachSheetBody =>
      'Die Datei wird auf deinem Gerät verschlüsselt. Nur dein Handelspartner kann sie öffnen.';

  @override
  String get attachSheetBodySolver =>
      'Die Datei wird auf deinem Gerät verschlüsselt. Nur der Schlichter kann sie öffnen.';

  @override
  String get attachSourcePhoto => 'Foto';

  @override
  String get attachSourceCamera => 'Kamera';

  @override
  String get attachSourcePdf => 'PDF-Dokument';

  @override
  String get attachConfirmTitle => 'Diese Datei senden?';

  @override
  String attachConfirmBody(String fileName, String size) {
    return '$fileName ($size)';
  }

  @override
  String get attachmentTooLarge => 'Dateien dürfen höchstens 25 MB groß sein.';

  @override
  String get attachmentUnsupported =>
      'Nur JPEG-, PNG- und PDF-Dateien können gesendet werden.';

  @override
  String get attachmentInvalidImage =>
      'Dieses Bild konnte nicht gelesen werden.';

  @override
  String get attachmentReadFailed => 'Die Datei konnte nicht gelesen werden.';

  @override
  String get attachmentPeerUnknown =>
      'Du kannst Dateien senden, sobald jemand die Order angenommen hat.';

  @override
  String get attachmentUploadFailed =>
      'Das Hochladen ist fehlgeschlagen. Prüfe deine Verbindung und versuche es erneut.';

  @override
  String get attachmentSendFailed => 'Die Datei konnte nicht gesendet werden.';

  @override
  String get attachmentDownloadFailed =>
      'Die Datei konnte nicht heruntergeladen werden.';

  @override
  String get attachmentDecryptFailed =>
      'Diese Datei konnte nicht entschlüsselt werden.';

  @override
  String get attachmentWebUnavailable =>
      'Dateien sind im Web noch nicht verfügbar.';

  @override
  String get attachmentUploading => 'Wird gesendet…';

  @override
  String get attachmentDiscard => 'Verwerfen';

  @override
  String get attachmentSave => 'Speichern';

  @override
  String get attachmentSaved => 'Datei gespeichert';

  @override
  String get attachmentSaveFailed =>
      'Die Datei konnte nicht gespeichert werden.';

  @override
  String attachmentImageSemantics(String fileName) {
    return 'Bild: $fileName';
  }

  @override
  String get attachmentOpenImage => 'Bild öffnen';

  @override
  String get attachmentOpenWith => 'Öffnen mit…';

  @override
  String get attachmentShare => 'Teilen';

  @override
  String get attachmentMoreActions => 'Weitere Optionen';

  @override
  String get attachmentNoAppToOpen =>
      'Keine App auf diesem Gerät kann diese Datei öffnen.';

  @override
  String get attachmentOpenFailed => 'Die Datei konnte nicht geöffnet werden.';

  @override
  String get attachmentShareFailed => 'Die Datei konnte nicht geteilt werden.';

  @override
  String get attachmentSaveOnly =>
      'Dieser Dateityp kann nur gespeichert werden.';
}

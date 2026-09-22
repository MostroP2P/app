// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Dutch Flemish (`nl`).
class AppLocalizationsNl extends AppLocalizations {
  AppLocalizationsNl([String locale = 'nl']) : super(locale);

  @override
  String get appName => 'Mostro';

  @override
  String get loading => 'Laden…';

  @override
  String get error => 'Fout';

  @override
  String get actionFailedAnnouncement => 'Actie mislukt';

  @override
  String get cancel => 'Annuleren';

  @override
  String get confirm => 'Bevestigen';

  @override
  String get done => 'Klaar';

  @override
  String get skip => 'Overslaan';

  @override
  String get chatTimestampYesterday => 'Gisteren';

  @override
  String get disputesEmptyState => 'Je disputen verschijnen hier';

  @override
  String get disputeAttachFile => 'Bestand toevoegen';

  @override
  String get disputeWriteMessageHint => 'Schrijf een bericht…';

  @override
  String get disputeSend => 'Versturen';

  @override
  String get orderDispute => 'Dispuut over de order';

  @override
  String get disputeAdminAssigned =>
      'Er is een beheerder aan je dispuut toegewezen. Hij neemt hier binnenkort contact met je op.';

  @override
  String get disputeChatClosed =>
      'Dit dispuut is opgelost. De chat is gesloten.';

  @override
  String get messageCopied => 'Gekopieerd';

  @override
  String get disputeLoadError =>
      'De disputen konden niet worden geladen. Probeer het opnieuw.';

  @override
  String get disputeMessagingComingSoon =>
      'Berichten bij disputen komen binnenkort';

  @override
  String get disputeAttachmentsComingSoon =>
      'Bestanden toevoegen komt binnenkort';

  @override
  String get disputeNotFound => 'Dispuut niet gevonden.';

  @override
  String get disputeNotFoundForOrder =>
      'Geen dispuut gevonden voor deze order.';

  @override
  String get disputeResolved => 'Opgelost';

  @override
  String get disputeSuccessfullyCompleted => 'Afgerond';

  @override
  String get disputeCoopCancelMessage =>
      'De order is in overleg geannuleerd. Er is geen geld overgemaakt.';

  @override
  String disputeWithBuyer(String handle) {
    return 'Dispuut met koper: $handle';
  }

  @override
  String disputeWithSeller(String handle) {
    return 'Dispuut met verkoper: $handle';
  }

  @override
  String orderLabel(String orderId) {
    return 'Order $orderId';
  }

  @override
  String get disputeInitiated => 'Geopend';

  @override
  String get disputeInProgress => 'In behandeling';

  @override
  String get disputeStatusClosed => 'Gesloten';

  @override
  String get disputeLostFundsToBuyer =>
      'De beheerder heeft het dispuut in het voordeel van de koper beslist. De sats zijn aan de koper vrijgegeven.';

  @override
  String get disputeLostFundsToSeller =>
      'De beheerder heeft de order geannuleerd en de sats aan de verkoper teruggegeven. Jij hebt de sats niet ontvangen.';

  @override
  String get walkthroughSlideOneTitle => 'Handel vrij in bitcoin, zonder KYC';

  @override
  String get walkthroughSlideOneBody =>
      'Mostro is een peer-to-peer exchange waar je bitcoin verhandelt tegen elke valuta en betaalmethode, zonder KYC en zonder je gegevens aan iemand te geven. Hij draait op Nostr, en is daarmee bestand tegen censuur. Niemand kan je tegenhouden om te handelen.';

  @override
  String get walkthroughSlideTwoTitle => 'Privacy vanaf het begin';

  @override
  String get walkthroughSlideTwoBody =>
      'Mostro maakt voor elke handel een nieuwe identiteit aan, zodat je trades niet aan elkaar te koppelen zijn. Je bepaalt zelf hoe privé je blijft:\n• Reputatiemodus: anderen zien je geslaagde trades en hoe betrouwbaar je bent.\n• Volledig privé: je bouwt geen reputatie op, maar wat je doet blijft volledig anoniem.\nJe kunt altijd wisselen in het scherm Account; sla daar ook je geheime woorden op, want dat is de enige manier om je account terug te krijgen.';

  @override
  String get walkthroughSlideThreeTitle => 'Zekerheid bij elke stap';

  @override
  String get walkthroughSlideThreeBody =>
      'Mostro werkt met hold invoices: de sats blijven in de wallet van de verkoper tot het einde van de trade. Dat beschermt beide kanten. De app is bovendien gemaakt om voor iedereen vanzelfsprekend te werken.';

  @override
  String get walkthroughSlideFourTitle => 'Volledig versleutelde chat';

  @override
  String get walkthroughSlideFourBody =>
      'Elke trade heeft een eigen privéchat, end-to-end versleuteld. Alleen de twee betrokken gebruikers kunnen hem lezen. Bij een dispuut kun je de gedeelde sleutel aan een beheerder geven om de zaak op te lossen.';

  @override
  String get walkthroughSlideFiveTitle => 'Een aanbod accepteren';

  @override
  String get walkthroughSlideFiveBody =>
      'Blader door het orderboek, kies een aanbod dat je bevalt en loop de trade stap voor stap door. Je kunt het profiel van de ander bekijken, veilig chatten en de trade zonder gedoe afronden.';

  @override
  String get walkthroughSlideSixTitle => 'Niet gevonden wat je zoekt?';

  @override
  String get walkthroughSlideSixBody =>
      'Je kunt ook je eigen aanbod plaatsen en wachten tot iemand het accepteert. Kies het bedrag en je betaalmethode; Mostro regelt de rest.';

  @override
  String get tabBuyBtc => 'BTC kopen';

  @override
  String get tabSellBtc => 'BTC verkopen';

  @override
  String get filterButtonLabel => 'Filter';

  @override
  String get noOrdersAvailable => 'Geen orders beschikbaar';

  @override
  String get justNow => 'Zojuist';

  @override
  String minutesAgo(int m) {
    return '$m min geleden';
  }

  @override
  String hoursAgo(int h) {
    return '$h uur geleden';
  }

  @override
  String daysAgo(int d) {
    return '$d d geleden';
  }

  @override
  String get invoiceRejected =>
      'De node heeft deze invoice geweigerd. Controleer het bedrag en de vervaldatum en voeg een nieuwe toe.';

  @override
  String get invoiceCopied => 'Invoice gekopieerd';

  @override
  String get submitButtonLabel => 'Versturen';

  @override
  String get orderAlreadyTaken => 'Deze order is al geaccepteerd';

  @override
  String get nodeProtocolUnsupported =>
      'Deze Mostro-node spreekt een protocolversie die de app niet ondersteunt. Kies een andere node in de instellingen, of kijk of er een app-update is';

  @override
  String get nodeCapabilitiesUnknown =>
      'Nog aan het nagaan wat de gekozen Mostro-node ondersteunt. Probeer het zo weer';

  @override
  String get mostroMaintenanceMode =>
      'De Mostro-node waarmee je verbonden bent is in onderhoud. Probeer het later opnieuw, of verbind met een andere Mostro-node in de instellingen';

  @override
  String get storageUnavailable =>
      'De app kan geen orders plaatsen of accepteren zolang de lokale database niet beschikbaar is. Herstart de app en probeer het opnieuw';

  @override
  String get orderIdCopied => 'Order-ID gekopieerd';

  @override
  String get comingSoonMessage => 'Komt binnenkort';

  @override
  String get tradeStatusActive => 'Actief';

  @override
  String get tradeStatusCompleted => 'Afgerond';

  @override
  String get tradeStatusCancelled => 'Geannuleerd';

  @override
  String get tradeStatusDisputed => 'In dispuut';

  @override
  String get accountScreenTitle => 'Account';

  @override
  String get secretWordsTitle => 'Geheime woorden';

  @override
  String get privacyCardTitle => 'Privacy';

  @override
  String get reputationMode => 'Reputatiemodus';

  @override
  String get reputationModeSubtitle =>
      'Je trades tellen mee voor je publieke reputatie';

  @override
  String get fullPrivacyMode => 'Volledig privé';

  @override
  String get fullPrivacyModeSubtitle =>
      'Elke trade gebruikt een nieuwe identiteit, geen reputatie';

  @override
  String get generateNewUserButton => 'Nieuwe gebruiker aanmaken';

  @override
  String get importMostroUserButton => 'Mostro-gebruiker importeren';

  @override
  String get generateNewUserDialogTitle => 'Nieuwe gebruiker aanmaken?';

  @override
  String get generateNewUserDialogContent =>
      'Hiermee maak je een volledig nieuwe identiteit aan. Je huidige geheime woorden werken dan niet meer, dus zorg dat je die hebt opgeslagen voordat je doorgaat.';

  @override
  String get continueButtonLabel => 'Doorgaan';

  @override
  String get importMnemonicDialogTitle => 'Geheime woorden importeren';

  @override
  String get importMnemonicHintText => 'Vul je 12 of 24 woorden in…';

  @override
  String get importButtonLabel => 'Importeren';

  @override
  String get refreshUserDialogTitle => 'Gebruiker verversen?';

  @override
  String get refreshUserDialogContent =>
      'Hiermee worden je trades en orders opnieuw bij de Mostro-instantie opgehaald. Doe dit als je vermoedt dat je gegevens niet kloppen of er orders ontbreken.';

  @override
  String get hideButtonLabel => 'Verbergen';

  @override
  String get showWordsButton => 'Woorden tonen';

  @override
  String get settingsScreenTitle => 'Instellingen';

  @override
  String get languageSettingTitle => 'Taal';

  @override
  String get appearanceSettingTitle => 'Weergave';

  @override
  String get appearanceDialogTitle => 'Weergave';

  @override
  String get allCurrencies => 'Alle valuta';

  @override
  String get lightningAddressSettingTitle => 'Lightning-adres';

  @override
  String get nwcWalletSettingTitle => 'NWC-wallet';

  @override
  String get relaysSettingTitle => 'Relays';

  @override
  String get pushNotificationsSettingTitle => 'Pushmeldingen';

  @override
  String get logReportSettingTitle => 'Logboekrapport';

  @override
  String get mostroNodeSettingTitle => 'Mostro-node';

  @override
  String get themeDark => 'Donker';

  @override
  String get themeLight => 'Licht';

  @override
  String get themeSystemDefault => 'Systeeminstelling';

  @override
  String get lightningAddressDialogTitle => 'Lightning-adres';

  @override
  String get lightningAddressHintText => 'gebruiker@domein.nl';

  @override
  String get invalidLightningAddressFormat =>
      'Moet de vorm gebruiker@domein hebben';

  @override
  String get clearButtonLabel => 'Wissen';

  @override
  String get saveButtonLabel => 'Opslaan';

  @override
  String get scanQrCodeTitle => 'QR-code scannen';

  @override
  String get selectLanguageTitle => 'Taal kiezen';

  @override
  String get selectCurrencyDialogTitle => 'Valuta kiezen';

  @override
  String get addRelayDialogTitle => 'Relay toevoegen';

  @override
  String get addButtonLabel => 'Toevoegen';

  @override
  String get relayHintText => 'wss://relay.example.com';

  @override
  String get relayErrorMustStartWithWss => 'Moet met wss:// beginnen';

  @override
  String get relayErrorUrlTooShort => 'De URL is te kort';

  @override
  String get relayErrorDuplicate => 'Deze relay staat al in de lijst';

  @override
  String get pasteQrCodeHeading => 'Inhoud van de QR-code plakken';

  @override
  String get pasteButtonLabel => 'Plakken';

  @override
  String get clipboardEmptyError => 'Het klembord is leeg';

  @override
  String get enterValueError => 'Vul een waarde in';

  @override
  String get trustedBadgeLabel => 'Vertrouwd';

  @override
  String get confirmButtonLabel => 'Bevestigen';

  @override
  String get selectMostroNode => 'Kies een node';

  @override
  String get addCustomNode => 'Je eigen node toevoegen';

  @override
  String get nodePubkeyFieldLabel => 'Publieke sleutel';

  @override
  String get nodePubkeyFieldHint => '64 tekens hex of npub…';

  @override
  String get nodeNameOptionalLabel => 'Naam (optioneel)';

  @override
  String get invalidPubkeyFormat =>
      'Vul een geldige publieke sleutel in (64 tekens hex of npub)';

  @override
  String get privateKeyNotAllowed =>
      'Dat is een privésleutel. Deel die nooit; vul de publieke sleutel van de node in';

  @override
  String get nodeAlreadyExists => 'Deze node staat al in de lijst';

  @override
  String get nodeAddedSuccess => 'Node toegevoegd';

  @override
  String nodeSwitchedSuccess(String nodeName) {
    return 'Je gebruikt nu $nodeName';
  }

  @override
  String get errorSwitchingNode =>
      'Overschakelen naar een andere node is mislukt';

  @override
  String get cannotRemoveActiveNode =>
      'De node die je nu gebruikt kun je niet verwijderen. Schakel eerst over naar een andere';

  @override
  String get deleteCustomNodeTitle => 'Node verwijderen';

  @override
  String get deleteCustomNodeMessage =>
      'Deze eigen node uit je lijst verwijderen?';

  @override
  String get deleteCustomNodeConfirm => 'Verwijderen';

  @override
  String get nodeRemovedSuccess => 'Node verwijderd';

  @override
  String get nodeStorageUnavailable =>
      'De lokale database is nog niet klaar. Herstart de app en probeer het opnieuw';

  @override
  String nodeSelectorSubtitle(String code) {
    return 'Orders en valuta voor $code, jouw valuta';
  }

  @override
  String get nodeSelectorSubtitleNoCurrency => 'Openstaande orders per node';

  @override
  String nodeMissingCurrencyChip(String code) {
    return 'GEEN $code';
  }

  @override
  String get nodeOrdersNowLabel => 'orders nu';

  @override
  String get nodeNoOrdersLabel => 'geen orders';

  @override
  String nodeOrdersInCurrency(int count, String code) {
    return '· $count in $code';
  }

  @override
  String get nodeFeeLabel => 'kosten';

  @override
  String get nodeFeeTooltip => 'Mostro verdeelt de kosten over beide partijen.';

  @override
  String get nodePerTradeLabel => 'per trade';

  @override
  String get nodeCustodyLightning => 'Lightning-bewaring';

  @override
  String nodeCustodyCashu(String mint) {
    return 'Cashu-bewaring · $mint';
  }

  @override
  String get nodeCustodyUnknown => 'Bewaring onbekend';

  @override
  String nodeBondPct(String pct) {
    return 'Borg $pct%';
  }

  @override
  String get nodeBondNone => 'Geen borg';

  @override
  String nodeStatusOnline(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count orders',
      one: '1 order',
    );
    return 'Online · $_temp0';
  }

  @override
  String get nodeStatusNoUsefulOrders => 'Geen orders in jouw valuta';

  @override
  String nodeStatusUnreachable(String ago) {
    return 'Reageert niet · laatst gezien $ago';
  }

  @override
  String get nodeStatusUnreachableNoSignal => 'Reageert niet';

  @override
  String get nodeDisclaimerShort =>
      'Elke node wordt beheerd door een zelfstandige derde partij. Mostro is niet verantwoordelijk voor hun handelen of voor jouw trades.';

  @override
  String get nodeVerifyKeyWarning =>
      'Controleer de sleutel bij de beheerder. Een valse node kan je orders zien.';

  @override
  String get nodeInvalidPubkeyShort => 'Dit is geen geldige publieke sleutel.';

  @override
  String get nodeNameFieldHint => 'Lokale Mostro';

  @override
  String get nodePubkeyCopied => 'Sleutel gekopieerd';

  @override
  String get nodeNotSelectableOffline => 'Deze node reageert niet';

  @override
  String get nodeStatsLoading => 'Nodegegevens laden';

  @override
  String get nodeSwitchConfirmTitle => 'Van node wisselen?';

  @override
  String nodeSwitchConfirmBody(String currentNode, String newNode) {
    return 'Je hebt een lopende trade op $currentNode. Die blijft daar staan; het orderboek toont voortaan $newNode.';
  }

  @override
  String get nodeSwitchConfirmAction => 'Van node wisselen';

  @override
  String get nodeTradesCheckFailed =>
      'Je trades konden niet worden gecontroleerd. Probeer het opnieuw.';

  @override
  String get notificationsScreenTitle => 'Meldingen';

  @override
  String get markAllAsReadMenuItem => 'Alles markeren als gelezen';

  @override
  String get clearAllMenuItem => 'Alles wissen';

  @override
  String get youMustBackUpYourAccount => 'Maak een back-up van je account';

  @override
  String get tapToViewAndSaveSecretWords =>
      'Tik om je geheime woorden te bekijken en op te slaan.';

  @override
  String get noNotifications => 'Geen meldingen';

  @override
  String get markAsRead => 'Markeren als gelezen';

  @override
  String get deleteNotificationLabel => 'Verwijderen';

  @override
  String get rateScreenHeader => 'BEOORDELEN';

  @override
  String get successfulOrder => 'Geslaagde order';

  @override
  String get closeRatingButton => 'SLUITEN';

  @override
  String get aboutScreenTitle => 'Over';

  @override
  String get linkCopiedToClipboard => 'Link gekopieerd';

  @override
  String get pubkeyLabel => 'Pubkey';

  @override
  String get relaysLabel => 'Relays';

  @override
  String get footerTagline => 'Open source. Non-custodial. Privé.';

  @override
  String get drawerTitle => 'Mostro';

  @override
  String get drawerTagline => 'P2P-exchange';

  @override
  String get drawerStageBadge => 'Alfa';

  @override
  String drawerVersion(String version) {
    return 'Versie $version';
  }

  @override
  String get drawerAccountMenuItem => 'Account';

  @override
  String get drawerSettingsMenuItem => 'Instellingen';

  @override
  String get drawerAboutMenuItem => 'Over';

  @override
  String get navOrderBook => 'Orderboek';

  @override
  String get navMyTrades => 'Mijn trades';

  @override
  String get navChat => 'Chat';

  @override
  String get loadingOrders => 'Orders laden…';

  @override
  String get errorLoadingOrders =>
      'De orders konden niet worden geladen. Controleer je verbinding.';

  @override
  String get retry => 'Opnieuw';

  @override
  String disableRelayLabel(String url) {
    return 'Relay $url uitschakelen';
  }

  @override
  String enableRelayLabel(String url) {
    return 'Relay $url inschakelen';
  }

  @override
  String get removeRelayTooltip => 'Relay verwijderen';

  @override
  String get relayAddFailed => 'De relay kon niet worden toegevoegd';

  @override
  String get relayRemoveFailed => 'De relay kon niet worden verwijderd';

  @override
  String get backupRitualSecondFailureMessage =>
      'Dat klopte opnieuw niet. Bekijk je geheime woorden, sla ze op en begin de controle dan van voren af aan.';

  @override
  String get cancelTradeDialogTitle => 'Trade annuleren?';

  @override
  String get cancelTradeDialogContent =>
      'Je vraagt een annulering in overleg aan. De tegenpartij moet ook akkoord gaan voordat de trade helemaal vervalt.';

  @override
  String get cancelTradeDialogContentNotStarted =>
      'De trade is nog niet begonnen, dus hij wordt meteen geannuleerd. De tegenpartij hoeft niet akkoord te gaan.';

  @override
  String get cancelTradeDialogContentMaybeStarted =>
      'Is de trade nog niet begonnen, dan wordt hij meteen geannuleerd. Is hij wel begonnen, dan moet de tegenpartij ook akkoord gaan.';

  @override
  String get noButtonLabel => 'Nee';

  @override
  String get yesButtonLabel => 'Ja';

  @override
  String get yesCancelButtonLabel => 'Ja, annuleren';

  @override
  String get cancelRequestSent => 'Annuleringsverzoek verstuurd';

  @override
  String get cancelRequestFailed =>
      'Annuleren is mislukt. Probeer het opnieuw.';

  @override
  String get tradeCardCancelRequestedByMeTitle => 'Annulering aangevraagd';

  @override
  String get tradeCardCancelRequestedByMeMessage =>
      'Je hebt gevraagd deze trade te annuleren. Hij blijft open tot de tegenpartij ook annuleert. Reageert hij niet, dan kun je een dispuut openen.';

  @override
  String get tradeCardCancelRequestedByPeerTitle =>
      'De tegenpartij wil annuleren';

  @override
  String get tradeCardCancelRequestedByPeerMessage =>
      'Hij heeft gevraagd deze trade te annuleren. Ga je akkoord, dan eindigt hij zonder dat er geld verschuift; anders gaat de handel door.';

  @override
  String get tradeCancelRequestedByMeNotice =>
      'Je hebt gevraagd deze trade te annuleren. Hij blijft open tot de tegenpartij ook annuleert. Reageert hij niet, dan kun je een dispuut openen.';

  @override
  String get tradeCancelRequestedByPeerNotice =>
      'De tegenpartij heeft gevraagd deze trade te annuleren. Ga je akkoord, dan eindigt hij zonder dat er geld verschuift; anders gaat de handel door.';

  @override
  String get acceptCancelButton => 'Annulering accepteren';

  @override
  String get cancelTradeDialogContentAccept =>
      'De tegenpartij heeft om annulering gevraagd. Nu annuleren beëindigt de trade voor jullie allebei, zonder dat er geld verschuift.';

  @override
  String get fiatSentFailed =>
      'De fiat kon niet als verstuurd worden gemeld. Probeer het opnieuw.';

  @override
  String get releaseFailed => 'Vrijgeven is mislukt. Probeer het opnieuw.';

  @override
  String get cancelTradeButton => 'Trade annuleren';

  @override
  String get payHoldInvoiceButton => 'Hold invoice betalen';

  @override
  String get openDisputeButton => 'Dispuut openen';

  @override
  String get releaseSatsButton => 'Sats vrijgeven';

  @override
  String get confirmReleaseSatsButton => 'Bevestigen en sats vrijgeven';

  @override
  String get shareOrderButton => 'Order delen';

  @override
  String get orderPillYouAreSelling => 'JE VERKOOPT';

  @override
  String get orderPillYouAreBuying => 'JE KOOPT';

  @override
  String get myOrderSellTitle => 'Je verkooporder';

  @override
  String get myOrderBuyTitle => 'Je kooporder';

  @override
  String get cancelOrderFailed =>
      'De order kon niet worden geannuleerd. Probeer het opnieuw.';

  @override
  String get closeButtonLabel => 'Sluiten';

  @override
  String get copyButtonLabel => 'Kopiëren';

  @override
  String get orderStatusWaitingForTaker => 'Wacht op een tegenpartij';

  @override
  String get orderStatusInProgress => 'Lopend';

  @override
  String get orderStatusExpired => 'Verlopen';

  @override
  String get copyOrderIdTooltip => 'Order-ID kopiëren';

  @override
  String get orderNotFoundTitle => 'Order niet gevonden';

  @override
  String get orderNotFoundMessage => 'Deze order is niet meer beschikbaar.';

  @override
  String get orderCancelledSuccess => 'De order is geannuleerd.';

  @override
  String get aboutDocumentationTitle => 'Documentatie';

  @override
  String get aboutMostroNodeTitle => 'Mostro-node';

  @override
  String get aboutVersionLabel => 'Versie';

  @override
  String get aboutCommitHashLabel => 'Commit-hash';

  @override
  String get aboutLicenseLabel => 'Licentie';

  @override
  String get aboutLicenseName => 'AGPLv3+';

  @override
  String get aboutGithubRepoName => 'MostroP2P/app';

  @override
  String get aboutCopiedToClipboard => 'Gekopieerd';

  @override
  String get aboutLicenseDialogTitle => 'GNU Affero General Public License v3';

  @override
  String get aboutNodeLoadingText => 'Nodegegevens laden…';

  @override
  String get aboutNodeUnavailable => 'Geen nodegegevens beschikbaar';

  @override
  String get aboutNodeRetry => 'Opnieuw';

  @override
  String get aboutLightningNetworkSection => 'Lightning Network';

  @override
  String get aboutFiatCurrenciesLabel => 'Fiatvaluta';

  @override
  String get aboutMostroVersionLabel => 'Mostro-versie';

  @override
  String get aboutMostroCommitLabel => 'Mostro-commit';

  @override
  String get aboutHoldInvoiceExpLabel => 'Verlooptijd hold invoice';

  @override
  String get aboutHoldInvoiceCltvLabel => 'CLTV hold invoice';

  @override
  String get aboutInvoiceExpWindowLabel => 'Geldigheidsduur invoice';

  @override
  String get aboutProofOfWorkLabel => 'Proof of work';

  @override
  String get aboutMaxOrdersPerResponseLabel => 'Max. orders per antwoord';

  @override
  String get aboutLndVersionLabel => 'LND-versie';

  @override
  String get aboutSupportedChainsLabel => 'Ondersteunde chains';

  @override
  String get aboutSupportedNetworksLabel => 'Ondersteunde netwerken';

  @override
  String get aboutSatoshisSuffix => 'Satoshi';

  @override
  String get aboutBlocksSuffix => 'blokken';

  @override
  String get aboutFiatCurrenciesAll => 'Alle';

  @override
  String get aboutAntiAbuseBondSection => 'Borg tegen misbruik';

  @override
  String get aboutBondEnabledValue => 'Aan';

  @override
  String get aboutBondDisabledValue => 'Uit';

  @override
  String get aboutBondUnsupportedValue => 'Niet ondersteund';

  @override
  String get aboutBondStatusLabel => 'Status van de borg';

  @override
  String get aboutBondAppliesToLabel => 'Geldt voor';

  @override
  String get aboutBondAppliesToTakers => 'Wie accepteert';

  @override
  String get aboutBondAppliesToMakers => 'Wie plaatst';

  @override
  String get aboutBondAppliesToBoth => 'Beide partijen';

  @override
  String get aboutBondAmountLabel => 'Hoogte van de borg';

  @override
  String get aboutBondBaseAmountLabel => 'Minimale borg';

  @override
  String get aboutBondNodeShareLabel => 'Deel voor de node bij inhouding';

  @override
  String get aboutBondSlashOnTimeoutLabel => 'Inhouden bij te lang wachten';

  @override
  String get aboutBondClaimWindowLabel => 'Termijn om op te halen';

  @override
  String aboutBondClaimWindowValue(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count dagen',
      one: '$count dag',
    );
    return '$_temp0';
  }

  @override
  String get openDisputeFailed =>
      'Het dispuut kon niet worden geopend. Probeer het opnieuw.';

  @override
  String get openDisputeTitle => 'Dispuut openen';

  @override
  String get openDisputeConfirmation =>
      'Weet je zeker dat je een dispuut wilt openen? Daarmee gaat de trade naar een beheerder en dat kan niet ongedaan worden gemaakt.';

  @override
  String get disputeAlreadyOpen => 'Voor deze trade loopt al een dispuut.';

  @override
  String get tradeNotDisputable =>
      'Een dispuut kan pas worden geopend zodra het geld voor deze trade vaststaat.';

  @override
  String get tradeWaitingInvoiceBuyerInstruction =>
      'Lever je Lightning-invoice aan, zodat de verkoper het geld kan vastzetten.';

  @override
  String get tradeWaitingInvoiceSellerInstruction =>
      'Wacht tot de koper zijn Lightning-invoice aanlevert.';

  @override
  String get tradeWaitingPaymentSellerInstruction =>
      'Betaal de hold invoice om het geld vast te zetten en de trade te starten.';

  @override
  String get tradeLoadError => 'Er ging iets mis bij het laden van de trade.';

  @override
  String get tradeWaitingForHoldInvoice => 'Wachten op de hold invoice…';

  @override
  String get shareButtonLabel => 'Delen';

  @override
  String get shareFailed => 'De invoice kon niet worden gedeeld';

  @override
  String get waitingForPaymentConfirmation =>
      'Wachten op bevestiging van de betaling…';

  @override
  String get orderNoLongerActive => 'Deze order is niet meer actief';

  @override
  String get tradeNoLongerYours => 'Je hoort niet meer bij deze trade';

  @override
  String get sessionTimeoutMessage =>
      'Geen antwoord ontvangen, controleer je verbinding en probeer het later opnieuw';

  @override
  String get noIdentityFoundMessage =>
      'Geen identiteit gevonden. Herstart de app.';

  @override
  String get failedToLoadSecretWordsMessage =>
      'De geheime woorden konden niet worden geladen. Probeer het opnieuw.';

  @override
  String get privacyModesInfoTitle => 'Privacymodi';

  @override
  String get privacyModesInfoContent =>
      'In de reputatiemodus zien anderen je geslaagde trades.\n\nVolledig privé houdt alles wat je doet anoniem, maar je bouwt dan geen reputatie op.';

  @override
  String get failedToGenerateIdentityMessage =>
      'De identiteit kon niet worden aangemaakt. Probeer het opnieuw.';

  @override
  String get invalidMnemonicMessage =>
      'Ongeldige woordenreeks. Controleer je woorden en probeer het opnieuw.';

  @override
  String get enterValidMnemonicError =>
      'Vul een geldige reeks van 12 of 24 woorden in.';

  @override
  String get orderBookRefreshedMessage => 'Orderboek ververst';

  @override
  String get refreshFailedMessage => 'Verversen mislukt';

  @override
  String get refreshButtonLabel => 'Verversen';

  @override
  String get okButtonLabel => 'OK';

  @override
  String get moreInformationTooltip => 'Meer informatie';

  @override
  String get backedUpBadgeLabel => 'Veiliggesteld';

  @override
  String get backupBannerTitle => 'Stel je reputatie veilig';

  @override
  String get backupBannerSubtitle =>
      'Sla je 12 woorden op. Het kost een minuut.';

  @override
  String get failedToSaveBackupStatusMessage =>
      'De back-upstatus kon niet worden opgeslagen. Probeer het opnieuw.';

  @override
  String get backupRitualStep1Title => 'Stap 1 van 3 · Schrijf je woorden op';

  @override
  String get backupRitualStep2Title => 'Stap 2 van 3 · Controleren';

  @override
  String get backupRitualStep3Title => 'Stap 3 van 3 · Klaar';

  @override
  String get backupRitualWarningTitle => 'Schrijf ze op papier. ';

  @override
  String get backupRitualWarningBody =>
      'Bewaar ze niet in foto’s, schermafbeeldingen of de cloud: wie deze 12 woorden heeft, kan je reputatie stelen.';

  @override
  String get wordsHiddenOnLeaveNote =>
      'Ze worden verborgen zodra je dit scherm verlaat';

  @override
  String get wroteThemDownVerifyButton => 'Opgeschreven, nu controleren';

  @override
  String get tapCorrectWordsTitle => 'Tik de juiste woorden aan';

  @override
  String get verifyInstructionsBody =>
      'We vragen er 3 willekeurig. Heb je ze goed, dan weten we dat ze veilig op papier staan.';

  @override
  String optionsForWordLabel(int number) {
    return 'KEUZES VOOR WOORD #$number';
  }

  @override
  String get wrongPickMessage =>
      'Net niet. Kijk op je papier en probeer het opnieuw.';

  @override
  String get allWordsCorrectMessage => 'Alle 3 de woorden goed';

  @override
  String get reviewWordsButton => 'Woorden bekijken';

  @override
  String get accountBackedUpTitle => 'Je account is veiliggesteld';

  @override
  String get accountBackedUpBody =>
      'Je reputatie is veilig. Raak je ooit je telefoon kwijt, dan herstel je je account met je 12 woorden.';

  @override
  String wordNumberLabel(int number) {
    return 'Woord #$number';
  }

  @override
  String get backupTriggerBody =>
      'Je reputatie zit in een sleutel die alleen jij hebt. Raak je je telefoon kwijt, dan ben je die reputatie kwijt. ';

  @override
  String get backupTriggerBodyHighlight => 'Stel hem in een minuut veilig.';

  @override
  String get backupStepWriteDown => 'Schrijf je 12 woorden op papier';

  @override
  String get backupStepVerifyRandom =>
      'We vragen er 3 willekeurig ter controle';

  @override
  String get backupStepSecured => 'Klaar: je account is veiliggesteld';

  @override
  String get backupNowButton => 'Nu veiligstellen';

  @override
  String get backupLaterButton => 'Later';

  @override
  String get nwcConnectionFailedMessage =>
      'Verbinden is mislukt. Controleer je NWC-URI en probeer het opnieuw.';

  @override
  String get clipboardInvalidNwcUriMessage =>
      'Op het klembord staat geen geldige NWC-URI.';

  @override
  String get scanQrButtonLabel => 'QR scannen';

  @override
  String get connectButtonLabel => 'Verbinden';

  @override
  String get walletDisconnectedMessage => 'Wallet losgekoppeld';

  @override
  String get relayLabel => 'Relay';

  @override
  String get disconnectButtonLabel => 'Verbreken';

  @override
  String relaysMoreSuffix(int count) {
    return '(+$count meer)';
  }

  @override
  String get chooseNotificationEventsSubtitle =>
      'Kies waarvoor je een melding in de app krijgt.';

  @override
  String get notifTradeUpdatesTitle => 'Wijzigingen in trades';

  @override
  String get notifTradeUpdatesSubtitle =>
      'Statuswijzigingen in je lopende trades';

  @override
  String get notifNewMessagesTitle => 'Nieuwe berichten';

  @override
  String get notifNewMessagesSubtitle => 'Berichten van je tegenpartij';

  @override
  String get notifPaymentAlertsTitle => 'Betaalmeldingen';

  @override
  String get notifPaymentAlertsSubtitle =>
      'Bevestigde en mislukte Lightning-betalingen';

  @override
  String get notifDisputeUpdatesTitle => 'Wijzigingen in disputen';

  @override
  String get notifDisputeUpdatesSubtitle =>
      'Acties van de beheerder en uitkomsten van disputen';

  @override
  String get searchCurrenciesHint => 'Valuta zoeken…';

  @override
  String get noCurrenciesFoundMessage => 'Geen valuta gevonden';

  @override
  String get shareLogsTooltip => 'Logboek delen';

  @override
  String get noLogsToShareTooltip => 'Geen logboek om te delen';

  @override
  String get noLogEntriesMessage => 'Geen logregels';

  @override
  String get failedToShareLogsMessage => 'Het logboek kon niet worden gedeeld';

  @override
  String get logReportShareHeading => 'Mostro-logboekrapport';

  @override
  String get tradeFilterAll => 'Alle';

  @override
  String get tradeFilterPending => 'In afwachting';

  @override
  String get tradeFilterWaitingInvoice => 'Wacht op invoice';

  @override
  String get tradeFilterWaitingPayment => 'Wacht op betaling';

  @override
  String get tradeFilterActive => 'Actief';

  @override
  String get tradeFilterFiatSent => 'Fiat verstuurd';

  @override
  String get tradeFilterSuccess => 'Gelukt';

  @override
  String get tradeFilterCanceled => 'Geannuleerd';

  @override
  String get tradeFilterDispute => 'Dispuut';

  @override
  String get menuTooltip => 'Menu';

  @override
  String get noTradesTitle => 'Geen trades';

  @override
  String get noTradesSubtitle =>
      'Je lopende en afgeronde trades verschijnen hier.';

  @override
  String get couldNotLoadTradesMessage =>
      'De trades konden niet worden geladen';

  @override
  String get sellingBitcoin => 'Bitcoin verkopen';

  @override
  String get buyingBitcoin => 'Bitcoin kopen';

  @override
  String get tradeInstructionActiveBuyer =>
      'Heb je het geld overgemaakt, meld dat dan hieronder. Open alleen een dispuut als de verkoper niet meer reageert.';

  @override
  String get tradeInstructionFiatSentBuyer =>
      'Je hebt de fiatbetaling als verstuurd gemeld. Wacht tot de verkoper de ontvangst bevestigt en je sats vrijgeeft.';

  @override
  String get tradeInstructionActiveSeller =>
      'Geef de koper via de chat hierboven door hoe hij moet betalen.';

  @override
  String get tradeInstructionFiatSentSeller =>
      'De koper heeft bevestigd dat hij de fiat heeft overgemaakt. Controleer of het binnen is en geef daarna de sats vrij.';

  @override
  String get tradeInstructionDisputed =>
      'Er is een solver toegewezen. Hij neemt via de app contact met je op.';

  @override
  String get tradeInstructionPending =>
      'Je order staat gepubliceerd en wacht op een tegenpartij. Je kunt hem altijd annuleren.';

  @override
  String get tradeInstructionCancelled =>
      'Deze trade is geannuleerd. Er is geen geld geruild.';

  @override
  String get tradeInstructionInProgress => 'Trade loopt.';

  @override
  String get theAgreedAmount => 'het afgesproken bedrag';

  @override
  String get tradeHeadlinePending => 'Wachten op een tegenpartij';

  @override
  String get tradeHeadlineInProgress => 'De trade wordt opgezet';

  @override
  String get tradeHeadlineWaitingInvoiceBuyer =>
      'Deel een Lightning-invoice om je sats te ontvangen';

  @override
  String get tradeHeadlineWaitingInvoiceSeller =>
      'Wachten tot de koper een invoice deelt';

  @override
  String get tradeHeadlineWaitingPaymentBuyer =>
      'Wachten tot de verkoper de sats vastzet';

  @override
  String get tradeHeadlineWaitingPaymentSeller =>
      'Betaal de hold invoice om de sats vast te zetten';

  @override
  String tradeHeadlineActiveBuyer(String amount) {
    return 'Maak $amount over aan de verkoper';
  }

  @override
  String tradeHeadlineActiveSeller(String amount) {
    return 'Wachten tot de koper $amount overmaakt';
  }

  @override
  String get tradeHeadlineFiatSentBuyer =>
      'Wachten tot de verkoper je sats vrijgeeft';

  @override
  String tradeHeadlineFiatSentSeller(String amount) {
    return 'Bevestig dat je $amount hebt ontvangen';
  }

  @override
  String get tradeHeadlineDisputed => 'Dispuut in behandeling';

  @override
  String get tradeHeadlineCancelled => 'Order geannuleerd';

  @override
  String get tradeHeadlineLoading => 'Trade laden…';

  @override
  String get tradeTimerPendingConsequence =>
      'Verloopt de tijd, dan gaat de order uit het orderboek. Dat raakt je reputatie niet.';

  @override
  String get tradeTimerWaitingInvoiceConsequence =>
      'Verloopt de tijd, dan wordt de trade geannuleerd en komt de order terug in het orderboek.';

  @override
  String get tradeStepOrderTaken => 'Order geaccepteerd';

  @override
  String get tradeStepInvoiceBuyer => 'De verkoper zet de sats vast';

  @override
  String get tradeStepInvoiceSeller => 'Jij zet de sats vast';

  @override
  String get tradeStepFiatBuyer => 'Jij maakt de fiat over';

  @override
  String get tradeStepFiatSeller => 'De koper maakt de fiat over';

  @override
  String get tradeStepReleaseBuyer => 'De verkoper geeft je sats vrij';

  @override
  String get tradeStepReleaseSeller => 'Jij bevestigt en geeft de sats vrij';

  @override
  String get tradeStepRate => 'Beoordeel de trade';

  @override
  String tradeCreatedAtLabel(String date) {
    return 'aangemaakt $date';
  }

  @override
  String stepIndicator(int current, int total) {
    return 'STAP $current VAN $total';
  }

  @override
  String get addLightningInvoiceButton => 'Lightning-invoice toevoegen';

  @override
  String get viewDisputeButton => 'Dispuut bekijken';

  @override
  String get yourTradeTimelineTitle => 'JOUW TRADE';

  @override
  String get messageSendFailed =>
      'Het bericht kon niet worden verstuurd. Probeer het opnieuw.';

  @override
  String get invalidTradeId => 'Ongeldig trade-ID';

  @override
  String get selectForDetailsHint => 'Kies ℹ of 👤\nvoor details';

  @override
  String noMessagesYet(String handle) {
    return 'Nog geen berichten.\nZeg hallo tegen $handle!';
  }

  @override
  String get exchangeInfoTooltip => 'Gegevens van de ruil';

  @override
  String get userInfoTooltip => 'Gebruikersgegevens';

  @override
  String chattingWith(String handle) {
    return 'Je chat met $handle';
  }

  @override
  String get unknownPeerHandle => 'Onbekend';

  @override
  String get messagesTab => 'Berichten';

  @override
  String get disputesTab => 'Disputen';

  @override
  String get tradeInformationTitle => 'Tradegegevens';

  @override
  String get orderIdLabel => 'Order-ID';

  @override
  String get fiatAmountLabel => 'Fiatbedrag';

  @override
  String get satsAmountLabel => 'Aantal sats';

  @override
  String get statusLabel => 'Status';

  @override
  String get paymentMethodLabel => 'Betaalmethode';

  @override
  String get createdLabel => 'Aangemaakt';

  @override
  String get tradeDetailsPlaceholder =>
      'Details worden aangesloten zodra de trade-provider er is (fase 10+)';

  @override
  String get userInformationTitle => 'Gebruikersgegevens';

  @override
  String get peerPublicKeyLabel => 'Publieke sleutel van de ander';

  @override
  String get yourSharedKeyLabel => 'Je gedeelde sleutel';

  @override
  String get sharedKeyPlaceholder =>
      'Beschikbaar na de bridge-integratie (fase 10+)';

  @override
  String get sharedKeySafetyNote =>
      'Bewaar je gedeelde sleutel goed: die is nodig om een dispuut op te lossen';

  @override
  String get attachmentLabel => '[Bijlage]';

  @override
  String get downloadTooltip => 'Downloaden';

  @override
  String get fileDownloadPlaceholder =>
      'Downloaden wordt aangesloten in fase 10+';

  @override
  String get fileTypeVideo => 'Video';

  @override
  String get fileTypeImage => 'Afbeelding';

  @override
  String get fileTypeArchive => 'Archief';

  @override
  String get fileTypeFile => 'Bestand';

  @override
  String get tapToDownload => 'Tik om te downloaden';

  @override
  String get imageDownloadPlaceholder =>
      'Afbeeldingen downloaden wordt aangesloten in fase 10+';

  @override
  String buyingSatsAmount(String sats) {
    return 'Je koopt $sats sats';
  }

  @override
  String sellingSatsAmount(String sats) {
    return 'Je verkoopt $sats sats';
  }

  @override
  String get viewOrderLink => 'Order bekijken';

  @override
  String timeLeftLabel(String time) {
    return 'nog $time';
  }

  @override
  String get invoiceNoLongerExpected =>
      'Deze order wacht niet meer op een invoice. De status wordt bijgewerkt…';

  @override
  String get invoiceSubmitInFlight =>
      'Er wordt al een invoice voor deze order verstuurd. Wacht op het antwoord.';

  @override
  String get waitingForTradeAmount =>
      'Wachten op het handelsbedrag. Probeer het zo weer.';

  @override
  String get fetchingTradeAmount => 'Handelsbedrag ophalen…';

  @override
  String get enterInvoiceManually => 'Invoice handmatig invullen';

  @override
  String get submitButton => 'Versturen';

  @override
  String get buyerReputation => 'Reputatie van de koper';

  @override
  String get sellerReputation => 'Reputatie van de verkoper';

  @override
  String get ratingStatLabel => 'beoordeling';

  @override
  String get tradesStatLabel => 'trades';

  @override
  String get daysActiveStatLabel => 'dagen actief';

  @override
  String timeRemainingLabel(String time) {
    return 'Resterende tijd: $time';
  }

  @override
  String orderAmountOutOfRange(int min, int max) {
    return 'Het bedrag moet tussen $min en $max sats liggen voor deze Mostro-node';
  }

  @override
  String orderAmountOutOfRangeFiat(int min, int max, String currency) {
    return 'Het bedrag moet tussen $min en $max $currency liggen voor deze Mostro-node';
  }

  @override
  String get priceTypeMarket => 'Markt';

  @override
  String get priceTypeFixed => 'Vast';

  @override
  String get priceTypeInfoTooltip => 'Over de prijssoort';

  @override
  String get premiumSectionLabel => 'Premie';

  @override
  String get fixedPriceRangeNotAvailable =>
      'Een vaste prijs kan niet bij een bandbreedte-order. Zet de bandbreedte uit om een vaste prijs te gebruiken.';

  @override
  String get priceTypesDialogTitle => 'Prijssoorten';

  @override
  String get priceTypesDialogContent =>
      'Marktprijs: je orderprijs volgt de marktkoers, met een premie of korting erbij.\n\nVaste prijs: je legt een exact bedrag in satoshi vast.';

  @override
  String get newOrderTitle => 'Nieuwe order';

  @override
  String get amountSectionSell => 'Hoeveel je verkoopt';

  @override
  String get amountSectionBuy => 'Hoeveel je koopt';

  @override
  String get amountModeSingle => 'Eén bedrag';

  @override
  String get amountModeRange => 'Bandbreedte';

  @override
  String get amountMinLabel => 'Minimum';

  @override
  String get amountMaxLabel => 'Maximum';

  @override
  String paymentMethodsChosenCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count gekozen',
      one: '1 gekozen',
      zero: 'niets gekozen',
    );
    return '$_temp0';
  }

  @override
  String get paymentMethodAdd => 'Toevoegen';

  @override
  String get paymentMethodSearchHint => 'Methodes zoeken';

  @override
  String get customPaymentMethodLabel => 'Eigen betaalmethode';

  @override
  String get priceSectionTitle => 'Prijs';

  @override
  String premiumSellAbove(String premium) {
    return 'Je verkoopt $premium% boven de marktprijs';
  }

  @override
  String premiumSellBelow(String premium) {
    return 'Je verkoopt $premium% onder de markt';
  }

  @override
  String premiumBuyBelow(String premium) {
    return 'Je betaalt $premium% minder dan de markt';
  }

  @override
  String premiumBuyAbove(String premium) {
    return 'Je betaalt $premium% meer';
  }

  @override
  String get premiumExactMarket => 'Precies de marktprijs';

  @override
  String get fixedPriceNote =>
      'Bij een vaste prijs volgt de order de markt niet: het aantal sats blijft precies zoals jij het invult.';

  @override
  String get previewHintNoAmount =>
      'Vul een bedrag in, dan zie je hier hoe de order eruitziet.';

  @override
  String previewSellMarket(String amount, String premium, String active) {
    return 'Je verkoopt BTC voor $amount tegen marktprijs $premium$active';
  }

  @override
  String previewSellMarketExact(String amount, String active) {
    return 'Je verkoopt BTC voor $amount tegen marktprijs$active';
  }

  @override
  String previewBuyMarket(String amount, String premium, String active) {
    return 'Je koopt BTC voor $amount tegen marktprijs $premium$active';
  }

  @override
  String previewBuyMarketExact(String amount, String active) {
    return 'Je koopt BTC voor $amount tegen marktprijs$active';
  }

  @override
  String previewSellFixed(String sats, String amount, String active) {
    return 'Je verkoopt $sats voor $amount tegen een vaste prijs$active';
  }

  @override
  String previewBuyFixed(String sats, String amount, String active) {
    return 'Je koopt $sats voor $amount tegen een vaste prijs$active';
  }

  @override
  String previewActiveSuffix(String hours) {
    return ' · actief $hours';
  }

  @override
  String get publishOrder => 'Order publiceren';

  @override
  String removePaymentMethod(String method) {
    return '$method verwijderen';
  }

  @override
  String get satsUnitLabel => 'sats';

  @override
  String satsAmount(String amount) {
    return '$amount sats';
  }

  @override
  String durationHours(int hours) {
    return '$hours u';
  }

  @override
  String get paymentMethodsLabel => 'Betaalmethodes';

  @override
  String get customPaymentMethodHint => 'Eigen betaalmethode…';

  @override
  String amountRangeError(String min, String max) {
    return 'Het bedrag moet tussen $min en $max liggen';
  }

  @override
  String get enterAmountTitle => 'Bedrag invullen';

  @override
  String minMaxRangeLabel(String min, String max, String currency) {
    return 'Min: $min – Max: $max $currency';
  }

  @override
  String get ratingFailed => 'De beoordeling is mislukt. Probeer het opnieuw.';

  @override
  String get submitUppercaseButton => 'VERSTUREN';

  @override
  String selectStarTooltip(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sterren geven',
      one: '1 ster geven',
    );
    return '$_temp0';
  }

  @override
  String get disputeDetailsTitle => 'Dispuutgegevens';

  @override
  String get disputeIdLabel => 'Dispuut-ID';

  @override
  String disputeReasonLabel(String reason) {
    return 'Reden: $reason';
  }

  @override
  String get adminLabel => 'Beheerder';

  @override
  String get disputeScreenTitle => 'Dispuut';

  @override
  String get filtersDialogTitle => 'Filters';

  @override
  String get resetButton => 'Herstellen';

  @override
  String get currencyLabel => 'Valuta';

  @override
  String get ratingLabel => 'Beoordeling';

  @override
  String get applyButton => 'Toepassen';

  @override
  String get successLabel => 'Gelukt';

  @override
  String get copyButton => 'Kopiëren';

  @override
  String get shareButton => 'Delen';

  @override
  String sendSatsToAddress(String sats) {
    return 'Stuur $sats sats naar:';
  }

  @override
  String get changeButton => 'Wijzigen';

  @override
  String get unableToOpenNotification => 'De melding kan niet worden geopend.';

  @override
  String get reasonBestPremium => 'Beste premie';

  @override
  String get reasonMostReputable => 'Beste reputatie';

  @override
  String get marketPriceCaption => 'Marktprijs';

  @override
  String reputationTradesLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'trades',
      one: 'trade',
    );
    return '$_temp0';
  }

  @override
  String reputationDaysLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'dagen',
      one: 'dag',
    );
    return '$_temp0';
  }

  @override
  String get sortNewest => 'Nieuwste';

  @override
  String ordersCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count orders',
      one: '1 order',
    );
    return '$_temp0';
  }

  @override
  String get sortBestPremium => 'Beste premie';

  @override
  String get sortBestReputation => 'Beste reputatie';

  @override
  String get sortSheetTitle => 'Sorteren op';

  @override
  String get orderCardPremiumCaption => 'premie';

  @override
  String orderFixedAmount(String sats) {
    return 'Vast bedrag · voor $sats';
  }

  @override
  String get reputationNew => 'Nieuw';

  @override
  String get reputationNoTrades => 'geen trades';

  @override
  String get bottomNavBook => 'Orderboek';

  @override
  String get bottomNavTrades => 'Trades';

  @override
  String get fabDismissHint => 'Tik ernaast om te sluiten';

  @override
  String get addOrderFabLabel => 'Order plaatsen';

  @override
  String get ordersEmptyHint =>
      'Nieuwe orders verschijnen hier zodra ze gepubliceerd worden.';

  @override
  String get ordersEmptyFilteredHint =>
      'Geen orders die aan je filters voldoen.';

  @override
  String get clearFiltersButton => 'Filters wissen';

  @override
  String get hideEarlierEvents => 'Eerdere gebeurtenissen verbergen';

  @override
  String viewEarlierEvents(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count eerdere gebeurtenissen tonen',
      one: '1 eerdere gebeurtenis tonen',
    );
    return '$_temp0';
  }

  @override
  String get goToTrade => 'Naar de trade';

  @override
  String get disputeWord => 'Dispuut';

  @override
  String get tradeWord => 'Trade';

  @override
  String get notifFilterAll => 'Alle';

  @override
  String get notifFilterDisputes => 'Disputen';

  @override
  String notifFilterDisputesCount(int count) {
    return 'Disputen · $count';
  }

  @override
  String get notifFilterSystem => 'Systeem';

  @override
  String notifFilterSystemCount(int count) {
    return 'Systeem · $count';
  }

  @override
  String get payingStatus => 'Betalen…';

  @override
  String get payWithWalletButton => 'Betalen met wallet';

  @override
  String get generatingInvoiceNwc => 'Invoice aanmaken via NWC…';

  @override
  String get unableToGenerateInvoice =>
      'De invoice kan niet automatisch worden aangemaakt';

  @override
  String get avatarIconLabel => 'Avatar';

  @override
  String get disputeDescResolvedBuyerFavour =>
      'Dispuut beslist in het voordeel van de koper';

  @override
  String get disputeDescResolvedYourFavour =>
      'Dispuut in jouw voordeel beslist';

  @override
  String get disputeDescResolvedSellerFavour =>
      'Dispuut beslist in het voordeel van de verkoper';

  @override
  String get disputeDescCooperativeCancel => 'Order in overleg geannuleerd';

  @override
  String get disputeDescResolved => 'Dispuut opgelost';

  @override
  String get disputeDescYouOpened => 'Jij hebt dit dispuut geopend';

  @override
  String get disputeDescCounterpartOpened =>
      'De tegenpartij heeft dit dispuut geopend';

  @override
  String get notificationsBellNoUnread => 'Meldingen, geen ongelezen meldingen';

  @override
  String get notificationsBellBackupActive =>
      'Meldingen, herinnering om je account veilig te stellen';

  @override
  String notificationsBellUnread(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Meldingen, $count ongelezen',
      one: 'Meldingen, 1 ongelezen',
    );
    return '$_temp0';
  }

  @override
  String drawerBadgeNewCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count nieuw',
      one: '1 nieuw',
    );
    return '$_temp0';
  }

  @override
  String get bondSlashedViewPolicy => 'Voorwaarden bekijken';

  @override
  String get bondSlashedViewTrade => 'Trade bekijken';

  @override
  String bondSlashedTradeNoticeDispute(String sats) {
    return 'De node heeft je borg van $sats sats ingehouden in dit dispuut.';
  }

  @override
  String bondSlashedTradeNoticeTimeout(String sats) {
    return 'De node heeft je borg van $sats sats ingehouden nadat een stap te lang duurde.';
  }

  @override
  String get bondSlashedTitle => 'Borg ingehouden';

  @override
  String bondSlashedMessageTimeout(String amount, String orderId) {
    return 'Je borg tegen misbruik van $amount sats voor order $orderId is vervallen nadat een wachtstap te lang duurde. De status van je order verandert niet.';
  }

  @override
  String bondSlashedMessageDispute(String amount, String orderId) {
    return 'Je borg tegen misbruik van $amount sats voor order $orderId is vervallen na de uitkomst van een dispuut. De status van je order verandert niet.';
  }

  @override
  String get bondSlashedCauseTimeout => 'Te lang in de wachtstand';

  @override
  String get bondSlashedCauseDispute => 'Uitkomst van het dispuut';

  @override
  String get bondSlashedDetailOrder => 'Order';

  @override
  String get bondSlashedDetailAmount => 'Hoogte van de borg';

  @override
  String get bondSlashedDetailCause => 'Oorzaak';

  @override
  String get bondSlashedDetailFiat => 'Fiat';

  @override
  String get bondSlashedDetailPaymentMethod => 'Betaalmethode';

  @override
  String aboutDaysValue(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count dagen',
      one: '$count dag',
    );
    return '$_temp0';
  }

  @override
  String get aboutCashuEscrowSection => 'Cashu-escrow';

  @override
  String get aboutCashuMintUrlLabel => 'Mint';

  @override
  String get aboutCashuMintNotAdvertised => 'Niet opgegeven';

  @override
  String get aboutCashuLocktimeLabel => 'Locktime van de escrow';

  @override
  String get aboutCashuSettlementMarginLabel => 'Afwikkelingsmarge';

  @override
  String get escrowModeLightning => 'Lightning';

  @override
  String get escrowModeCashu => 'Cashu';

  @override
  String get escrowModeUnknown => 'Niet opgegeven';

  @override
  String get settingsEscrowOverrideTitle => 'Escrow-backend (ontwikkelaar)';

  @override
  String get settingsEscrowOverrideSubtitle =>
      'Cashu testen tegen een node die het nog niet aanbiedt. Alleen in debug-builds.';

  @override
  String get settingsForceCashuLabel => 'Cashu-escrow afdwingen';

  @override
  String get settingsCashuMintOverrideLabel => 'Mint-URL overschrijven';

  @override
  String get settingsCashuMintOverrideApply => 'Toepassen';

  @override
  String get settingsCashuMintOverrideInvalid =>
      'Dat is geen geldige mint-URL. Gebruik http of https met een host.';

  @override
  String settingsEscrowEffectiveMode(String mode) {
    return 'Actieve backend: $mode';
  }

  @override
  String settingsEscrowEffectiveMint(String mint) {
    return 'Actieve mint: $mint';
  }

  @override
  String get settingsEscrowCashuUnavailable =>
      'Cashu werkt niet zonder mint. Stel er hieronder een in.';

  @override
  String get tradeStatusPayoutPending => 'Uitbetaling wacht';

  @override
  String get tradeHeadlinePayoutPending =>
      'Wachten op de uitbetaling aan de koper';

  @override
  String get tradeInstructionPayoutPending =>
      'De verkoper heeft de escrow vrijgegeven. Wachten tot de Lightning-betaling aan de koper slaagt.';

  @override
  String get tradeScreenTitle => 'Jouw trade';

  @override
  String get tradeChipWaiting => 'WACHTEN';

  @override
  String get tradeChipActive => 'ACTIEF';

  @override
  String get tradeChipYourTurn => 'ACTIE VEREIST';

  @override
  String get tradeChipDispute => 'DISPUUT';

  @override
  String get tradeChatLockedNote =>
      'Nog geen chat: zolang de trade niet actief is, weet geen van beiden wie de ander is.';

  @override
  String get tradeChatEncrypted => 'End-to-end versleutelde chat';

  @override
  String get tradeBodyWaitingPaymentBuyer =>
      'Hij betaalt de hold invoice. Zodra de sats vaststaan, is het aan jou om de fiat over te maken.';

  @override
  String tradeBodyActiveSeller(String method) {
    return 'Deel je $method-gegevens in de chat hierboven.';
  }

  @override
  String tradeBodyActiveBuyer(String method) {
    return 'Via $method, met de gegevens die hij in de chat heeft gedeeld. Heb je het overgemaakt, meld dat dan hieronder.';
  }

  @override
  String tradeBodyFiatSentSeller(String method) {
    return 'De koper heeft de betaling als verstuurd gemeld. Controleer je $method-rekening voordat je vrijgeeft.';
  }

  @override
  String get tradeReleaseIrreversible =>
      'De sats vrijgeven kan niet ongedaan worden gemaakt.';

  @override
  String get tradeTimerYouHave => 'Jij hebt nog';

  @override
  String get tradeTimerTheyHave => 'Hij heeft nog';

  @override
  String get tradeTimerOrderHas => 'Resterende tijd';

  @override
  String get tradeTimerNoteCoordinate =>
      'Heb je meer tijd nodig, overleg dat in de chat voordat de tijd om is.';

  @override
  String get tradeRoleBuyer => 'Koper';

  @override
  String get tradeRoleSeller => 'Verkoper';

  @override
  String reputationTradesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count trades',
      one: '1 trade',
    );
    return '$_temp0';
  }

  @override
  String reputationDaysOnMostro(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count dagen op Mostro',
      one: '1 dag op Mostro',
    );
    return '$_temp0';
  }

  @override
  String get tradeFiatSentAction => 'Ik heb betaald';

  @override
  String get tradeCloseAction => 'Sluiten';

  @override
  String get tradeSendRatingAction => 'Beoordeling versturen';

  @override
  String get tradeCompletedTitle => 'Trade afgerond';

  @override
  String tradeRatedCounterpart(String alias, String score) {
    return 'Je hebt $alias $score gegeven';
  }

  @override
  String get tradeIdLabel => 'ID';

  @override
  String tradeCreatedTodayLabel(String time) {
    return 'vandaag aangemaakt om $time';
  }

  @override
  String get releaseSheetTitle => 'De sats vrijgeven?';

  @override
  String get releaseSheetBody =>
      'Dit kan niet ongedaan worden gemaakt. Geef pas vrij als het geld op je rekening staat.';

  @override
  String get releaseSheetConfirm => 'Ja, vrijgeven';

  @override
  String get releaseSheetBack => 'Terug';

  @override
  String get orderSideChipSell => 'Je verkoopt BTC';

  @override
  String get orderSideChipBuy => 'Je koopt BTC';

  @override
  String orderDetailMarketPremium(String premium) {
    return 'Marktprijs · premie $premium';
  }

  @override
  String myOrderWaitingNote(String ago) {
    return 'Gepubliceerd $ago. Je krijgt bericht zodra iemand hem accepteert: je kunt dit scherm sluiten.';
  }

  @override
  String get orderStatusTakenWaitingInvoice =>
      'Geaccepteerd · wacht op invoice';

  @override
  String get orderStatusTakenWaitingPayment =>
      'Geaccepteerd · wacht op betaling';

  @override
  String get orderDetailCreatedLabel => 'Aangemaakt';

  @override
  String get orderDetailIdLabel => 'ID';

  @override
  String paymentMethodsMore(String first, int count) {
    return '$first +$count';
  }

  @override
  String get paymentMethodsSheetTitle => 'Betaalmethodes';

  @override
  String get cancelOrderSheetTitle => 'De order annuleren?';

  @override
  String get cancelOrderSheetBody =>
      'Hij gaat uit het orderboek en dat kan niet ongedaan worden gemaakt.';

  @override
  String get goBackButtonLabel => 'Terug';

  @override
  String get takeOrderYouPay => 'Jij betaalt';

  @override
  String get takeOrderYouReceive => 'Jij ontvangt';

  @override
  String get takeOrderYouSend => 'Jij stuurt';

  @override
  String takeOrderSatsFrom(String sats) {
    return 'vanaf $sats';
  }

  @override
  String takeOrderMarketFooter(String premium) {
    return 'Marktprijs · premie $premium. Het uiteindelijke bedrag staat vast zodra je hem accepteert.';
  }

  @override
  String takeOrderFixedFooterSeller(String sats) {
    return 'Vast bedrag · de verkoper vraagt $sats';
  }

  @override
  String takeOrderFixedFooterBuyer(String sats) {
    return 'Vast bedrag · de koper biedt $sats';
  }

  @override
  String get counterpartySeller => 'Verkoper';

  @override
  String get counterpartyBuyer => 'Koper';

  @override
  String counterpartyTrades(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count trades',
      one: '$count trade',
    );
    return '$_temp0';
  }

  @override
  String counterpartyDaysOnMostro(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count dagen op Mostro',
      one: '$count dag op Mostro',
    );
    return '$_temp0';
  }

  @override
  String get takeOrderPayWithLabel => 'Jij betaalt met';

  @override
  String get takeOrderPaidWithLabel => 'Jij wordt betaald met';

  @override
  String get takeOrderPublishedLabel => 'Gepubliceerd';

  @override
  String get takeOrderNoteBuyer =>
      'Accepteer je hem, dan zet de verkoper de sats vast in Mostro. Jij betaalt pas als ze vaststaan.';

  @override
  String get takeOrderNoteSeller =>
      'Accepteer je hem, dan zet jij de sats vast in Mostro. De koper betaalt daarna.';

  @override
  String get takeOrderButton => 'Order accepteren';

  @override
  String get takeOrderTaking => 'Accepteren…';

  @override
  String get takeOrderUnavailable => 'Niet meer beschikbaar';

  @override
  String get takeOrderClosed => 'Gesloten';

  @override
  String get easterEggWhitepaper =>
      '31 oktober 2008: negen pagina\'s, niemand om toestemming gevraagd. Fijne Halloween.';

  @override
  String get easterEggGenesis =>
      'The Times 03/Jan/2009 Chancellor on brink of second bailout for banks';

  @override
  String get easterEggPizzaDay =>
      '22 mei 2010: 10.000 BTC voor twee pizza\'s. Hopelijk waren ze lekker.';

  @override
  String get settingsGroupApp => 'App';

  @override
  String get settingsGroupPayments => 'Betalingen';

  @override
  String get settingsGroupNetwork => 'Netwerk';

  @override
  String get settingsGroupHelp => 'Hulp';

  @override
  String get fiatCurrencySettingTitle => 'Fiatvaluta';

  @override
  String notificationsEnabledOfTotal(int count, int total) {
    return '$count van $total';
  }

  @override
  String get notificationsAllOff => 'Uit';

  @override
  String get lightningAddressUnset => 'Niet ingesteld';

  @override
  String get nwcWalletNotConnected => 'Niet verbonden';

  @override
  String relaysConnectedOfTotal(int connected, int total) {
    return '$connected van $total verbonden';
  }

  @override
  String get relaysSummaryHealthy =>
      'Je ontvangt orders en berichten zoals het hoort';

  @override
  String get relaysSummaryAtRisk => 'Je ziet mogelijk geen nieuwe orders meer';

  @override
  String get relayStatusConnected => 'Verbonden';

  @override
  String get relayStatusOffline => 'Geen verbinding';

  @override
  String get addRelayButtonLabel => 'Relay toevoegen';

  @override
  String get relaysFootnote =>
      'Relays dragen je orders en berichten. Met minder dan twee verbonden relays zie je mogelijk geen nieuwe orders meer.';

  @override
  String get lastRelayBlockedMessage =>
      'Houd minstens één relay actief: zonder relays kun je geen orders zien of plaatsen.';

  @override
  String get nwcExplainerTitle => 'Verbind je wallet';

  @override
  String get nwcExplainerSubtitle => 'Met Nostr Wallet Connect';

  @override
  String get nwcExplainerBody =>
      'Mostro haalt en betaalt je invoices dan uit deze wallet, zodat je nooit met de hand een invoice hoeft te kopiëren.';

  @override
  String get nwcUriFieldLabel => 'Verbindings-URI';

  @override
  String get nwcUriPlaceholder => 'nostr+walletconnect://…';

  @override
  String get nwcStorageFootnote =>
      'De URI blijft alleen op dit apparaat en wordt nooit op Nostr gepubliceerd.';

  @override
  String get walletConnectedMessage => 'Wallet verbonden';

  @override
  String get nwcConnectedStatus => 'Verbonden';

  @override
  String nwcBalanceSats(String sats) {
    return '$sats sats';
  }

  @override
  String get notificationsSystemDenied =>
      'Meldingen staan uit in je systeeminstellingen.';

  @override
  String get openSystemSettingsAction => 'Instellingen openen';

  @override
  String get notificationsPrivacyFootnote =>
      'Meldingen bevatten geen bedragen en geen tegenpartijen. Een push loopt via de servers van Google of Apple en zegt alleen dát er iets te zien is.';

  @override
  String get pushMasterToggleTitle => 'Pushmeldingen';

  @override
  String get pushMasterToggleSubtitle =>
      'Wekt de app zodra er een trade-gebeurtenis of chatbericht binnenkomt. De melding zelf bevat niets.';

  @override
  String get pushStatusOff =>
      'Uit: er staat niets geregistreerd bij de push-server';

  @override
  String pushStatusCleanupPending(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Uit: $count push-registraties worden nog verwijderd',
      one: 'Uit: 1 push-registratie wordt nog verwijderd',
    );
    return '$_temp0';
  }

  @override
  String get pushStatusNoToken => 'Wachten op het push-token van dit apparaat';

  @override
  String get pushStatusIdle => 'Aan: geen lopende trades om te registreren';

  @override
  String pushStatusRegistered(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Geregistreerd voor $count trades',
      one: 'Geregistreerd voor 1 trade',
    );
    return '$_temp0';
  }

  @override
  String pushStatusLastRegistered(String ago) {
    return 'laatst geregistreerd $ago';
  }

  @override
  String get pushStatusUnreachable =>
      'Push-server niet bereikbaar, nieuwe poging volgt';

  @override
  String get pushStatusNodeRefused =>
      'De push-server accepteert deze Mostro-node niet';

  @override
  String get pushStatusRateLimited =>
      'Limiet voor push-verzoeken bereikt, zo volgt een nieuwe poging';

  @override
  String get pushUnsupportedPlatform =>
      'Pushmeldingen zijn niet beschikbaar op dit platform';

  @override
  String get pushToggleSaveFailed =>
      'De pushmeldingen konden niet worden gewijzigd';

  @override
  String get pushNewMessageBody => 'Je hebt een nieuw bericht';

  @override
  String get notificationPrefSaveFailed =>
      'Die voorkeur kon niet worden opgeslagen';

  @override
  String get logsScreenTitle => 'Logboek';

  @override
  String get logFilterAll => 'Alle';

  @override
  String get logFilterRelays => 'Relays';

  @override
  String get logFilterOrders => 'Orders';

  @override
  String get logFilterPayments => 'Betalingen';

  @override
  String get verboseLoggingTitle => 'Uitgebreid loggen';

  @override
  String get verboseLoggingSubtitle => 'Meer details, meer batterijverbruik';

  @override
  String get newLogsChipLabel => 'Nieuwe regels';

  @override
  String get noLogsForFilter => 'Geen regels voor dit filter';

  @override
  String get aboutAppSection => 'App';

  @override
  String get aboutSourceCodeLabel => 'Broncode';

  @override
  String get aboutUserGuideLabel => 'Handleiding';

  @override
  String get aboutTechnicalDocsLabel => 'Technische documentatie';

  @override
  String get aboutLanguageSpanish => 'Spaans';

  @override
  String get aboutLanguageEnglish => 'Engels';

  @override
  String get aboutConnectedNodeTitle => 'Verbonden node';

  @override
  String get aboutMinOrderCell => 'Min. order';

  @override
  String get aboutMaxOrderCell => 'Max. order';

  @override
  String get aboutFeeCell => 'Kosten';

  @override
  String aboutFeeValue(String value) {
    return '$value%';
  }

  @override
  String get aboutLimitsFootnote => 'Grenzen in satoshi per order';

  @override
  String get aboutNodeTechnicalDataRow => 'Technische gegevens van de node';

  @override
  String aboutFieldCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count velden',
      one: '$count veld',
    );
    return '$_temp0';
  }

  @override
  String get aboutTechnicalDataTitle => 'Technische gegevens';

  @override
  String get aboutPublicKeyLabel => 'Publieke sleutel';

  @override
  String get aboutOrderExpiryLabel => 'Verlooptijd van een order';

  @override
  String get aboutWaitingTimeoutLabel => 'Tijdslimiet in de wachtstand';

  @override
  String aboutHoursShort(int count) {
    return '$count u';
  }

  @override
  String aboutSecondsShort(int count) {
    return '$count s';
  }

  @override
  String get aboutAliasLabel => 'Naam';

  @override
  String get aboutNodePublicKeyLabel => 'Publieke sleutel van de node';

  @override
  String get aboutNodeUriLabel => 'URI van de node';

  @override
  String get aboutCommitLabel => 'Commit';

  @override
  String get aboutChainNetworkLabel => 'Chain en netwerk';

  @override
  String get aboutTechnicalFootnote =>
      'Deze gegevens identificeren de node waarmee je handelt. Handig bij ondersteuning, of om hem te controleren voordat je geld stuurt.';

  @override
  String get aboutCopyAllData => 'Alle gegevens kopiëren';

  @override
  String get tradesGroupNeedsAction => 'Actie vereist';

  @override
  String get tradesGroupInProgress => 'Lopend';

  @override
  String get tradesGroupClosed => 'Gesloten';

  @override
  String get tradesDirectionSell => 'Je verkoopt';

  @override
  String get tradesDirectionBondClaim => 'Borg ophalen';

  @override
  String get tradesDirectionBuy => 'Je koopt';

  @override
  String tradesCounterpartyTo(String handle) {
    return 'aan $handle';
  }

  @override
  String tradesCounterpartyFrom(String handle) {
    return 'van $handle';
  }

  @override
  String get tradeListChipYourTurn => 'Actie vereist';

  @override
  String get tradeListChipPublished => 'Gepubliceerd';

  @override
  String get tradeListChipInProgress => 'Lopend';

  @override
  String get tradeListChipWaitingInvoice => 'Wacht op invoice';

  @override
  String get tradeListChipWaitingPayment => 'Wacht op betaling';

  @override
  String get tradeListChipWaitingSats => 'Wacht op sats';

  @override
  String get tradeListChipDispute => 'In dispuut';

  @override
  String get tradeListChipCompleted => 'Afgerond';

  @override
  String get tradeListChipCancelled => 'Geannuleerd';

  @override
  String get tradeListChipExpired => 'Verlopen';

  @override
  String get tradeVerbAddInvoice => 'Invoice toevoegen';

  @override
  String get tradeVerbPayBond => 'Borg betalen';

  @override
  String get tradeHeadlineWaitingBond => 'Zet je borg vast om door te gaan';

  @override
  String get tradeInstructionWaitingBond =>
      'De node houdt je acceptatie vast tot de terugbetaalbare borg betaald is. De order blijft ondertussen open voor anderen.';

  @override
  String get takeOrderBondNotice =>
      'Deze node vraagt wie een order accepteert eerst een terugbetaalbare borg vast te zetten; die komt terug als de trade eerlijk verloopt.';

  @override
  String takeOrderBondNoticeEstimate(String sats) {
    return 'Deze node vraagt wie een order accepteert eerst een terugbetaalbare borg van ≈ $sats sats vast te zetten; die komt terug als de trade eerlijk verloopt.';
  }

  @override
  String get tradeVerbPayInvoice => 'Invoice betalen';

  @override
  String get tradeVerbSendPayment => 'Betaling versturen';

  @override
  String get tradeVerbReleaseSats => 'Sats vrijgeven';

  @override
  String get tradeVerbRate => 'Beoordelen';

  @override
  String get tradeListFilterAll => 'Alle';

  @override
  String get tradeListFilterActive => 'Actief';

  @override
  String get tradeListFilterCompleted => 'Afgerond';

  @override
  String get tradeListFilterCancelled => 'Geannuleerd';

  @override
  String get tradeListFilterTitle => 'Trades tonen';

  @override
  String get relativeTimeNow => 'nu';

  @override
  String relativeTimeMinutes(int count) {
    return '$count min geleden';
  }

  @override
  String relativeTimeHours(int count) {
    return '$count u geleden';
  }

  @override
  String get relativeTimeYesterday => 'gisteren';

  @override
  String satsFigureEstimate(String sats) {
    return '≈ $sats sats';
  }

  @override
  String satsFigureExact(String sats) {
    return '$sats sats';
  }

  @override
  String get chatGroupActive => 'Lopende trades';

  @override
  String chatContextSellActive(String amount, String currency) {
    return 'Je verkoopt $amount $currency';
  }

  @override
  String chatContextBuyActive(String amount, String currency) {
    return 'Je koopt $amount $currency';
  }

  @override
  String chatContextSellClosed(String amount, String currency) {
    return 'Je hebt $amount $currency verkocht';
  }

  @override
  String chatContextBuyClosed(String amount, String currency) {
    return 'Je hebt $amount $currency gekocht';
  }

  @override
  String get chatTurnAddInvoice => 'jij moet de invoice toevoegen';

  @override
  String get chatTurnPayBond => 'jij moet de borg betalen';

  @override
  String get chatTurnPayInvoice => 'jij moet de invoice betalen';

  @override
  String get chatTurnSendPayment => 'jij moet betalen';

  @override
  String get chatTurnRelease => 'jij moet vrijgeven';

  @override
  String get chatTurnRate => 'jij moet beoordelen';

  @override
  String get chatYouLabel => 'Jij:';

  @override
  String get chatListFootnote =>
      'Elk gesprek hoort bij één trade en is end-to-end versleuteld. Als de trade voorbij is, blijft het hier staan om terug te lezen.';

  @override
  String get chatListEmptyTitle => 'Nog geen gesprekken';

  @override
  String get chatListEmptyBody =>
      'Er opent een chat zodra een trade actief wordt.';

  @override
  String get chatClosedNotice =>
      'Deze trade is voorbij. Het gesprek blijft hier staan om terug te lezen.';

  @override
  String disputeOpenedByYou(String time) {
    return 'Jij hebt het $time geopend';
  }

  @override
  String disputeOpenedByPeer(String time) {
    return 'De tegenpartij heeft het $time geopend';
  }

  @override
  String get invoiceReceiveTitle => 'Ontvang je sats';

  @override
  String get invoiceLockTitle => 'Zet je sats vast';

  @override
  String get bondTitle => 'Borg tegen misbruik';

  @override
  String get bondRefundableLabel => 'TERUGBETAALBARE BORG';

  @override
  String get bondComesBack => 'komt terug zodra de trade is afgerond';

  @override
  String bondFiatComesBack(String fiat) {
    return '≈ $fiat · komt terug zodra de trade is afgerond';
  }

  @override
  String bondPaySemantics(String sats) {
    return 'Terugbetaalbare borg van $sats sats';
  }

  @override
  String bondReleasesIn(String time) {
    return 'De order komt weer vrij als je niet binnen $time betaalt';
  }

  @override
  String bondRowHeld(String bold) {
    return 'De sats blijven $bold, ze worden niet uitgegeven';
  }

  @override
  String get bondRowHeldBold => 'vastgezet in je wallet';

  @override
  String bondRowReleased(String bold) {
    return 'Verloopt de trade goed, dan $bold';
  }

  @override
  String get bondRowReleasedBold => 'komt hij vanzelf weer vrij';

  @override
  String bondRowLost(String bold) {
    return 'Je raakt hem alleen kwijt als er een dispuut komt en $bold';
  }

  @override
  String bondRowLostTimeout(String bold) {
    return 'Je raakt hem kwijt als je een stap laat verlopen, of als er een dispuut komt en $bold';
  }

  @override
  String get bondRowLostBold => 'je dat verliest';

  @override
  String get bondWhyTitle => 'Waarom Mostro om een borg vraagt';

  @override
  String get bondWhyCustody =>
      'Mostro houdt geen geld vast en kan dus niemand straffen die een trade laat lopen; dat doet de borg, en die beschermt iedereen tegen oplichters.';

  @override
  String bondWhyHold(String hold) {
    return 'Het is een $hold invoice: je wallet reserveert de sats zonder ze te versturen, en zodra de trade klaar is vervalt die reservering vanzelf.';
  }

  @override
  String get bondWhyDispute =>
      'Open je een dispuut en win je dat, dan krijg je hem ook terug. Je bent hem alleen kwijt als je een dispuut verliest.';

  @override
  String get bondWhyDisputeTimeout =>
      'Open je een dispuut en win je dat, dan krijg je hem ook terug. Je bent hem alleen kwijt als je een dispuut verliest of een wachtstap laat verlopen.';

  @override
  String get bondReadDocs => 'Lees de documentatie';

  @override
  String get bondContextOrder => 'Order';

  @override
  String bondContextBuy(String fiat) {
    return 'Je koopt $fiat';
  }

  @override
  String bondContextSell(String fiat) {
    return 'Je verkoopt $fiat';
  }

  @override
  String get bondContextEquals => 'De borg bedraagt';

  @override
  String bondContextPercent(String pct) {
    return '$pct % van het bedrag';
  }

  @override
  String get bondDontPublish => 'De order niet publiceren';

  @override
  String get bondAbandoned =>
      'Order laten vallen. Er is niets gepubliceerd en niets in rekening gebracht.';

  @override
  String bondPublishesIn(String time) {
    return 'Nog niet gepubliceerd: de order vervalt als je niet binnen $time betaalt';
  }

  @override
  String get bondInvoiceMissingMaker =>
      'Dit apparaat heeft geen kopie van de borg-invoice, en de node stuurt die niet opnieuw voor een order die jij hebt geplaatst. Laat de order vallen en maak hem opnieuw aan.';

  @override
  String get bondExpiredBodyMaker =>
      'Er is niet op tijd betaald: de order is nooit gepubliceerd en er zijn geen sats uit je wallet gegaan.';

  @override
  String get bondExpiredNoticeMaker =>
      'De borg-invoice is verlopen; de order is niet gepubliceerd';

  @override
  String get orderStatusWaitingBond =>
      'Wacht op je borg, nog niet gepubliceerd';

  @override
  String get bondCancelNotAllowed =>
      'Deze order kan niet worden geannuleerd zolang de borg openstaat. Laat hem vallen vanuit het borgscherm.';

  @override
  String createOrderBondNoticeEstimate(String sats) {
    return 'Deze node vraagt je een terugbetaalbare borg van ≈ $sats sats vast te zetten voordat de order wordt gepubliceerd; die komt terug als de trade eerlijk verloopt.';
  }

  @override
  String get createOrderBondNotice =>
      'Deze node vraagt je een terugbetaalbare borg vast te zetten voordat de order wordt gepubliceerd; die komt terug als de trade eerlijk verloopt.';

  @override
  String get bondClaimTitle => 'Haal je deel op';

  @override
  String get bondClaimShareLabel => 'JOUW DEEL';

  @override
  String bondClaimShareSemantics(String sats) {
    return 'Deel van $sats sats om op te halen';
  }

  @override
  String bondClaimContext(String context) {
    return 'Uit de trade van $context';
  }

  @override
  String bondClaimDeadline(String date) {
    return 'Ophalen vóór $date';
  }

  @override
  String get bondClaimExplainer =>
      'De borg van de tegenpartij is in jouw voordeel verbeurd. Voeg een invoice toe voor precies dit bedrag, dan betaalt de node hem aan je uit.';

  @override
  String get bondClaimFieldLabel => 'Lightning-invoice';

  @override
  String get bondClaimFieldHint => 'lnbc… voor precies dat deel';

  @override
  String get bondClaimSubmit => 'Invoice versturen';

  @override
  String get bondClaimSent => 'Invoice naar de node verstuurd';

  @override
  String get bondClaimSubmittedTitle => 'Invoice verstuurd';

  @override
  String get bondClaimSubmittedBody => 'Wachten tot de node hem bevestigt.';

  @override
  String get bondClaimAcknowledgedTitle => 'Uitbetaling onderweg';

  @override
  String get bondClaimAcknowledgedBody =>
      'De node heeft je invoice aangenomen en betaalt hem. Lukt de routering niet, dan wordt om een nieuwe gevraagd.';

  @override
  String get bondClaimCompletedTitle => 'Betaald';

  @override
  String bondClaimCompletedBody(String sats) {
    return '$sats sats zijn in je wallet aangekomen.';
  }

  @override
  String get bondClaimExpiredTitle => 'De ophaaltermijn is voorbij';

  @override
  String bondClaimExpiredBody(String date) {
    return 'Die liep af op $date. Het deel kan niet meer worden opgehaald.';
  }

  @override
  String get bondClaimMissing => 'Geen claim gevonden voor deze order.';

  @override
  String get bondClaimErrorAmount =>
      'De invoice moet voor precies het getoonde deel zijn.';

  @override
  String get bondClaimErrorExpired =>
      'De ophaaltermijn is voorbij; het deel kan niet meer worden opgehaald.';

  @override
  String get bondClaimErrorRejected =>
      'De node heeft de invoice niet aangenomen. Probeer een andere.';

  @override
  String get bondClaimErrorNotClaimable =>
      'Voor deze claim kan nu geen invoice worden ingediend.';

  @override
  String get bondClaimErrorNoKey =>
      'Dit apparaat heeft geen sleutel voor die trade en kan het deel dus niet ophalen.';

  @override
  String get tradeVerbClaimPayout => 'Uitbetaling ophalen';

  @override
  String get chatTurnClaimPayout => 'jij moet de uitbetaling ophalen';

  @override
  String get tradeBadgePayoutPending => 'Uitbetaling wacht';

  @override
  String get tradeBadgePayoutInProgress => 'Uitbetaling onderweg';

  @override
  String get tradeBadgePayoutPaid => 'Uitbetaald';

  @override
  String bondBannerPendingTitle(String sats) {
    return '$sats sats staan klaar om naar je terug te komen';
  }

  @override
  String bondBannerPendingBody(String sats) {
    return 'De borg van de tegenpartij is in jouw voordeel verbeurd. Voeg een Lightning-invoice voor $sats sats toe om hem op te halen.';
  }

  @override
  String get bondBannerAddInvoice => 'Uitbetalingsinvoice toevoegen';

  @override
  String get bondBannerView => 'Claim bekijken';

  @override
  String get bondBannerInProgressTitle => 'Uitbetaling onderweg';

  @override
  String bondBannerInProgressBody(String sats) {
    return 'De node betaalt jouw deel van $sats sats.';
  }

  @override
  String get bondBannerPaidTitle => 'Uitbetaling ontvangen';

  @override
  String bondBannerPaidBody(String sats, String date) {
    return '$sats sats zijn op $date aan je uitbetaald.';
  }

  @override
  String bondBannerExpired(String date) {
    return 'De claim op de borg van de tegenpartij is op $date gesloten.';
  }

  @override
  String get bondClaimNewTitle => 'Uitbetaling van de borg op te halen';

  @override
  String bondClaimNewMessage(String sats) {
    return 'Je kunt $sats sats ophalen uit een ingehouden borg. Voeg een Lightning-invoice toe om ze te ontvangen.';
  }

  @override
  String get bondClaimPaidTitle => 'Uitbetaling van de borg ontvangen';

  @override
  String bondClaimPaidMessage(String sats) {
    return 'Uitbetaling van $sats sats uit de borg ontvangen.';
  }

  @override
  String get bondDontTake => 'De order niet accepteren';

  @override
  String get bondLockedNowEscrow =>
      'Borg vastgezet. Zet nu het handelsbedrag vast.';

  @override
  String get bondLostRace =>
      'Een andere gebruiker heeft deze order geaccepteerd voordat je borg betaald was';

  @override
  String get bondMakerCanceled => 'De plaatser heeft deze order geannuleerd';

  @override
  String get bondExpiredNotice =>
      'De borg-invoice is verlopen; de order is terug in het orderboek';

  @override
  String get bondExpiredTitle => 'De borg-invoice is verlopen';

  @override
  String get bondExpiredBody =>
      'Er is niet op tijd betaald: de order is terug in het orderboek en er zijn geen sats uit je wallet gegaan.';

  @override
  String get bondInvoiceMissing =>
      'Dit apparaat heeft geen kopie van de borg-invoice. Vraag hem opnieuw bij de node op om de order alsnog te accepteren.';

  @override
  String get bondRequestAgain => 'De invoice opnieuw opvragen';

  @override
  String get bondRequestFailed =>
      'De node heeft de borg-invoice niet opnieuw gestuurd';

  @override
  String get invoiceOrderIdCopied => 'Order-ID gekopieerd';

  @override
  String get invoiceYouReceiveLabel => 'Je ontvangt';

  @override
  String get invoiceToPayLabel => 'Te betalen';

  @override
  String invoiceReceiveSemantics(String sats) {
    return '$sats satoshi te ontvangen';
  }

  @override
  String invoicePaySemantics(String sats) {
    return '$sats satoshi te betalen';
  }

  @override
  String invoiceFeeIncluded(String sats) {
    return 'Inclusief $sats sats aan Mostro-kosten';
  }

  @override
  String invoiceTimeToSend(String time) {
    return 'Je hebt $time om hem te versturen';
  }

  @override
  String invoiceExpiresIn(String time) {
    return 'De invoice verloopt over $time';
  }

  @override
  String get invoiceFieldLabel => 'Lightning-invoice of -adres';

  @override
  String get invoiceFieldHint => 'lnbc… of gebruiker@domein';

  @override
  String get invoiceFieldPromptLabel => 'Plak hier je invoice';

  @override
  String get invoiceFieldFilledLabel => 'Lightning-invoice';

  @override
  String get invoiceFieldAddressLabel => 'Lightning-adres';

  @override
  String get invoiceScanButton => 'Scannen';

  @override
  String get invoiceReplaceButton => 'Vervangen';

  @override
  String get invoiceFieldSemantics => 'Lightning-invoice of -adres, verplicht';

  @override
  String invoiceFilledSemantics(String sats) {
    return 'Lightning-invoice voor $sats sats';
  }

  @override
  String get invoiceValidAddress =>
      'Geldig adres · de invoice wordt bij het versturen opgevraagd';

  @override
  String invoiceValidInvoice(String sats) {
    return 'Geldige invoice · $sats sats';
  }

  @override
  String invoiceErrorWrongAmount(String actual, String expected) {
    return 'De invoice is voor $actual sats, hij moet $expected zijn';
  }

  @override
  String get invoiceErrorExpired => 'De invoice is al verlopen';

  @override
  String invoiceErrorExpiresTooSoon(String minutes) {
    return 'De invoice verloopt binnen $minutes minuten; de node heeft meer tijd nodig om hem te betalen';
  }

  @override
  String get invoiceErrorMalformed =>
      'Deze invoice is onvolledig of verkeerd overgenomen';

  @override
  String get invoiceErrorUnrecognized =>
      'Geen invoice (lnbc…) en geen Lightning-adres (gebruiker@domein)';

  @override
  String get invoiceSellerLabel => 'Verkoper';

  @override
  String get invoiceBuyerLabel => 'Koper';

  @override
  String get invoiceYouPayLabel => 'Jij betaalt';

  @override
  String get invoiceYouGetLabel => 'Jij ontvangt';

  @override
  String get invoiceNoTrades => 'geen trades';

  @override
  String get invoiceSendButton => 'Invoice versturen';

  @override
  String get invoiceCancelTrade => 'Trade annuleren';

  @override
  String get invoiceOpenWallet => 'Openen in mijn wallet';

  @override
  String invoiceHoldNote(String hold) {
    return 'Dit is een $hold invoice: de sats staan vast en gaan pas uit je wallet als jij de betaling van de koper bevestigt.';
  }

  @override
  String invoiceQrSemantics(String invoice) {
    return 'QR-code van de Lightning-invoice: $invoice';
  }

  @override
  String get invoiceExpiredTitle => 'De invoice is verlopen';

  @override
  String get invoiceExpiredBody =>
      'Er is niet op tijd betaald: Mostro annuleert de trade en er zijn geen sats uit je wallet gegaan.';

  @override
  String get invoiceBackToBook => 'Terug naar het orderboek';

  @override
  String get invoiceTimeUpTitle => 'De tijd is om';

  @override
  String get invoiceTimeUpBody =>
      'De invoice is niet op tijd verstuurd: Mostro annuleert de trade. Van jouw kant is er niets vastgelegd.';

  @override
  String invoiceErrorWrongNetwork(String invoice, String node) {
    return 'De invoice is voor $invoice, de node gebruikt $node';
  }

  @override
  String invoiceCountdownHours(String hours, String minutes) {
    return '$hours u $minutes';
  }

  @override
  String get tradeCardWaitingBuyerInvoiceTitle =>
      'Wachten op de invoice van de koper';

  @override
  String get tradeCardWaitingBuyerInvoiceMessage =>
      'De trade gaat verder zodra de koper een Lightning-invoice toevoegt.';

  @override
  String get tradeCardWaitingPaymentTitle =>
      'Wachten op de betaling van de verkoper';

  @override
  String get tradeCardWaitingPaymentMessage =>
      'De trade gaat verder zodra de verkoper de hold invoice betaalt.';

  @override
  String get tradeCardWaitingTakerBondTitle => 'Borgbetaling staat open';

  @override
  String get tradeCardWaitingTakerBondMessage =>
      'De borg tegen misbruik van wie de order accepteert moet betaald zijn voordat de trade begint.';

  @override
  String get tradeCardActiveTitle => 'Trade actief';

  @override
  String get tradeCardActiveMessage =>
      'De sats staan vast. De koper kan nu de fiat overmaken.';

  @override
  String get tradeCardFiatSentTitle => 'Fiat als verstuurd gemeld';

  @override
  String get tradeCardFiatSentMessage =>
      'De koper heeft de fiatbetaling als verstuurd gemeld.';

  @override
  String get tradeCardSettledHoldInvoiceTitle => 'Sats vrijgegeven';

  @override
  String get tradeCardSettledHoldInvoiceMessage =>
      'De verkoper heeft de sats vrijgegeven. De uitbetaling aan de koper is onderweg.';

  @override
  String get tradeCardSuccessTitle => 'Trade afgerond';

  @override
  String get tradeCardSuccessMessage => 'De trade is goed afgelopen.';

  @override
  String get tradeCardCanceledTitle => 'Trade geannuleerd';

  @override
  String get tradeCardCanceledMessage => 'De trade is geannuleerd.';

  @override
  String get tradeCardExpiredTitle => 'Order verlopen';

  @override
  String get tradeCardExpiredMessage =>
      'De order is verlopen voordat de trade verder kon.';

  @override
  String get tradeCardCooperativelyCanceledTitle =>
      'Trade in overleg geannuleerd';

  @override
  String get tradeCardCooperativelyCanceledMessage =>
      'Beide partijen waren het eens over het annuleren van de trade.';

  @override
  String get tradeCardDisputeTitle => 'Dispuut geopend';

  @override
  String get tradeCardDisputeMessage =>
      'Er is een dispuut geopend over deze trade.';

  @override
  String get tradeCardCanceledByAdminTitle => 'Geannuleerd door de solver';

  @override
  String get tradeCardCanceledByAdminMessage =>
      'De solver heeft de trade geannuleerd.';

  @override
  String get tradeCardSettledByAdminTitle => 'Afgewikkeld door de solver';

  @override
  String get tradeCardSettledByAdminMessage =>
      'De solver heeft de sats aan de koper vrijgegeven.';

  @override
  String get tradeCardCompletedByAdminTitle => 'Afgerond door de solver';

  @override
  String get tradeCardCompletedByAdminMessage =>
      'De solver heeft de trade afgerond.';

  @override
  String get tradeCardUpdatedTitle => 'Trade bijgewerkt';

  @override
  String get tradeCardUpdatedMessage =>
      'De status van deze trade is veranderd.';

  @override
  String get tradeCardCanceledByMakerMessage =>
      'De plaatser heeft de order geannuleerd.';

  @override
  String get tradeCardCanceledBondLostRaceMessage =>
      'Een andere gebruiker heeft deze order geaccepteerd voordat de borg betaald was.';

  @override
  String get tradeCardCanceledBondExpiredMessage =>
      'De borg-invoice is onbetaald verlopen.';

  @override
  String get chatCardTitle => 'Nieuwe berichten';

  @override
  String get chatCardSolverTitle => 'Berichten van de solver';

  @override
  String chatCardMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count nieuwe berichten van je tegenpartij',
      one: '1 nieuw bericht van je tegenpartij',
    );
    return '$_temp0';
  }

  @override
  String chatCardSolverMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count nieuwe berichten van de solver',
      one: '1 nieuw bericht van de solver',
    );
    return '$_temp0';
  }

  @override
  String get invalidTradeIndexError =>
      'Je account loopt niet gelijk met deze Mostro-node, dus de order is geweigerd. Probeer het zo weer';

  @override
  String get recoveringTradesMessage =>
      'Account geïmporteerd. Je trades worden bij Mostro opgehaald…';

  @override
  String recoveredTradesMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Account geïmporteerd. $count trades hersteld',
      one: 'Account geïmporteerd. 1 trade hersteld',
      zero: 'Account geïmporteerd. Je had geen lopende trades',
    );
    return '$_temp0';
  }

  @override
  String get recoverTradesFailedMessage =>
      'Account geïmporteerd, maar Mostro gaf geen antwoord, dus je lopende trades zijn niet hersteld';

  @override
  String get paymentMethodsChosenLabel => 'Gekozen';

  @override
  String paymentMethodsSelectedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count methodes gekozen',
      one: '1 methode gekozen',
      zero: 'Kies minstens één methode',
    );
    return '$_temp0';
  }

  @override
  String get paymentMethodsConfirm => 'Methodes bevestigen';

  @override
  String get paymentMethodAddCustom => 'Eigen betaalmethode toevoegen';

  @override
  String get paymentMethodsDiscardTitle => 'De wijzigingen weggooien?';

  @override
  String get paymentMethodsDiscardConfirm => 'Weggooien';

  @override
  String get paymentMethodsKeepEditing => 'Verder bewerken';

  @override
  String get fundsAtRiskTitle => 'Deze gebruiker heeft nog sats in het spel';

  @override
  String get fundsAtRiskBody =>
      'Als je doorgaat, worden de sleutels van deze gebruiker vervangen en kan niets van wat hier staat nog vanaf dit apparaat worden afgerond of hersteld. Dit wordt afgeraden: je kunt deze sats kwijtraken.';

  @override
  String get fundsAtRiskSellerEscrow =>
      'Sats vastgezet in escrow voor een verkoop';

  @override
  String get fundsAtRiskBondLocked => 'Borg vastgezet';

  @override
  String get fundsAtRiskPayoutClaim => 'Borguitbetaling nog niet geïnd';

  @override
  String get fundsAtRiskTradeInProgress => 'Trade bezig';

  @override
  String get fundsAtRiskBondInvoicePending => 'Borgfactuur nog te betalen';

  @override
  String get fundsAtRiskKeep => 'Deze gebruiker houden';

  @override
  String get fundsAtRiskContinue => 'Toch doorgaan';
}

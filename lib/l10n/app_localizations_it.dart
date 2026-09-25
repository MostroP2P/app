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
  String get actionFailedAnnouncement => 'Azione non riuscita';

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

  @override
  String get disputeResolved => 'Risolto';

  @override
  String get disputeSuccessfullyCompleted => 'Completato con successo';

  @override
  String get disputeCoopCancelMessage =>
      'L\'ordine è stato annullato cooperativamente. Nessun fondo è stato trasferito.';

  @override
  String disputeWithBuyer(String handle) {
    return 'Controversia con l\'Acquirente: $handle';
  }

  @override
  String disputeWithSeller(String handle) {
    return 'Controversia con il Venditore: $handle';
  }

  @override
  String orderLabel(String orderId) {
    return 'Ordine $orderId';
  }

  @override
  String get disputeInitiated => 'Avviato';

  @override
  String get disputeInProgress => 'In corso';

  @override
  String get disputeStatusClosed => 'Chiuso';

  @override
  String get disputeLostFundsToBuyer =>
      'L\'amministratore ha risolto la controversia a favore dell\'acquirente. I sats sono stati rilasciati all\'acquirente.';

  @override
  String get disputeLostFundsToSeller =>
      'L\'amministratore ha annullato l\'ordine e restituito i sats al venditore. Non hai ricevuto i sats.';

  @override
  String get walkthroughSlideOneTitle =>
      'Scambia Bitcoin liberamente — senza KYC';

  @override
  String get walkthroughSlideOneBody =>
      'Mostro è un exchange peer-to-peer che ti consente di scambiare Bitcoin con qualsiasi valuta e metodo di pagamento — senza KYC e senza dover fornire i tuoi dati a nessuno. È costruito su Nostr, il che lo rende resistente alla censura. Nessuno può impedirti di fare trading.';

  @override
  String get walkthroughSlideTwoTitle => 'Privacy per impostazione predefinita';

  @override
  String get walkthroughSlideTwoBody =>
      'Mostro genera una nuova identità per ogni scambio, in modo che le tue operazioni non possano essere collegate. Puoi anche decidere quanto vuoi essere privato:\n• Modalità reputazione – Consente agli altri di vedere le tue operazioni riuscite e il tuo livello di fiducia.\n• Modalità privacy totale – Non viene costruita alcuna reputazione, ma la tua attività è completamente anonima.\nCambia modalità in qualsiasi momento dalla schermata Account, dove dovresti anche salvare le tue parole segrete — sono l\'unico modo per recuperare il tuo account.';

  @override
  String get walkthroughSlideThreeTitle => 'Sicurezza ad ogni passo';

  @override
  String get walkthroughSlideThreeBody =>
      'Mostro utilizza Hold Invoice (fatture trattenute): i sats rimangono nel portafoglio del venditore fino alla fine dello scambio. Questo protegge entrambe le parti. L\'app è anche progettata per essere intuitiva e facile da usare per ogni tipo di utente.';

  @override
  String get walkthroughSlideFourTitle => 'Chat completamente cifrata';

  @override
  String get walkthroughSlideFourBody =>
      'Ogni operazione ha la propria chat privata, cifrata end-to-end. Solo i due utenti coinvolti possono leggerla. In caso di disputa, puoi fornire la chiave condivisa a un amministratore per aiutare a risolvere il problema.';

  @override
  String get walkthroughSlideFiveTitle => 'Prendi un\'offerta';

  @override
  String get walkthroughSlideFiveBody =>
      'Sfoglia il book degli ordini, scegli un\'offerta adatta a te e segui il flusso dell\'operazione passo dopo passo. Potrai controllare il profilo dell\'altro utente, chattare in sicurezza e completare l\'operazione con facilità.';

  @override
  String get walkthroughSlideSixTitle => 'Non trovi quello che cerchi?';

  @override
  String get walkthroughSlideSixBody =>
      'Puoi anche creare la tua offerta e aspettare che qualcuno la accetti. Imposta l\'importo e il metodo di pagamento preferito — Mostro pensa al resto.';

  @override
  String get tabBuyBtc => 'Compra BTC';

  @override
  String get tabSellBtc => 'Vendi BTC';

  @override
  String get filterButtonLabel => 'Filtra';

  @override
  String filtersActiveCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count filtri attivi',
      one: '1 filtro attivo',
    );
    return '$_temp0';
  }

  @override
  String get noOrdersAvailable => 'Nessun ordine disponibile';

  @override
  String get justNow => 'proprio ora';

  @override
  String minutesAgo(int m) {
    return '${m}m fa';
  }

  @override
  String hoursAgo(int h) {
    return '${h}h fa';
  }

  @override
  String daysAgo(int d) {
    return '${d}g fa';
  }

  @override
  String get invoiceRejected =>
      'Il nodo ha rifiutato questa fattura. Controlla importo e scadenza e aggiungine una nuova.';

  @override
  String get invoiceCopied => 'Fattura copiata';

  @override
  String get submitButtonLabel => 'Invia';

  @override
  String get orderAlreadyTaken => 'L\'ordine è già stato preso';

  @override
  String get nodeProtocolUnsupported =>
      'Questo nodo Mostro usa una versione del protocollo che questa app non supporta. Scegli un altro nodo nelle Impostazioni o verifica se è disponibile un aggiornamento dell\'app';

  @override
  String get nodeCapabilitiesUnknown =>
      'Stiamo ancora verificando cosa supporta il nodo Mostro selezionato. Riprova tra un istante';

  @override
  String get mostroMaintenanceMode =>
      'Il nodo Mostro a cui sei connesso è in manutenzione. Riprova più tardi o connettiti a un altro nodo Mostro nelle Impostazioni';

  @override
  String get storageUnavailable =>
      'L\'app non può creare né prendere ordini finché il suo database locale non è disponibile. Riavvia l\'app e riprova';

  @override
  String get orderIdCopied => 'ID ordine copiato';

  @override
  String get comingSoonMessage => 'Prossimamente';

  @override
  String get tradeStatusActive => 'Attivo';

  @override
  String get tradeStatusCompleted => 'Completato';

  @override
  String get tradeStatusCancelled => 'Annullato';

  @override
  String get tradeStatusDisputed => 'In disputa';

  @override
  String get accountScreenTitle => 'Account';

  @override
  String get secretWordsTitle => 'Parole segrete';

  @override
  String get privacyCardTitle => 'Privacy';

  @override
  String get reputationMode => 'Modalità Reputazione';

  @override
  String get reputationModeSubtitle =>
      'Le tue operazioni contano per la tua reputazione pubblica';

  @override
  String get fullPrivacyMode => 'Modalità Privacy Totale';

  @override
  String get fullPrivacyModeSubtitle =>
      'Ogni operazione usa una nuova identità, senza reputazione';

  @override
  String get generateNewUserButton => 'Genera nuovo utente';

  @override
  String get importMostroUserButton => 'Importa utente Mostro';

  @override
  String get generateNewUserDialogTitle => 'Generare nuovo utente?';

  @override
  String get generateNewUserDialogContent =>
      'Verrà creata una nuova identità. Le tue parole segrete attuali non funzioneranno più — assicurati di averle salvate prima di continuare.';

  @override
  String get continueButtonLabel => 'Continua';

  @override
  String get importMnemonicDialogTitle => 'Importa parole segrete';

  @override
  String get importMnemonicHintText => 'Inserisci le tue 12 parole segrete';

  @override
  String get importButtonLabel => 'Importa';

  @override
  String get refreshUserDialogTitle => 'Aggiornare utente?';

  @override
  String get refreshUserDialogContent =>
      'Verranno recuperate le tue operazioni e gli ordini dall\'istanza Mostro. Usalo se pensi che i tuoi dati non siano sincronizzati o manchino degli ordini.';

  @override
  String get hideButtonLabel => 'Nascondi';

  @override
  String get showWordsButton => 'Mostra parole';

  @override
  String get settingsScreenTitle => 'Impostazioni';

  @override
  String get languageSettingTitle => 'Lingua';

  @override
  String get appearanceSettingTitle => 'Aspetto';

  @override
  String get appearanceDialogTitle => 'Aspetto';

  @override
  String get allCurrencies => 'Tutte le valute';

  @override
  String get lightningAddressSettingTitle => 'Indirizzo Lightning';

  @override
  String get nwcWalletSettingTitle => 'Portafoglio NWC';

  @override
  String get relaysSettingTitle => 'Relay';

  @override
  String get pushNotificationsSettingTitle => 'Notifiche push';

  @override
  String get logReportSettingTitle => 'Registro diagnostico';

  @override
  String get mostroNodeSettingTitle => 'Nodo Mostro';

  @override
  String get themeDark => 'Scuro';

  @override
  String get themeLight => 'Chiaro';

  @override
  String get themeSystemDefault => 'Predefinito di sistema';

  @override
  String get lightningAddressDialogTitle => 'Indirizzo Lightning';

  @override
  String get lightningAddressHintText => 'utente@dominio.com';

  @override
  String get invalidLightningAddressFormat =>
      'Deve essere nel formato utente@dominio';

  @override
  String get clearButtonLabel => 'Cancella';

  @override
  String get saveButtonLabel => 'Salva';

  @override
  String get scanQrCodeTitle => 'Scansiona codice QR';

  @override
  String get selectLanguageTitle => 'Seleziona lingua';

  @override
  String get selectCurrencyDialogTitle => 'Seleziona valuta';

  @override
  String get addRelayDialogTitle => 'Aggiungi relay';

  @override
  String get addButtonLabel => 'Aggiungi';

  @override
  String get relayHintText => 'wss://relay.example.com';

  @override
  String get relayErrorMustStartWithWss => 'Deve iniziare con wss://';

  @override
  String get relayErrorUrlTooShort => 'L\'URL è troppo corto';

  @override
  String get relayErrorDuplicate => 'Relay già presente nella lista';

  @override
  String get pasteQrCodeHeading => 'Incolla contenuto del codice QR';

  @override
  String get pasteButtonLabel => 'Incolla';

  @override
  String get clipboardEmptyError => 'Gli appunti sono vuoti';

  @override
  String get enterValueError => 'Inserisci un valore';

  @override
  String get trustedBadgeLabel => 'Affidabile';

  @override
  String get confirmButtonLabel => 'Conferma';

  @override
  String get selectMostroNode => 'Scegli un nodo';

  @override
  String get addCustomNode => 'Aggiungi il tuo nodo';

  @override
  String get nodePubkeyFieldLabel => 'Chiave pubblica';

  @override
  String get nodePubkeyFieldHint => 'Hex di 64 caratteri o npub…';

  @override
  String get nodeNameOptionalLabel => 'Nome (facoltativo)';

  @override
  String get invalidPubkeyFormat =>
      'Inserisci una chiave pubblica valida (hex di 64 caratteri o npub)';

  @override
  String get privateKeyNotAllowed =>
      'Questa è una chiave privata — non condividerla mai. Inserisci la chiave pubblica del nodo';

  @override
  String get nodeAlreadyExists => 'Questo nodo è già nella lista';

  @override
  String get nodeAddedSuccess => 'Nodo aggiunto';

  @override
  String nodeSwitchedSuccess(String nodeName) {
    return 'Ora stai usando $nodeName';
  }

  @override
  String get errorSwitchingNode => 'Cambio di nodo non riuscito';

  @override
  String get cannotRemoveActiveNode =>
      'Il nodo attivo non può essere rimosso — passa prima a un altro nodo';

  @override
  String get deleteCustomNodeTitle => 'Rimuovi nodo';

  @override
  String get deleteCustomNodeMessage =>
      'Rimuovere questo nodo personalizzato dalla tua lista?';

  @override
  String get deleteCustomNodeConfirm => 'Rimuovi';

  @override
  String get nodeRemovedSuccess => 'Nodo rimosso';

  @override
  String get nodeStorageUnavailable =>
      'Il database locale non è pronto. Riavvia l\'app e riprova';

  @override
  String nodeSelectorSubtitle(String code) {
    return 'Ordini e valute in $code, la tua valuta';
  }

  @override
  String get nodeSelectorSubtitleNoCurrency => 'Ordini aperti su ogni nodo';

  @override
  String nodeMissingCurrencyChip(String code) {
    return 'SENZA $code';
  }

  @override
  String get nodeOrdersNowLabel => 'ordini ora';

  @override
  String get nodeNoOrdersLabel => 'nessun ordine';

  @override
  String nodeOrdersInCurrency(int count, String code) {
    return '· $count in $code';
  }

  @override
  String get nodeFeeLabel => 'commissione';

  @override
  String get nodeFeeTooltip => 'Mostro divide la commissione tra le due parti.';

  @override
  String get nodePerTradeLabel => 'per operazione';

  @override
  String get nodeCustodyLightning => 'Custodia Lightning';

  @override
  String nodeCustodyCashu(String mint) {
    return 'Custodia Cashu · $mint';
  }

  @override
  String get nodeCustodyUnknown => 'Custodia —';

  @override
  String nodeBondPct(String pct) {
    return 'Cauzione $pct%';
  }

  @override
  String get nodeBondNone => 'Senza cauzione';

  @override
  String nodeStatusOnline(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ordini',
      one: '1 ordine',
    );
    return 'Online · $_temp0';
  }

  @override
  String get nodeStatusNoUsefulOrders => 'Nessun ordine nelle tue valute';

  @override
  String nodeStatusUnreachable(String ago) {
    return 'Non risponde · ultimo segnale $ago';
  }

  @override
  String get nodeStatusUnreachableNoSignal => 'Non risponde';

  @override
  String get nodeDisclaimerShort =>
      'Ogni nodo è gestito da un terzo indipendente. Mostro non risponde della sua condotta né delle tue operazioni.';

  @override
  String get nodeVerifyKeyWarning =>
      'Verifica la chiave con l\'operatore. Un nodo falso può vedere i tuoi ordini.';

  @override
  String get nodeInvalidPubkeyShort =>
      'Questa non è una chiave pubblica valida.';

  @override
  String get nodeNameFieldHint => 'Mostro locale';

  @override
  String get nodePubkeyCopied => 'Chiave copiata';

  @override
  String get nodeNotSelectableOffline => 'Questo nodo non risponde';

  @override
  String get nodeStatsLoading => 'Caricamento dati del nodo';

  @override
  String get nodeSwitchConfirmTitle => 'Cambiare nodo?';

  @override
  String nodeSwitchConfirmBody(String currentNode, String newNode) {
    return 'Hai un\'operazione in corso su $currentNode. Resta lì; il libro mostrerà ora $newNode.';
  }

  @override
  String get nodeSwitchConfirmAction => 'Cambia nodo';

  @override
  String get nodeTradesCheckFailed =>
      'Impossibile verificare le tue operazioni. Riprova.';

  @override
  String get notificationsScreenTitle => 'Notifiche';

  @override
  String get markAllAsReadMenuItem => 'Segna tutto come letto';

  @override
  String get clearAllMenuItem => 'Cancella tutto';

  @override
  String get youMustBackUpYourAccount =>
      'Devi eseguire il backup del tuo account';

  @override
  String get tapToViewAndSaveSecretWords =>
      'Tocca per visualizzare e salvare le tue parole segrete.';

  @override
  String get noNotifications => 'Nessuna notifica';

  @override
  String get markAsRead => 'Segna come letto';

  @override
  String get deleteNotificationLabel => 'Elimina';

  @override
  String get rateScreenHeader => 'VALUTA';

  @override
  String get successfulOrder => 'Ordine riuscito';

  @override
  String get closeRatingButton => 'CHIUDI';

  @override
  String get aboutScreenTitle => 'Informazioni';

  @override
  String get linkCopiedToClipboard => 'Link copiato negli appunti';

  @override
  String get pubkeyLabel => 'Chiave pubblica';

  @override
  String get relaysLabel => 'Relay';

  @override
  String get footerTagline => 'Open-source. Non custodiale. Privato.';

  @override
  String get drawerTitle => 'Mostro';

  @override
  String get drawerTagline => 'Scambio P2P';

  @override
  String get drawerStageBadge => 'Alpha';

  @override
  String drawerVersion(String version) {
    return 'Versione $version';
  }

  @override
  String get drawerAccountMenuItem => 'Account';

  @override
  String get drawerSettingsMenuItem => 'Impostazioni';

  @override
  String get drawerAboutMenuItem => 'Informazioni';

  @override
  String get navOrderBook => 'Book ordini';

  @override
  String get navMyTrades => 'Le mie operazioni';

  @override
  String get navChat => 'Chat';

  @override
  String get loadingOrders => 'Caricamento ordini…';

  @override
  String get errorLoadingOrders =>
      'Impossibile caricare gli ordini. Controlla la connessione.';

  @override
  String get retry => 'Riprova';

  @override
  String disableRelayLabel(String url) {
    return 'Disabilita relay $url';
  }

  @override
  String enableRelayLabel(String url) {
    return 'Abilita relay $url';
  }

  @override
  String get removeRelayTooltip => 'Rimuovi relay';

  @override
  String get relayAddFailed => 'Impossibile aggiungere il relay';

  @override
  String get relayRemoveFailed => 'Impossibile rimuovere il relay';

  @override
  String get backupRitualSecondFailureMessage =>
      'Di nuovo errato. Per favore controlla e salva le tue parole segrete, poi verifica dall\'inizio.';

  @override
  String get cancelTradeDialogTitle => 'Annullare lo scambio?';

  @override
  String get cancelTradeDialogContent =>
      'Annullamento cooperativo richiesto. Anche l\'altra parte deve accettare affinché lo scambio venga annullato.';

  @override
  String get cancelTradeDialogContentNotStarted =>
      'Lo scambio non è ancora iniziato, quindi viene annullato subito. Non serve che l\'altra parte accetti.';

  @override
  String get cancelTradeDialogContentMaybeStarted =>
      'Se lo scambio non è ancora iniziato, viene annullato subito. Se è già iniziato, anche l\'altra parte deve accettare.';

  @override
  String get noButtonLabel => 'No';

  @override
  String get yesButtonLabel => 'Sì';

  @override
  String get yesCancelButtonLabel => 'Sì, annulla';

  @override
  String get cancelRequestSent => 'Richiesta di annullamento inviata';

  @override
  String get cancelRequestFailed => 'Annullamento fallito. Riprovare.';

  @override
  String get tradeCardCancelRequestedByMeTitle => 'Annullamento richiesto';

  @override
  String get tradeCardCancelRequestedByMeMessage =>
      'Hai chiesto di annullare questo scambio. Resta aperto finché anche l\'altra parte non annulla. Se non risponde, puoi aprire una disputa.';

  @override
  String get tradeCardCancelRequestedByPeerTitle =>
      'L\'altra parte vuole annullare';

  @override
  String get tradeCardCancelRequestedByPeerMessage =>
      'Ha chiesto di annullare questo scambio. Accetta per concluderlo senza spostare fondi, oppure continua lo scambio.';

  @override
  String get tradeCancelRequestedByMeNotice =>
      'Hai chiesto di annullare questo scambio. Resta aperto finché anche l\'altra parte non annulla. Se non risponde, puoi aprire una disputa.';

  @override
  String get tradeCancelRequestedByPeerNotice =>
      'L\'altra parte ha chiesto di annullare questo scambio. Accetta per concluderlo senza spostare fondi, oppure continua lo scambio.';

  @override
  String get acceptCancelButton => 'Accetta annullamento';

  @override
  String get cancelTradeDialogContentAccept =>
      'L\'altra parte ha chiesto di annullare. Annullando ora lo scambio termina per entrambi e nessun fondo viene spostato.';

  @override
  String get fiatSentFailed =>
      'Impossibile contrassegnare il fiat come inviato. Riprovare.';

  @override
  String get releaseFailed => 'Rilascio fallito. Riprovare.';

  @override
  String get cancelTradeButton => 'Annulla scambio';

  @override
  String get payHoldInvoiceButton => 'Paga fattura hold';

  @override
  String get openDisputeButton => 'Apri disputa';

  @override
  String get releaseSatsButton => 'Rilascia sats';

  @override
  String get confirmReleaseSatsButton => 'Conferma e rilascia sats';

  @override
  String get shareOrderButton => 'Condividi ordine';

  @override
  String get orderPillYouAreSelling => 'STAI VENDENDO';

  @override
  String get orderPillYouAreBuying => 'STAI COMPRANDO';

  @override
  String get myOrderSellTitle => 'Il tuo ordine di vendita';

  @override
  String get myOrderBuyTitle => 'Il tuo ordine di acquisto';

  @override
  String get cancelOrderFailed => 'Annullamento fallito. Riprovare.';

  @override
  String get closeButtonLabel => 'Chiudi';

  @override
  String get copyButtonLabel => 'Copia';

  @override
  String get orderStatusWaitingForTaker => 'In attesa di un taker';

  @override
  String get orderStatusInProgress => 'In corso';

  @override
  String get orderStatusExpired => 'Scaduto';

  @override
  String get copyOrderIdTooltip => 'Copia ID ordine';

  @override
  String get orderNotFoundTitle => 'Ordine non trovato';

  @override
  String get orderNotFoundMessage => 'Questo ordine non è più disponibile.';

  @override
  String get orderCancelledSuccess => 'Ordine annullato con successo.';

  @override
  String get aboutDocumentationTitle => 'Documentazione';

  @override
  String get aboutMostroNodeTitle => 'Nodo Mostro';

  @override
  String get aboutVersionLabel => 'Versione';

  @override
  String get aboutCommitHashLabel => 'Hash del commit';

  @override
  String get aboutLicenseLabel => 'Licenza';

  @override
  String get aboutLicenseName => 'AGPLv3+';

  @override
  String get aboutGithubRepoName => 'MostroP2P/app';

  @override
  String get aboutCopiedToClipboard => 'Copiato negli appunti';

  @override
  String get aboutLicenseDialogTitle =>
      'Licenza Pubblica Generica Affero GNU v3';

  @override
  String get aboutNodeLoadingText => 'Caricamento informazioni del nodo…';

  @override
  String get aboutNodeUnavailable => 'Informazioni del nodo non disponibili';

  @override
  String get aboutNodeRetry => 'Riprova';

  @override
  String get aboutLightningNetworkSection => 'Rete Lightning';

  @override
  String get aboutFiatCurrenciesLabel => 'Valute fiat';

  @override
  String get aboutMostroVersionLabel => 'Versione Mostro';

  @override
  String get aboutMostroCommitLabel => 'Commit Mostro';

  @override
  String get aboutHoldInvoiceExpLabel => 'Scadenza hold invoice';

  @override
  String get aboutHoldInvoiceCltvLabel => 'CLTV hold invoice';

  @override
  String get aboutInvoiceExpWindowLabel => 'Finestra di scadenza fattura';

  @override
  String get aboutProofOfWorkLabel => 'Proof of Work';

  @override
  String get aboutMaxOrdersPerResponseLabel => 'Max ordini/risposta';

  @override
  String get aboutLndVersionLabel => 'Versione LND';

  @override
  String get aboutSupportedChainsLabel => 'Chain supportate';

  @override
  String get aboutSupportedNetworksLabel => 'Reti supportate';

  @override
  String get aboutSatoshisSuffix => 'Satoshi';

  @override
  String get aboutBlocksSuffix => 'blocchi';

  @override
  String get aboutFiatCurrenciesAll => 'Tutte';

  @override
  String get aboutAntiAbuseBondSection => 'Cauzione anti-abuso';

  @override
  String get aboutBondEnabledValue => 'Attiva';

  @override
  String get aboutBondDisabledValue => 'Disattivata';

  @override
  String get aboutBondUnsupportedValue => 'Non supportata';

  @override
  String get aboutBondStatusLabel => 'Stato della cauzione';

  @override
  String get aboutBondAppliesToLabel => 'Si applica a';

  @override
  String get aboutBondAppliesToTakers => 'Chi accetta l\'ordine';

  @override
  String get aboutBondAppliesToMakers => 'Chi crea l\'ordine';

  @override
  String get aboutBondAppliesToBoth => 'Entrambe le parti';

  @override
  String get aboutBondAmountLabel => 'Importo della cauzione';

  @override
  String get aboutBondBaseAmountLabel => 'Cauzione minima';

  @override
  String get aboutBondNodeShareLabel =>
      'Quota del nodo in caso di incameramento';

  @override
  String get aboutBondSlashOnTimeoutLabel =>
      'Incameramento per scadenza dell\'attesa';

  @override
  String get aboutBondClaimWindowLabel => 'Termine per richiedere il pagamento';

  @override
  String aboutBondClaimWindowValue(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count giorni',
      one: '$count giorno',
    );
    return '$_temp0';
  }

  @override
  String get openDisputeFailed => 'Impossibile aprire la disputa. Riprovare.';

  @override
  String get openDisputeTitle => 'Apri contestazione';

  @override
  String get openDisputeConfirmation =>
      'Sei sicuro di voler aprire una contestazione? Questo inoltra lo scambio a un amministratore e non può essere annullato.';

  @override
  String get disputeAlreadyOpen =>
      'Esiste già una disputa aperta per questo scambio.';

  @override
  String get tradeNotDisputable =>
      'Una disputa può essere aperta solo quando i fondi sono bloccati per questo scambio.';

  @override
  String get tradeWaitingInvoiceBuyerInstruction =>
      'Invia la tua fattura Lightning per permettere al venditore di bloccare i fondi.';

  @override
  String get tradeWaitingInvoiceSellerInstruction =>
      'In attesa che il compratore invii la propria fattura Lightning.';

  @override
  String get tradeWaitingPaymentSellerInstruction =>
      'Paga la fattura hold per bloccare i fondi e avviare lo scambio.';

  @override
  String get tradeLoadError =>
      'Si è verificato un errore durante il caricamento dello scambio.';

  @override
  String get tradeWaitingForHoldInvoice => 'In attesa della fattura hold...';

  @override
  String get shareButtonLabel => 'Condividi';

  @override
  String get shareFailed => 'Impossibile condividere la fattura';

  @override
  String get waitingForPaymentConfirmation =>
      'In attesa di conferma del pagamento...';

  @override
  String get orderNoLongerActive => 'Questo ordine non è più attivo';

  @override
  String get tradeNoLongerYours => 'Non partecipi più a questo scambio';

  @override
  String get sessionTimeoutMessage =>
      'Nessuna risposta ricevuta, verifica la tua connessione e riprova più tardi';

  @override
  String get noIdentityFoundMessage =>
      'Nessuna identità trovata — prova a riavviare l\'app.';

  @override
  String get failedToLoadSecretWordsMessage =>
      'Impossibile caricare le parole segrete. Riprova.';

  @override
  String get privacyModesInfoTitle => 'Modalità di privacy';

  @override
  String get privacyModesInfoContent =>
      'La modalità reputazione consente ad altri di vedere le tue operazioni riuscite.\n\nLa modalità privacy totale mantiene la tua attività completamente anonima — non viene costruita alcuna reputazione.';

  @override
  String get failedToGenerateIdentityMessage =>
      'Impossibile generare l\'identità. Riprova.';

  @override
  String get invalidMnemonicMessage =>
      'Parole segrete non valide. Controlla le tue parole e riprova.';

  @override
  String get enterValidMnemonicError => 'Inserisci le tue 12 parole segrete.';

  @override
  String get orderBookRefreshedMessage => 'Book ordini aggiornato';

  @override
  String get refreshFailedMessage => 'Aggiornamento non riuscito';

  @override
  String get refreshButtonLabel => 'Aggiorna';

  @override
  String get okButtonLabel => 'OK';

  @override
  String get moreInformationTooltip => 'Maggiori informazioni';

  @override
  String get backedUpBadgeLabel => 'Salvate';

  @override
  String get backupBannerTitle => 'Proteggi la tua reputazione';

  @override
  String get backupBannerSubtitle =>
      'Salva le tue 12 parole — bastano 60 secondi.';

  @override
  String get pendingWipeBannerTitle =>
      'I dati dell\'utente precedente sono ancora su questo dispositivo';

  @override
  String get pendingWipeBannerBody =>
      'L\'eliminazione dell\'identità precedente non ha potuto rimuovere i suoi scambi e le sue chat da questo dispositivo. L\'app riproverà alla prossima creazione di un nuovo utente.';

  @override
  String get failedToSaveBackupStatusMessage =>
      'Impossibile salvare lo stato del backup. Riprova.';

  @override
  String get backupRitualStep1Title => 'Passo 1 di 3 · Annota le tue parole';

  @override
  String get backupRitualStep2Title => 'Passo 2 di 3 · Verifica';

  @override
  String get backupRitualStep3Title => 'Passo 3 di 3 · Fatto';

  @override
  String get backupRitualWarningTitle => 'Annotale su carta. ';

  @override
  String get backupRitualWarningBody =>
      'Non salvarle in foto, screenshot o nel cloud — chiunque abbia queste 12 parole può rubare la tua reputazione.';

  @override
  String get wordsHiddenOnLeaveNote =>
      'Verranno nascoste quando lasci questa schermata';

  @override
  String get wroteThemDownVerifyButton => 'Le ho annotate — verifica';

  @override
  String get tapCorrectWordsTitle => 'Tocca le parole corrette';

  @override
  String get verifyInstructionsBody =>
      'Ne chiediamo 3 a caso. Se le indovini, sappiamo che sono annotate al sicuro.';

  @override
  String optionsForWordLabel(int number) {
    return 'OPZIONI PER LA PAROLA #$number';
  }

  @override
  String get wrongPickMessage =>
      'Non proprio — controlla il tuo foglio e riprova.';

  @override
  String get allWordsCorrectMessage => 'Tutte e 3 le parole corrette';

  @override
  String get reviewWordsButton => 'Vedi parole';

  @override
  String get accountBackedUpTitle => 'Il tuo account è salvato';

  @override
  String get accountBackedUpBody =>
      'La tua reputazione è al sicuro. Se dovessi perdere il telefono, ripristina il tuo account con le tue 12 parole.';

  @override
  String wordNumberLabel(int number) {
    return 'Parola #$number';
  }

  @override
  String get backupTriggerBody =>
      'La tua reputazione risiede in una chiave che possiedi solo tu. Se perdi il telefono, perdi quella reputazione — ';

  @override
  String get backupTriggerBodyHighlight => 'salvala in 60 secondi.';

  @override
  String get backupStepWriteDown => 'Annota le tue 12 parole su carta';

  @override
  String get backupStepVerifyRandom => 'Ne chiediamo 3 a caso per confermare';

  @override
  String get backupStepSecured => 'Fatto — il tuo account è protetto';

  @override
  String get backupNowButton => 'Salva ora';

  @override
  String get backupLaterButton => 'Lo farò dopo';

  @override
  String get nwcConnectionFailedMessage =>
      'Connessione non riuscita. Controlla il tuo URI NWC e riprova.';

  @override
  String get clipboardInvalidNwcUriMessage =>
      'Gli appunti non contengono un URI NWC valido.';

  @override
  String get scanQrButtonLabel => 'Scansiona QR';

  @override
  String get connectButtonLabel => 'Connetti';

  @override
  String get walletDisconnectedMessage => 'Wallet disconnesso';

  @override
  String get relayLabel => 'Relay';

  @override
  String get disconnectButtonLabel => 'Disconnetti';

  @override
  String relaysMoreSuffix(int count) {
    return '(+$count altri)';
  }

  @override
  String get chooseNotificationEventsSubtitle =>
      'Scegli quali eventi mostrano una notifica nell’app.';

  @override
  String get notifTradeUpdatesTitle => 'Aggiornamenti operazioni';

  @override
  String get notifTradeUpdatesSubtitle =>
      'Cambiamenti di stato nelle tue operazioni attive';

  @override
  String get notifNewMessagesTitle => 'Nuovi messaggi';

  @override
  String get notifNewMessagesSubtitle => 'Messaggi dalla tua controparte';

  @override
  String get notifPaymentAlertsTitle => 'Avvisi di pagamento';

  @override
  String get notifPaymentAlertsSubtitle =>
      'Conferme ed errori dei pagamenti Lightning';

  @override
  String get notifDisputeUpdatesTitle => 'Aggiornamenti dispute';

  @override
  String get notifDisputeUpdatesSubtitle =>
      'Azioni degli amministratori e risoluzioni delle dispute';

  @override
  String get searchCurrenciesHint => 'Cerca valute…';

  @override
  String get noCurrenciesFoundMessage => 'Nessuna valuta trovata';

  @override
  String get shareLogsTooltip => 'Condividi i log';

  @override
  String get noLogsToShareTooltip => 'Nessun log da condividere';

  @override
  String get noLogEntriesMessage => 'Nessuna voce di registro';

  @override
  String get failedToShareLogsMessage => 'Impossibile condividere i log';

  @override
  String get logReportShareHeading => 'Registro diagnostico di Mostro';

  @override
  String get tradeFilterAll => 'Tutti';

  @override
  String get tradeFilterPending => 'In attesa';

  @override
  String get tradeFilterWaitingInvoice => 'In attesa di fattura';

  @override
  String get tradeFilterWaitingPayment => 'In attesa di pagamento';

  @override
  String get tradeFilterActive => 'Attivo';

  @override
  String get tradeFilterFiatSent => 'Fiat inviato';

  @override
  String get tradeFilterSuccess => 'Riuscito';

  @override
  String get tradeFilterCanceled => 'Annullato';

  @override
  String get tradeFilterDispute => 'Disputa';

  @override
  String get menuTooltip => 'Menu';

  @override
  String get noTradesTitle => 'Nessuna operazione';

  @override
  String get noTradesSubtitle =>
      'Le tue operazioni attive e completate appariranno qui.';

  @override
  String get couldNotLoadTradesMessage => 'Impossibile caricare le operazioni';

  @override
  String get sellingBitcoin => 'Vendita di Bitcoin';

  @override
  String get buyingBitcoin => 'Acquisto di Bitcoin';

  @override
  String get tradeInstructionActiveBuyer =>
      'Una volta inviato il denaro, contrassegnalo qui sotto. Apri una disputa solo se il venditore smette di rispondere.';

  @override
  String get tradeInstructionFiatSentBuyer =>
      'Pagamento fiat contrassegnato come inviato. In attesa che il venditore confermi la ricezione e rilasci i tuoi sats.';

  @override
  String get tradeInstructionActiveSeller =>
      'Contatta l\'acquirente con le istruzioni di pagamento tramite la chat sopra.';

  @override
  String get tradeInstructionFiatSentSeller =>
      'L\'acquirente ha confermato di aver inviato il pagamento fiat. Una volta verificata la ricezione, rilascia i sats.';

  @override
  String get tradeInstructionDisputed =>
      'È stato assegnato un risolutore di dispute. Ti contatterà tramite l\'app.';

  @override
  String get tradeInstructionPending =>
      'Il tuo ordine è pubblicato e in attesa che una controparte lo prenda. Puoi annullarlo in qualsiasi momento.';

  @override
  String get tradeInstructionCancelled =>
      'Questa operazione è stata annullata. Non sono stati scambiati fondi.';

  @override
  String get tradeInstructionInProgress => 'Operazione in corso.';

  @override
  String get theAgreedAmount => 'l\'importo concordato';

  @override
  String get tradeHeadlinePending =>
      'In attesa che qualcuno prenda il tuo ordine';

  @override
  String get tradeHeadlineInProgress => 'Lo scambio è in preparazione';

  @override
  String get tradeHeadlineWaitingInvoiceBuyer =>
      'Condividi una fattura Lightning per ricevere i tuoi sats';

  @override
  String get tradeHeadlineWaitingInvoiceSeller =>
      'In attesa che l\'acquirente condivida una fattura';

  @override
  String get tradeHeadlineWaitingPaymentBuyer =>
      'In attesa che il venditore blocchi i sats';

  @override
  String get tradeHeadlineWaitingPaymentSeller =>
      'Paga la hold invoice per bloccare i sats';

  @override
  String tradeHeadlineActiveBuyer(String amount) {
    return 'Invia $amount al venditore';
  }

  @override
  String tradeHeadlineActiveSeller(String amount) {
    return 'In attesa che l\'acquirente invii $amount';
  }

  @override
  String get tradeHeadlineFiatSentBuyer =>
      'In attesa che il venditore rilasci i tuoi sats';

  @override
  String tradeHeadlineFiatSentSeller(String amount) {
    return 'Conferma di aver ricevuto $amount';
  }

  @override
  String get tradeHeadlineDisputed => 'Disputa in corso';

  @override
  String get tradeHeadlineCancelled => 'Ordine annullato';

  @override
  String get tradeHeadlineLoading => 'Caricamento operazione…';

  @override
  String get tradeTimerPendingConsequence =>
      'Se scade, l\'ordine viene rimosso dal book. Non influirà sulla tua reputazione.';

  @override
  String get tradeTimerWaitingInvoiceConsequence =>
      'Se scade, l\'operazione viene annullata e l\'ordine torna nel book.';

  @override
  String get tradeStepOrderTaken => 'Ordine preso';

  @override
  String get tradeStepInvoiceBuyer => 'Il venditore blocca i sats';

  @override
  String get tradeStepInvoiceSeller => 'Blocchi i sats';

  @override
  String get tradeStepFiatBuyer => 'Invii il pagamento fiat';

  @override
  String get tradeStepFiatSeller => 'L\'acquirente invia il pagamento fiat';

  @override
  String get tradeStepReleaseBuyer => 'Il venditore rilascia i tuoi sats';

  @override
  String get tradeStepReleaseSeller => 'Confermi e rilasci i sats';

  @override
  String get tradeStepRate => 'Valutate l\'operazione';

  @override
  String tradeCreatedAtLabel(String date) {
    return 'creata $date';
  }

  @override
  String stepIndicator(int current, int total) {
    return 'PASSO $current DI $total';
  }

  @override
  String get addLightningInvoiceButton => 'Aggiungi fattura Lightning';

  @override
  String get viewDisputeButton => 'Vedi disputa';

  @override
  String get yourTradeTimelineTitle => 'LA TUA OPERAZIONE';

  @override
  String get messageSendFailed => 'Impossibile inviare il messaggio. Riprova.';

  @override
  String get invalidTradeId => 'ID operazione non valido';

  @override
  String get selectForDetailsHint => 'Seleziona ℹ o 👤\nper i dettagli';

  @override
  String noMessagesYet(String handle) {
    return 'Ancora nessun messaggio.\nSaluta $handle!';
  }

  @override
  String get exchangeInfoTooltip => 'Info sullo scambio';

  @override
  String get userInfoTooltip => 'Info utente';

  @override
  String chattingWith(String handle) {
    return 'Stai chattando con $handle';
  }

  @override
  String get unknownPeerHandle => 'Sconosciuto';

  @override
  String get messagesTab => 'Messaggi';

  @override
  String get disputesTab => 'Dispute';

  @override
  String get tradeInformationTitle => 'Informazioni operazione';

  @override
  String get orderIdLabel => 'ID ordine';

  @override
  String get fiatAmountLabel => 'Importo fiat';

  @override
  String get satsAmountLabel => 'Importo in sats';

  @override
  String get statusLabel => 'Stato';

  @override
  String get paymentMethodLabel => 'Metodo di pagamento';

  @override
  String get createdLabel => 'Creata';

  @override
  String get tradeDetailsPlaceholder =>
      'Dettagli disponibili quando il provider di operazioni sarà pronto (Fase 10+)';

  @override
  String get userInformationTitle => 'Informazioni utente';

  @override
  String get peerPublicKeyLabel => 'Chiave pubblica del peer';

  @override
  String get yourSharedKeyLabel => 'La tua chiave condivisa';

  @override
  String get sharedKeyPlaceholder =>
      'Disponibile dopo l\'integrazione del bridge (Fase 10+)';

  @override
  String get sharedKeySafetyNote =>
      'Conserva la tua chiave condivisa al sicuro — è necessaria per la risoluzione delle dispute';

  @override
  String get attachmentLabel => '[Allegato]';

  @override
  String get downloadTooltip => 'Scarica';

  @override
  String get fileDownloadPlaceholder =>
      'Download dei file disponibile nella Fase 10+';

  @override
  String get fileTypeVideo => 'Video';

  @override
  String get fileTypeImage => 'Immagine';

  @override
  String get fileTypeArchive => 'Archivio';

  @override
  String get fileTypeFile => 'File';

  @override
  String get tapToDownload => 'Tocca per scaricare';

  @override
  String get imageDownloadPlaceholder =>
      'Download delle immagini disponibile nella Fase 10+';

  @override
  String buyingSatsAmount(String sats) {
    return 'Acquisto di $sats sats';
  }

  @override
  String sellingSatsAmount(String sats) {
    return 'Vendita di $sats sats';
  }

  @override
  String get viewOrderLink => 'Vedi ordine';

  @override
  String timeLeftLabel(String time) {
    return '$time rimasti';
  }

  @override
  String get invoiceNoLongerExpected =>
      'Questo ordine non attende più una fattura. Aggiornamento dello stato…';

  @override
  String get invoiceSubmitInFlight =>
      'Una fattura per questo ordine è già in fase di invio. Attendi la risposta.';

  @override
  String get waitingForTradeAmount =>
      'In attesa dell\'importo dell\'operazione — riprova tra poco.';

  @override
  String get fetchingTradeAmount => 'Recupero dell\'importo dell\'operazione…';

  @override
  String get enterInvoiceManually => 'Inserisci la fattura manualmente';

  @override
  String get submitButton => 'Invia';

  @override
  String get buyerReputation => 'Reputazione dell\'acquirente';

  @override
  String get sellerReputation => 'Reputazione del venditore';

  @override
  String get ratingStatLabel => 'valutazione';

  @override
  String get tradesStatLabel => 'operazioni';

  @override
  String get daysActiveStatLabel => 'giorni attivo';

  @override
  String timeRemainingLabel(String time) {
    return 'Tempo rimanente: $time';
  }

  @override
  String orderAmountOutOfRange(int min, int max) {
    return 'L\'importo deve essere compreso tra $min e $max sats per questo nodo Mostro';
  }

  @override
  String orderAmountOutOfRangeFiat(int min, int max, String currency) {
    return 'L\'importo deve essere compreso tra $min e $max $currency per questo nodo Mostro';
  }

  @override
  String get priceTypeMarket => 'Mercato';

  @override
  String get priceTypeFixed => 'Fisso';

  @override
  String get priceTypeInfoTooltip => 'Info sul tipo di prezzo';

  @override
  String get premiumSectionLabel => 'Premio';

  @override
  String get fixedPriceRangeNotAvailable =>
      'Il prezzo fisso non è disponibile per gli ordini a intervallo. Disattiva l\'intervallo per usare un prezzo fisso.';

  @override
  String get priceTypesDialogTitle => 'Tipi di prezzo';

  @override
  String get priceTypesDialogContent =>
      'Prezzo di mercato: il prezzo del tuo ordine segue il tasso di mercato con una percentuale di premio/sconto applicata.\n\nPrezzo fisso: imposti un prezzo esatto in satoshi.';

  @override
  String get newOrderTitle => 'Nuovo ordine';

  @override
  String get amountSectionSell => 'Quanto vendi';

  @override
  String get amountSectionBuy => 'Quanto compri';

  @override
  String get amountModeSingle => 'Singolo';

  @override
  String get amountModeRange => 'Intervallo';

  @override
  String get amountMinLabel => 'Minimo';

  @override
  String get amountMaxLabel => 'Massimo';

  @override
  String paymentMethodsChosenCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count scelti',
      one: '1 scelto',
      zero: 'nessuno scelto',
    );
    return '$_temp0';
  }

  @override
  String get paymentMethodAdd => 'Aggiungi';

  @override
  String get paymentMethodSearchHint => 'Cerca metodi';

  @override
  String get customPaymentMethodLabel => 'Metodo di pagamento personalizzato';

  @override
  String get priceSectionTitle => 'Prezzo';

  @override
  String premiumSellAbove(String premium) {
    return 'Vendi $premium% sopra il prezzo di mercato';
  }

  @override
  String premiumSellBelow(String premium) {
    return 'Vendi $premium% sotto il mercato';
  }

  @override
  String premiumBuyBelow(String premium) {
    return 'Paghi $premium% meno del mercato';
  }

  @override
  String premiumBuyAbove(String premium) {
    return 'Paghi $premium% in più';
  }

  @override
  String get premiumExactMarket => 'Prezzo di mercato esatto';

  @override
  String get fixedPriceNote =>
      'A prezzo fisso l\'ordine non segue il mercato: l\'importo in sats resta esattamente come lo scrivi.';

  @override
  String get previewHintNoAmount =>
      'Scrivi un importo e vedrai qui come risulta l\'ordine.';

  @override
  String previewSellMarket(String amount, String premium, String active) {
    return 'Vendi BTC per $amount a prezzo di mercato $premium$active';
  }

  @override
  String previewSellMarketExact(String amount, String active) {
    return 'Vendi BTC per $amount a prezzo di mercato$active';
  }

  @override
  String previewBuyMarket(String amount, String premium, String active) {
    return 'Compri BTC per $amount a prezzo di mercato $premium$active';
  }

  @override
  String previewBuyMarketExact(String amount, String active) {
    return 'Compri BTC per $amount a prezzo di mercato$active';
  }

  @override
  String previewSellFixed(String sats, String amount, String active) {
    return 'Vendi $sats per $amount a prezzo fisso$active';
  }

  @override
  String previewBuyFixed(String sats, String amount, String active) {
    return 'Compri $sats per $amount a prezzo fisso$active';
  }

  @override
  String previewActiveSuffix(String hours) {
    return ' · attivo $hours';
  }

  @override
  String get publishOrder => 'Pubblica ordine';

  @override
  String removePaymentMethod(String method) {
    return 'Rimuovi $method';
  }

  @override
  String get satsUnitLabel => 'sats';

  @override
  String satsAmount(String amount) {
    return '$amount sats';
  }

  @override
  String durationHours(int hours) {
    return '$hours h';
  }

  @override
  String get paymentMethodsLabel => 'Metodi di pagamento';

  @override
  String get customPaymentMethodHint => 'Metodo di pagamento personalizzato...';

  @override
  String amountRangeError(String min, String max) {
    return 'L\'importo deve essere compreso tra $min e $max';
  }

  @override
  String get enterAmountTitle => 'Inserisci l\'importo';

  @override
  String minMaxRangeLabel(String min, String max, String currency) {
    return 'Min: $min – Max: $max $currency';
  }

  @override
  String get ratingFailed => 'Valutazione non riuscita. Riprova.';

  @override
  String get submitUppercaseButton => 'INVIA';

  @override
  String selectStarTooltip(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Seleziona $count stelle',
      one: 'Seleziona 1 stella',
    );
    return '$_temp0';
  }

  @override
  String get disputeDetailsTitle => 'Dettagli della disputa';

  @override
  String get disputeIdLabel => 'ID disputa';

  @override
  String disputeReasonLabel(String reason) {
    return 'Motivo: $reason';
  }

  @override
  String get adminLabel => 'Amministratore';

  @override
  String get disputeScreenTitle => 'Disputa';

  @override
  String get filtersDialogTitle => 'Filtri';

  @override
  String get resetButton => 'Reimposta';

  @override
  String get currencyLabel => 'Valuta';

  @override
  String get ratingLabel => 'Valutazione';

  @override
  String get applyButton => 'Applica';

  @override
  String get successLabel => 'Successo';

  @override
  String get copyButton => 'Copia';

  @override
  String get shareButton => 'Condividi';

  @override
  String sendSatsToAddress(String sats) {
    return 'Invia $sats sats a:';
  }

  @override
  String get changeButton => 'Modifica';

  @override
  String get unableToOpenNotification =>
      'Impossibile aprire i dettagli della notifica.';

  @override
  String get reasonBestPremium => 'Miglior premio';

  @override
  String get reasonMostReputable => 'Più affidabile';

  @override
  String get marketPriceCaption => 'Prezzo di mercato';

  @override
  String reputationTradesLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'operazioni',
      one: 'operazione',
    );
    return '$_temp0';
  }

  @override
  String reputationDaysLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'giorni',
      one: 'giorno',
    );
    return '$_temp0';
  }

  @override
  String get sortNewest => 'Più recenti';

  @override
  String ordersCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ordini',
      one: '1 ordine',
    );
    return '$_temp0';
  }

  @override
  String get sortBestPremium => 'Miglior premio';

  @override
  String get sortBestReputation => 'Miglior reputazione';

  @override
  String get sortSheetTitle => 'Ordina per';

  @override
  String get orderCardPremiumCaption => 'premio';

  @override
  String orderFixedAmount(String sats) {
    return 'Importo fisso · per $sats';
  }

  @override
  String get reputationNew => 'Nuovo';

  @override
  String get reputationNoTrades => 'nessuna operazione';

  @override
  String get bottomNavBook => 'Book';

  @override
  String get bottomNavTrades => 'Operazioni';

  @override
  String get fabDismissHint => 'Tocca fuori per chiudere';

  @override
  String get addOrderFabLabel => 'Crea ordine';

  @override
  String get ordersEmptyHint =>
      'I nuovi ordini appaiono qui appena vengono pubblicati.';

  @override
  String get ordersEmptyFilteredHint =>
      'Nessun ordine corrisponde ai tuoi filtri.';

  @override
  String get clearFiltersButton => 'Rimuovi filtri';

  @override
  String get hideEarlierEvents => 'Nascondi eventi precedenti';

  @override
  String viewEarlierEvents(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Vedi $count eventi precedenti',
      one: 'Vedi 1 evento precedente',
    );
    return '$_temp0';
  }

  @override
  String get goToTrade => 'Vai all\'operazione';

  @override
  String get disputeWord => 'Disputa';

  @override
  String get tradeWord => 'Operazione';

  @override
  String get notifFilterAll => 'Tutte';

  @override
  String get notifFilterDisputes => 'Dispute';

  @override
  String notifFilterDisputesCount(int count) {
    return 'Dispute · $count';
  }

  @override
  String get notifFilterSystem => 'Sistema';

  @override
  String notifFilterSystemCount(int count) {
    return 'Sistema · $count';
  }

  @override
  String get payingStatus => 'Pagamento in corso...';

  @override
  String get payWithWalletButton => 'Paga con il wallet';

  @override
  String get generatingInvoiceNwc => 'Generazione fattura tramite NWC...';

  @override
  String get unableToGenerateInvoice =>
      'Impossibile generare la fattura automaticamente';

  @override
  String get avatarIconLabel => 'Icona avatar';

  @override
  String get disputeDescResolvedBuyerFavour =>
      'Disputa risolta a favore dell\'acquirente';

  @override
  String get disputeDescResolvedYourFavour => 'Disputa risolta a tuo favore';

  @override
  String get disputeDescResolvedSellerFavour =>
      'Disputa risolta a favore del venditore';

  @override
  String get disputeDescCooperativeCancel =>
      'Ordine annullato cooperativamente';

  @override
  String get disputeDescResolved => 'Disputa risolta';

  @override
  String get disputeDescYouOpened => 'Hai aperto questa disputa';

  @override
  String get disputeDescCounterpartOpened =>
      'La controparte ha aperto questa disputa';

  @override
  String get notificationsBellNoUnread =>
      'Notifiche, nessuna notifica non letta';

  @override
  String get notificationsBellBackupActive =>
      'Notifiche, promemoria di backup attivo';

  @override
  String notificationsBellUnread(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Notifiche, $count non lette',
      one: 'Notifiche, 1 non letta',
    );
    return '$_temp0';
  }

  @override
  String drawerBadgeNewCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count nuovi',
      one: '1 nuovo',
    );
    return '$_temp0';
  }

  @override
  String get bondSlashedViewPolicy => 'Vedi la politica';

  @override
  String get bondSlashedViewTrade => 'Vedi lo scambio';

  @override
  String bondSlashedTradeNoticeDispute(String sats) {
    return 'Il nodo ha confiscato il tuo deposito di $sats sats in questa disputa.';
  }

  @override
  String bondSlashedTradeNoticeTimeout(String sats) {
    return 'Il nodo ha confiscato il tuo deposito di $sats sats perché un passaggio è scaduto.';
  }

  @override
  String get bondSlashedTitle => 'Cauzione confiscata';

  @override
  String bondSlashedMessageTimeout(String amount, String orderId) {
    return 'La tua cauzione anti-abuso di $amount sats per l\'ordine $orderId è stata confiscata dopo lo scadere del tempo di attesa. Lo stato del tuo ordine è invariato.';
  }

  @override
  String bondSlashedMessageDispute(String amount, String orderId) {
    return 'La tua cauzione anti-abuso di $amount sats per l\'ordine $orderId è stata confiscata dopo la risoluzione di una controversia. Lo stato del tuo ordine è invariato.';
  }

  @override
  String get bondSlashedCauseTimeout => 'Tempo di attesa scaduto';

  @override
  String get bondSlashedCauseDispute => 'Risoluzione della controversia';

  @override
  String get bondSlashedDetailOrder => 'Ordine';

  @override
  String get bondSlashedDetailAmount => 'Importo della cauzione';

  @override
  String get bondSlashedDetailCause => 'Motivo';

  @override
  String get bondSlashedDetailFiat => 'Fiat';

  @override
  String get bondSlashedDetailPaymentMethod => 'Metodo di pagamento';

  @override
  String aboutDaysValue(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count giorni',
      one: '$count giorno',
    );
    return '$_temp0';
  }

  @override
  String get aboutCashuEscrowSection => 'Deposito Cashu';

  @override
  String get aboutCashuMintUrlLabel => 'Mint';

  @override
  String get aboutCashuMintNotAdvertised => 'Non dichiarata';

  @override
  String get aboutCashuLocktimeLabel => 'Blocco del deposito';

  @override
  String get aboutCashuSettlementMarginLabel => 'Margine di liquidazione';

  @override
  String get escrowModeLightning => 'Lightning';

  @override
  String get escrowModeCashu => 'Cashu';

  @override
  String get escrowModeUnknown => 'Non dichiarato';

  @override
  String get settingsEscrowOverrideTitle => 'Backend di deposito (sviluppo)';

  @override
  String get settingsEscrowOverrideSubtitle =>
      'Prova Cashu con un nodo che non lo dichiara ancora. Solo nelle build di debug.';

  @override
  String get settingsForceCashuLabel => 'Forza il deposito Cashu';

  @override
  String get settingsCashuMintOverrideLabel => 'URL mint alternativo';

  @override
  String get settingsCashuMintOverrideApply => 'Applica';

  @override
  String get settingsCashuMintOverrideInvalid =>
      'Non è un URL di mint valido. Usa http o https con un host.';

  @override
  String settingsEscrowEffectiveMode(String mode) {
    return 'Backend effettivo: $mode';
  }

  @override
  String settingsEscrowEffectiveMint(String mint) {
    return 'Mint effettiva: $mint';
  }

  @override
  String get settingsEscrowCashuUnavailable =>
      'Cashu non può funzionare senza una mint: impostane una qui sotto.';

  @override
  String get tradeStatusPayoutPending => 'Pagamento in attesa';

  @override
  String get tradeHeadlinePayoutPending =>
      'In attesa del pagamento all’acquirente';

  @override
  String get tradeInstructionPayoutPending =>
      'Il venditore ha rilasciato i fondi in deposito. In attesa del completamento del pagamento Lightning all’acquirente.';

  @override
  String get tradeScreenTitle => 'La tua operazione';

  @override
  String get tradeChipWaiting => 'IN ATTESA';

  @override
  String get tradeChipActive => 'ATTIVA';

  @override
  String get tradeChipYourTurn => 'TOCCA A TE';

  @override
  String get tradeChipDispute => 'DISPUTA';

  @override
  String get tradeChatLockedNote =>
      'Ancora nessuna chat: finché l\'operazione non è attiva, nessuna delle due parti sa chi è l\'altra.';

  @override
  String get tradeChatEncrypted => 'Chat cifrata end-to-end';

  @override
  String get tradeBodyWaitingPaymentBuyer =>
      'Sta pagando la hold invoice. Quando i sats saranno bloccati, toccherà a te pagare il fiat.';

  @override
  String tradeBodyActiveSeller(String method) {
    return 'Passa i tuoi dati $method nella chat qui sopra.';
  }

  @override
  String tradeBodyActiveBuyer(String method) {
    return 'Tramite $method, con i dati ricevuti in chat. Quando hai inviato, segnalalo qui sotto.';
  }

  @override
  String tradeBodyFiatSentSeller(String method) {
    return 'L\'acquirente ha segnato il pagamento come inviato. Controlla il tuo conto $method prima di rilasciare.';
  }

  @override
  String get tradeReleaseIrreversible =>
      'Il rilascio dei sats non si può annullare.';

  @override
  String get tradeTimerYouHave => 'Ti restano';

  @override
  String get tradeTimerTheyHave => 'Gli restano';

  @override
  String get tradeTimerOrderHas => 'Tempo rimasto';

  @override
  String get tradeTimerNoteCoordinate =>
      'Se vi serve più tempo, accordatevi in chat prima che scada.';

  @override
  String get tradeRoleBuyer => 'Acquirente';

  @override
  String get tradeRoleSeller => 'Venditore';

  @override
  String reputationTradesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count operazioni',
      one: '1 operazione',
    );
    return '$_temp0';
  }

  @override
  String reputationDaysOnMostro(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count giorni su Mostro',
      one: '1 giorno su Mostro',
    );
    return '$_temp0';
  }

  @override
  String get tradeFiatSentAction => 'Ho inviato il pagamento';

  @override
  String get tradeCloseAction => 'Chiudi';

  @override
  String get tradeSendRatingAction => 'Invia valutazione';

  @override
  String get tradeCompletedTitle => 'Operazione completata';

  @override
  String tradeRatedCounterpart(String alias, String score) {
    return 'Hai valutato $alias con $score';
  }

  @override
  String get tradeIdLabel => 'ID';

  @override
  String tradeCreatedTodayLabel(String time) {
    return 'creata oggi alle $time';
  }

  @override
  String get releaseSheetTitle => 'Rilasciare i sats?';

  @override
  String get releaseSheetBody =>
      'Non si può annullare. Rilascia solo se il denaro è già sul tuo conto.';

  @override
  String get releaseSheetConfirm => 'Sì, rilascia';

  @override
  String get releaseSheetBack => 'Indietro';

  @override
  String get orderSideChipSell => 'Vendi BTC';

  @override
  String get orderSideChipBuy => 'Compri BTC';

  @override
  String orderDetailMarketPremium(String premium) {
    return 'Prezzo di mercato · $premium di premio';
  }

  @override
  String myOrderWaitingNote(String ago) {
    return 'Pubblicata $ago. Ti avvisiamo appena qualcuno la prende: puoi chiudere questa schermata.';
  }

  @override
  String get orderStatusTakenWaitingInvoice =>
      'Presa · in attesa della fattura';

  @override
  String get orderStatusTakenWaitingPayment =>
      'Presa · in attesa del pagamento';

  @override
  String get orderDetailCreatedLabel => 'Creata';

  @override
  String get orderDetailIdLabel => 'ID';

  @override
  String paymentMethodsMore(String first, int count) {
    return '$first +$count';
  }

  @override
  String get paymentMethodsSheetTitle => 'Metodi di pagamento';

  @override
  String get cancelOrderSheetTitle => 'Annullare l\'ordine?';

  @override
  String get cancelOrderSheetBody =>
      'Viene rimosso dal libro degli ordini e non si può annullare.';

  @override
  String get goBackButtonLabel => 'Indietro';

  @override
  String get takeOrderYouPay => 'Paghi';

  @override
  String get takeOrderYouReceive => 'Ricevi';

  @override
  String get takeOrderYouSend => 'Invii';

  @override
  String takeOrderSatsFrom(String sats) {
    return 'da $sats';
  }

  @override
  String takeOrderMarketFooter(String premium) {
    return 'Prezzo di mercato · $premium di premio. La cifra finale si fissa quando la prendi.';
  }

  @override
  String takeOrderFixedFooterSeller(String sats) {
    return 'Importo fisso · il venditore chiede $sats';
  }

  @override
  String takeOrderFixedFooterBuyer(String sats) {
    return 'Importo fisso · l\'acquirente offre $sats';
  }

  @override
  String get counterpartySeller => 'Venditore';

  @override
  String get counterpartyBuyer => 'Acquirente';

  @override
  String counterpartyTrades(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count scambi',
      one: '$count scambio',
    );
    return '$_temp0';
  }

  @override
  String counterpartyDaysOnMostro(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count giorni su Mostro',
      one: '$count giorno su Mostro',
    );
    return '$_temp0';
  }

  @override
  String get takeOrderPayWithLabel => 'Paghi con';

  @override
  String get takeOrderPaidWithLabel => 'Ti pagano con';

  @override
  String get takeOrderPublishedLabel => 'Pubblicata';

  @override
  String get takeOrderNoteBuyer =>
      'Quando la prendi, il venditore blocca i sats in Mostro. Paghi solo quando sono bloccati.';

  @override
  String get takeOrderNoteSeller =>
      'Quando la prendi, blocchi i sats in Mostro. L\'acquirente paga dopo.';

  @override
  String get takeOrderButton => 'Prendi l\'ordine';

  @override
  String get takeOrderTaking => 'Presa in corso…';

  @override
  String get takeOrderUnavailable => 'Non più disponibile';

  @override
  String get takeOrderClosed => 'Chiusa';

  @override
  String get easterEggWhitepaper =>
      '31 ottobre 2008: nove pagine, il permesso di nessuno. Buon Halloween.';

  @override
  String get easterEggGenesis =>
      'The Times 03/Jan/2009 Chancellor on brink of second bailout for banks';

  @override
  String get easterEggPizzaDay =>
      '22 maggio 2010: 10.000 BTC per due pizze. Speriamo fossero buone.';

  @override
  String get settingsGroupApp => 'Applicazione';

  @override
  String get settingsGroupPayments => 'Pagamenti';

  @override
  String get settingsGroupNetwork => 'Rete';

  @override
  String get settingsGroupHelp => 'Aiuto';

  @override
  String get fiatCurrencySettingTitle => 'Valuta fiat';

  @override
  String notificationsEnabledOfTotal(int count, int total) {
    return '$count su $total';
  }

  @override
  String get notificationsAllOff => 'Disattivate';

  @override
  String get lightningAddressUnset => 'Non impostato';

  @override
  String get nwcWalletNotConnected => 'Non connesso';

  @override
  String relaysConnectedOfTotal(int connected, int total) {
    return '$connected su $total connessi';
  }

  @override
  String get relaysSummaryHealthy => 'Ricevi ordini e messaggi normalmente';

  @override
  String get relaysSummaryAtRisk => 'Potresti non vedere più i nuovi ordini';

  @override
  String get relayStatusConnected => 'Connesso';

  @override
  String get relayStatusOffline => 'Nessuna connessione';

  @override
  String get addRelayButtonLabel => 'Aggiungi relay';

  @override
  String get relaysFootnote =>
      'I relay trasportano i tuoi ordini e messaggi. Con meno di due connessi potresti non vedere più i nuovi ordini.';

  @override
  String get lastRelayBlockedMessage =>
      'Mantieni almeno un relay attivo: senza relay non puoi vedere né pubblicare ordini.';

  @override
  String get nwcExplainerTitle => 'Connetti il tuo wallet';

  @override
  String get nwcExplainerSubtitle => 'Con Nostr Wallet Connect';

  @override
  String get nwcExplainerBody =>
      'Mostro incasserà e pagherà le fatture delle tue operazioni da questo wallet, senza che tu debba copiare fatture a mano.';

  @override
  String get nwcUriFieldLabel => 'URI di connessione';

  @override
  String get nwcUriPlaceholder => 'nostr+walletconnect://…';

  @override
  String get nwcStorageFootnote =>
      'L’URI è salvata solo su questo dispositivo e non viene mai pubblicata su Nostr.';

  @override
  String get walletConnectedMessage => 'Wallet connesso';

  @override
  String get nwcConnectedStatus => 'Connesso';

  @override
  String nwcBalanceSats(String sats) {
    return '$sats sats';
  }

  @override
  String get notificationsSystemDenied =>
      'Le notifiche sono disattivate nelle impostazioni di sistema.';

  @override
  String get openSystemSettingsAction => 'Apri impostazioni';

  @override
  String get notificationsPrivacyFootnote =>
      'Le notifiche non includono importi né controparti. Un push passa dai server di Google o di Apple e dice solo che c’è qualcosa da vedere.';

  @override
  String get pushMasterToggleTitle => 'Notifiche push';

  @override
  String get pushMasterToggleSubtitle =>
      'Risveglia l’app quando arriva un aggiornamento di scambio o un messaggio. La notifica in sé non contiene nulla.';

  @override
  String get pushStatusOff => 'Disattivate: nulla è registrato sul server push';

  @override
  String pushStatusCleanupPending(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Disattivate — $count registrazioni push ancora da rimuovere',
      one: 'Disattivate — 1 registrazione push ancora da rimuovere',
    );
    return '$_temp0';
  }

  @override
  String get pushStatusNoToken =>
      'In attesa del token push di questo dispositivo';

  @override
  String get pushStatusIdle => 'Attivate: nessuno scambio aperto da registrare';

  @override
  String pushStatusRegistered(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Registrato per $count scambi',
      one: 'Registrato per 1 scambio',
    );
    return '$_temp0';
  }

  @override
  String pushStatusLastRegistered(String ago) {
    return 'ultima registrazione $ago';
  }

  @override
  String get pushStatusUnreachable =>
      'Server push irraggiungibile: nuovo tentativo in corso';

  @override
  String get pushStatusNodeRefused =>
      'Questo nodo Mostro non è accettato dal server push';

  @override
  String get pushStatusRateLimited =>
      'Limite di richieste push raggiunto: nuovo tentativo a breve';

  @override
  String get pushUnsupportedPlatform =>
      'Le notifiche push non sono disponibili su questa piattaforma';

  @override
  String get pushToggleSaveFailed => 'Impossibile modificare le notifiche push';

  @override
  String get pushNewMessageBody => 'Hai un nuovo messaggio';

  @override
  String get notificationPrefSaveFailed => 'Impossibile salvare la preferenza';

  @override
  String get logsScreenTitle => 'Registri';

  @override
  String get logFilterAll => 'Tutti';

  @override
  String get logFilterRelays => 'Relay';

  @override
  String get logFilterOrders => 'Ordini';

  @override
  String get logFilterPayments => 'Pagamenti';

  @override
  String get verboseLoggingTitle => 'Registro dettagliato';

  @override
  String get verboseLoggingSubtitle => 'Più dettaglio, più consumo';

  @override
  String get newLogsChipLabel => 'Nuovi registri';

  @override
  String get noLogsForFilter => 'Nessuna voce per questo filtro';

  @override
  String get aboutAppSection => 'Applicazione';

  @override
  String get aboutSourceCodeLabel => 'Codice sorgente';

  @override
  String get aboutUserGuideLabel => 'Guida utente';

  @override
  String get aboutTechnicalDocsLabel => 'Documentazione tecnica';

  @override
  String get aboutLanguageSpanish => 'Spagnolo';

  @override
  String get aboutLanguageEnglish => 'Inglese';

  @override
  String get aboutConnectedNodeTitle => 'Nodo connesso';

  @override
  String get aboutMinOrderCell => 'Ordine minimo';

  @override
  String get aboutMaxOrderCell => 'Ordine massimo';

  @override
  String get aboutFeeCell => 'Commissione';

  @override
  String aboutFeeValue(String value) {
    return '$value%';
  }

  @override
  String get aboutLimitsFootnote => 'Limiti in satoshi per ordine';

  @override
  String get aboutNodeTechnicalDataRow => 'Dati tecnici del nodo';

  @override
  String aboutFieldCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count campi',
      one: '$count campo',
    );
    return '$_temp0';
  }

  @override
  String get aboutTechnicalDataTitle => 'Dati tecnici';

  @override
  String get aboutPublicKeyLabel => 'Chiave pubblica';

  @override
  String get aboutOrderExpiryLabel => 'Scadenza ordine';

  @override
  String get aboutWaitingTimeoutLabel => 'Timeout di attesa';

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
  String get aboutNodePublicKeyLabel => 'Chiave pubblica del nodo';

  @override
  String get aboutNodeUriLabel => 'URI del nodo';

  @override
  String get aboutCommitLabel => 'Commit';

  @override
  String get aboutChainNetworkLabel => 'Catena e rete';

  @override
  String get aboutTechnicalFootnote =>
      'Questi dati identificano il nodo con cui fai trading. Utili per l\'assistenza o per verificarlo prima di inviare fondi.';

  @override
  String get aboutCopyAllData => 'Copia tutti i dati';

  @override
  String get tradesGroupNeedsAction => 'Richiedono un\'azione';

  @override
  String get tradesGroupInProgress => 'In corso';

  @override
  String get tradesGroupClosed => 'Chiuse';

  @override
  String get tradesDirectionSell => 'Vendi';

  @override
  String get tradesDirectionBondClaim => 'Richiesta sul deposito';

  @override
  String get tradesDirectionBuy => 'Compri';

  @override
  String tradesCounterpartyTo(String handle) {
    return 'a $handle';
  }

  @override
  String tradesCounterpartyFrom(String handle) {
    return 'da $handle';
  }

  @override
  String get tradeListChipYourTurn => 'Tocca a te';

  @override
  String get tradeListChipPublished => 'Pubblicata';

  @override
  String get tradeListChipInProgress => 'In corso';

  @override
  String get tradeListChipWaitingInvoice => 'In attesa di fattura';

  @override
  String get tradeListChipWaitingPayment => 'In attesa di pagamento';

  @override
  String get tradeListChipWaitingSats => 'In attesa dei sats';

  @override
  String get tradeListChipDispute => 'In disputa';

  @override
  String get tradeListChipCompleted => 'Completata';

  @override
  String get tradeListChipCancelled => 'Annullata';

  @override
  String get tradeListChipExpired => 'Scaduta';

  @override
  String get tradeVerbAddInvoice => 'Aggiungi fattura';

  @override
  String get tradeVerbPayBond => 'Paga il deposito';

  @override
  String get tradeHeadlineWaitingBond =>
      'Blocca il tuo deposito per continuare';

  @override
  String get tradeInstructionWaitingBond =>
      'Il nodo trattiene questa presa finché il deposito rimborsabile non viene pagato. Nel frattempo l\'ordine resta aperto ad altri.';

  @override
  String get takeOrderBondNotice =>
      'Questo nodo chiede a chi prende l\'ordine di bloccare prima un deposito rimborsabile; torna quando lo scambio finisce onestamente.';

  @override
  String takeOrderBondNoticeEstimate(String sats) {
    return 'Questo nodo chiede a chi prende l\'ordine di bloccare prima un deposito rimborsabile di ≈ $sats sats; torna quando lo scambio finisce onestamente.';
  }

  @override
  String get tradeVerbPayInvoice => 'Paga fattura';

  @override
  String get tradeVerbSendPayment => 'Invia pagamento';

  @override
  String get tradeVerbReleaseSats => 'Rilascia sats';

  @override
  String get tradeVerbRate => 'Valuta';

  @override
  String get tradeListFilterAll => 'Tutte';

  @override
  String get tradeListFilterActive => 'Attive';

  @override
  String get tradeListFilterCompleted => 'Completate';

  @override
  String get tradeListFilterCancelled => 'Annullate';

  @override
  String get tradeListFilterTitle => 'Mostra scambi';

  @override
  String get relativeTimeNow => 'ora';

  @override
  String relativeTimeMinutes(int count) {
    return '$count min fa';
  }

  @override
  String relativeTimeHours(int count) {
    return '$count h fa';
  }

  @override
  String get relativeTimeYesterday => 'ieri';

  @override
  String satsFigureEstimate(String sats) {
    return '≈ $sats sats';
  }

  @override
  String satsFigureExact(String sats) {
    return '$sats sats';
  }

  @override
  String get chatGroupActive => 'Scambi attivi';

  @override
  String chatContextSellActive(String amount, String currency) {
    return 'Vendi $amount $currency';
  }

  @override
  String chatContextBuyActive(String amount, String currency) {
    return 'Compri $amount $currency';
  }

  @override
  String chatContextSellClosed(String amount, String currency) {
    return 'Hai venduto $amount $currency';
  }

  @override
  String chatContextBuyClosed(String amount, String currency) {
    return 'Hai comprato $amount $currency';
  }

  @override
  String get chatTurnAddInvoice => 'tocca a te la fattura';

  @override
  String get chatTurnPayBond => 'tocca a te pagare il deposito';

  @override
  String get chatTurnPayInvoice => 'tocca a te pagare la fattura';

  @override
  String get chatTurnSendPayment => 'tocca a te pagare';

  @override
  String get chatTurnRelease => 'tocca a te rilasciare';

  @override
  String get chatTurnRate => 'tocca a te valutare';

  @override
  String get chatYouLabel => 'Tu:';

  @override
  String get chatListFootnote =>
      'Ogni conversazione appartiene a uno scambio ed è cifrata end-to-end. Terminato lo scambio, resta qui da consultare.';

  @override
  String get chatListEmptyTitle => 'Nessuna conversazione per ora';

  @override
  String get chatListEmptyBody =>
      'La chat si apre quando uno scambio diventa attivo.';

  @override
  String get chatClosedNotice =>
      'Lo scambio è terminato. La conversazione resta qui da consultare.';

  @override
  String disputeOpenedByYou(String time) {
    return 'L\'hai aperta $time';
  }

  @override
  String disputeOpenedByPeer(String time) {
    return 'L\'ha aperta la controparte $time';
  }

  @override
  String get invoiceReceiveTitle => 'Ricevi i tuoi sats';

  @override
  String get invoiceLockTitle => 'Blocca i tuoi sats';

  @override
  String get bondTitle => 'Deposito di garanzia';

  @override
  String get bondRefundableLabel => 'DEPOSITO RIMBORSABILE';

  @override
  String get bondComesBack => 'torna a te al completamento';

  @override
  String bondFiatComesBack(String fiat) {
    return '≈ $fiat · torna a te al completamento';
  }

  @override
  String bondPaySemantics(String sats) {
    return 'Deposito rimborsabile di $sats sats';
  }

  @override
  String bondReleasesIn(String time) {
    return 'L\'ordine viene liberato se non paghi entro $time';
  }

  @override
  String bondRowHeld(String bold) {
    return 'I sats restano $bold, non vengono spesi';
  }

  @override
  String get bondRowHeldBold => 'trattenuti nel tuo wallet';

  @override
  String bondRowReleased(String bold) {
    return 'Se lo scambio finisce bene, $bold';
  }

  @override
  String get bondRowReleasedBold => 'viene liberato da solo';

  @override
  String bondRowLost(String bold) {
    return 'Lo perdi solo se c\'è una disputa e $bold';
  }

  @override
  String bondRowLostTimeout(String bold) {
    return 'Lo perdi se lasci scadere un passaggio, o se c\'è una disputa e $bold';
  }

  @override
  String get bondRowLostBold => 'la perdi';

  @override
  String get bondWhyTitle => 'Perché Mostro chiede un deposito';

  @override
  String get bondWhyCustody =>
      'Mostro non custodisce fondi, quindi non può penalizzare chi abbandona uno scambio; il deposito fa quel lavoro e protegge tutti gli utenti dai truffatori.';

  @override
  String bondWhyHold(String hold) {
    return 'È una fattura $hold: il wallet riserva i sats senza inviarli; al completamento, la riserva si annulla da sola.';
  }

  @override
  String get bondWhyDispute =>
      'Se apri una disputa e vinci, lo recuperi comunque. Viene addebitato solo quando perdi una disputa.';

  @override
  String get bondWhyDisputeTimeout =>
      'Se apri una disputa e vinci, lo recuperi comunque. Viene addebitato solo quando perdi una disputa o lasci scadere un passaggio.';

  @override
  String get bondReadDocs => 'Leggi la documentazione';

  @override
  String get bondContextOrder => 'Ordine';

  @override
  String bondContextBuy(String fiat) {
    return 'Compri $fiat';
  }

  @override
  String bondContextSell(String fiat) {
    return 'Vendi $fiat';
  }

  @override
  String get bondContextEquals => 'Il deposito equivale a';

  @override
  String bondContextPercent(String pct) {
    return '$pct % dell\'importo';
  }

  @override
  String get bondDontPublish => 'Non pubblicare l\'ordine';

  @override
  String get bondAbandoned =>
      'Ordine scartato. Non è stato pubblicato nulla e non è stato addebitato nulla.';

  @override
  String bondPublishesIn(String time) {
    return 'Non ancora pubblicato: l\'ordine viene scartato se non paghi entro $time';
  }

  @override
  String get bondInvoiceMissingMaker =>
      'Questo dispositivo non ha una copia della fattura del deposito e il nodo non la rinvia per un ordine che hai creato. Scarta l\'ordine e crealo di nuovo.';

  @override
  String get bondExpiredBodyMaker =>
      'Non è stato pagato in tempo: l\'ordine non è mai stato pubblicato e nessun sat ha lasciato il tuo wallet.';

  @override
  String get bondExpiredNoticeMaker =>
      'La fattura del deposito è scaduta; l\'ordine non è stato pubblicato';

  @override
  String get orderStatusWaitingBond =>
      'In attesa del tuo deposito — non ancora pubblicato';

  @override
  String get bondCancelNotAllowed =>
      'Questo ordine non può essere annullato finché il deposito è in sospeso. Scartalo dalla schermata del deposito.';

  @override
  String createOrderBondNoticeEstimate(String sats) {
    return 'Questo nodo ti chiede di bloccare un deposito rimborsabile di ≈ $sats sats prima di pubblicare l\'ordine; torna quando lo scambio finisce onestamente.';
  }

  @override
  String get createOrderBondNotice =>
      'Questo nodo ti chiede di bloccare un deposito rimborsabile prima di pubblicare l\'ordine; torna quando lo scambio finisce onestamente.';

  @override
  String get bondClaimTitle => 'Reclama la tua parte';

  @override
  String get bondClaimShareLabel => 'LA TUA PARTE';

  @override
  String bondClaimShareSemantics(String sats) {
    return 'Parte di $sats sats da reclamare';
  }

  @override
  String bondClaimContext(String context) {
    return 'Dallo scambio di $context';
  }

  @override
  String bondClaimDeadline(String date) {
    return 'Reclama entro il $date';
  }

  @override
  String get bondClaimExplainer =>
      'Il deposito dell\'altra parte è stato confiscato a tuo favore. Aggiungi una fattura per esattamente questo importo e il nodo te lo paga.';

  @override
  String get bondClaimFieldLabel => 'Fattura Lightning';

  @override
  String get bondClaimFieldHint => 'lnbc… per esattamente la parte';

  @override
  String get bondClaimSubmit => 'Invia fattura';

  @override
  String get bondClaimSent => 'Fattura inviata al nodo';

  @override
  String get bondClaimSubmittedTitle => 'Fattura inviata';

  @override
  String get bondClaimSubmittedBody => 'In attesa che il nodo la confermi.';

  @override
  String get bondClaimAcknowledgedTitle => 'Pagamento in corso';

  @override
  String get bondClaimAcknowledgedBody =>
      'Il nodo ha accettato la tua fattura e la sta pagando. Se non riesce a instradarla, te ne chiederà una nuova.';

  @override
  String get bondClaimCompletedTitle => 'Pagato';

  @override
  String bondClaimCompletedBody(String sats) {
    return '$sats sats sono arrivati nel tuo wallet.';
  }

  @override
  String get bondClaimExpiredTitle => 'La finestra per reclamare è finita';

  @override
  String bondClaimExpiredBody(String date) {
    return 'Si è chiusa il $date. La parte non può più essere reclamata.';
  }

  @override
  String get bondClaimMissing => 'Nessuna richiesta trovata per questo ordine.';

  @override
  String get bondClaimErrorAmount =>
      'La fattura deve essere per esattamente la parte indicata.';

  @override
  String get bondClaimErrorExpired =>
      'La finestra per reclamare è finita; la parte non può più essere reclamata.';

  @override
  String get bondClaimErrorRejected =>
      'Il nodo non ha accettato la fattura. Provane un\'altra.';

  @override
  String get bondClaimErrorNotClaimable =>
      'Questa richiesta non accetta una fattura in questo momento.';

  @override
  String get bondClaimErrorNoKey =>
      'Questo dispositivo non ha la chiave di quello scambio, quindi non può reclamare la parte.';

  @override
  String get tradeVerbClaimPayout => 'Reclama il pagamento';

  @override
  String get chatTurnClaimPayout => 'tocca a te reclamare il pagamento';

  @override
  String get tradeBadgePayoutPending => 'Pagamento in sospeso';

  @override
  String get tradeBadgePayoutInProgress => 'Pagamento in corso';

  @override
  String get tradeBadgePayoutPaid => 'Pagamento ricevuto';

  @override
  String bondBannerPendingTitle(String sats) {
    return '$sats sats sono pronti a tornare a te';
  }

  @override
  String bondBannerPendingBody(String sats) {
    return 'Il deposito dell\'altra parte è stato confiscato a tuo favore. Aggiungi una fattura Lightning per $sats sats per reclamarlo.';
  }

  @override
  String get bondBannerAddInvoice => 'Aggiungi fattura di pagamento';

  @override
  String get bondBannerView => 'Vedi richiesta';

  @override
  String get bondBannerInProgressTitle => 'Pagamento in corso';

  @override
  String bondBannerInProgressBody(String sats) {
    return 'Il nodo sta pagando la tua parte di $sats sats.';
  }

  @override
  String get bondBannerPaidTitle => 'Pagamento ricevuto';

  @override
  String bondBannerPaidBody(String sats, String date) {
    return '$sats sats ti sono stati pagati il $date.';
  }

  @override
  String bondBannerExpired(String date) {
    return 'La richiesta sul deposito dell\'altra parte si è chiusa il $date.';
  }

  @override
  String get bondClaimNewTitle => 'Pagamento del deposito da reclamare';

  @override
  String bondClaimNewMessage(String sats) {
    return 'Puoi reclamare $sats sats da un deposito confiscato. Aggiungi una fattura Lightning per riceverli.';
  }

  @override
  String get bondClaimPaidTitle => 'Pagamento del deposito ricevuto';

  @override
  String bondClaimPaidMessage(String sats) {
    return 'Pagamento del deposito di $sats sats ricevuto.';
  }

  @override
  String get bondDontTake => 'Non prendere l\'ordine';

  @override
  String get bondLockedNowEscrow =>
      'Deposito bloccato. Ora blocca l\'importo dello scambio.';

  @override
  String get bondLostRace =>
      'Un altro utente ha preso questo ordine prima che il tuo deposito fosse pagato';

  @override
  String get bondMakerCanceled => 'Il creatore ha annullato questo ordine';

  @override
  String get bondExpiredNotice =>
      'La fattura del deposito è scaduta; l\'ordine è tornato nel book';

  @override
  String get bondExpiredTitle => 'La fattura del deposito è scaduta';

  @override
  String get bondExpiredBody =>
      'Non è stata pagata in tempo: l\'ordine è tornato nel book e nessun sat ha lasciato il tuo wallet.';

  @override
  String get bondInvoiceMissing =>
      'Questo dispositivo non ha una copia della fattura del deposito. Richiedila al nodo per continuare a prendere l\'ordine.';

  @override
  String get bondRequestAgain => 'Richiedi di nuovo la fattura';

  @override
  String get bondRequestFailed =>
      'Il nodo non ha reinviato la fattura del deposito';

  @override
  String get invoiceOrderIdCopied => 'ID dell\'ordine copiato';

  @override
  String get invoiceYouReceiveLabel => 'Riceverai';

  @override
  String get invoiceToPayLabel => 'Da pagare';

  @override
  String invoiceReceiveSemantics(String sats) {
    return '$sats satoshi da ricevere';
  }

  @override
  String invoicePaySemantics(String sats) {
    return '$sats satoshi da pagare';
  }

  @override
  String invoiceFeeIncluded(String sats) {
    return 'Include $sats sats di commissione Mostro';
  }

  @override
  String invoiceTimeToSend(String time) {
    return 'Hai $time per inviarla';
  }

  @override
  String invoiceExpiresIn(String time) {
    return 'La fattura scade tra $time';
  }

  @override
  String get invoiceFieldLabel => 'Fattura o indirizzo Lightning';

  @override
  String get invoiceFieldHint => 'lnbc… o utente@dominio';

  @override
  String get invoiceFieldPromptLabel => 'Incolla qui la tua fattura';

  @override
  String get invoiceFieldFilledLabel => 'Fattura Lightning';

  @override
  String get invoiceFieldAddressLabel => 'Indirizzo Lightning';

  @override
  String get invoiceScanButton => 'Scansiona';

  @override
  String get invoiceReplaceButton => 'Sostituisci';

  @override
  String get invoiceFieldSemantics =>
      'Fattura o indirizzo Lightning, obbligatorio';

  @override
  String invoiceFilledSemantics(String sats) {
    return 'Fattura Lightning da $sats sats';
  }

  @override
  String get invoiceValidAddress =>
      'Indirizzo valido · la fattura verrà richiesta all\'invio';

  @override
  String invoiceValidInvoice(String sats) {
    return 'Fattura valida · $sats sats';
  }

  @override
  String invoiceErrorWrongAmount(String actual, String expected) {
    return 'La fattura è di $actual sats, devono essere $expected';
  }

  @override
  String get invoiceErrorExpired => 'La fattura è già scaduta';

  @override
  String invoiceErrorExpiresTooSoon(String minutes) {
    return 'La fattura scade tra meno di $minutes minuti, il nodo ha bisogno di più tempo per pagarla';
  }

  @override
  String get invoiceErrorMalformed =>
      'Questa fattura è incompleta o copiata male';

  @override
  String get invoiceErrorUnrecognized =>
      'Non è una fattura (lnbc…) né un indirizzo Lightning (utente@dominio)';

  @override
  String get invoiceSellerLabel => 'Venditore';

  @override
  String get invoiceBuyerLabel => 'Acquirente';

  @override
  String get invoiceYouPayLabel => 'Paghi';

  @override
  String get invoiceYouGetLabel => 'Ricevi';

  @override
  String get invoiceNoTrades => 'nessuna operazione';

  @override
  String get invoiceSendButton => 'Invia fattura';

  @override
  String get invoiceCancelTrade => 'Annulla operazione';

  @override
  String get invoiceOpenWallet => 'Apri nel mio wallet';

  @override
  String invoiceHoldNote(String hold) {
    return 'È una fattura $hold: i sats restano bloccati, non lasciano il tuo wallet finché non confermi il pagamento dell\'acquirente.';
  }

  @override
  String invoiceQrSemantics(String invoice) {
    return 'Codice QR della fattura Lightning: $invoice';
  }

  @override
  String get invoiceExpiredTitle => 'La fattura è scaduta';

  @override
  String get invoiceExpiredBody =>
      'Non è stata pagata in tempo: Mostro annulla l\'operazione e nessun sat ha lasciato il tuo wallet.';

  @override
  String get invoiceBackToBook => 'Torna al registro ordini';

  @override
  String get invoiceTimeUpTitle => 'Il tempo è scaduto';

  @override
  String get invoiceTimeUpBody =>
      'La fattura non è stata inviata in tempo: Mostro annulla l\'operazione. Da parte tua non è stato impegnato nulla.';

  @override
  String invoiceErrorWrongNetwork(String invoice, String node) {
    return 'La fattura è per $invoice, il nodo usa $node';
  }

  @override
  String invoiceCountdownHours(String hours, String minutes) {
    return '$hours h $minutes';
  }

  @override
  String get tradeCardWaitingBuyerInvoiceTitle =>
      'In attesa della fattura dell\'acquirente';

  @override
  String get tradeCardWaitingBuyerInvoiceMessage =>
      'Lo scambio prosegue quando l\'acquirente aggiunge una fattura Lightning.';

  @override
  String get tradeCardWaitingPaymentTitle =>
      'In attesa del pagamento del venditore';

  @override
  String get tradeCardWaitingPaymentMessage =>
      'Lo scambio prosegue quando il venditore paga la fattura hold.';

  @override
  String get tradeCardWaitingTakerBondTitle =>
      'Pagamento del deposito in sospeso';

  @override
  String get tradeCardWaitingTakerBondMessage =>
      'Il deposito anti-abuso di chi accetta l\'ordine deve essere pagato prima dell\'inizio dello scambio.';

  @override
  String get tradeCardActiveTitle => 'Scambio attivo';

  @override
  String get tradeCardActiveMessage =>
      'I sats sono bloccati. L\'acquirente può ora inviare il pagamento fiat.';

  @override
  String get tradeCardFiatSentTitle => 'Fiat segnato come inviato';

  @override
  String get tradeCardFiatSentMessage =>
      'L\'acquirente ha segnato il pagamento fiat come inviato.';

  @override
  String get tradeCardSettledHoldInvoiceTitle => 'Sats rilasciati';

  @override
  String get tradeCardSettledHoldInvoiceMessage =>
      'Il venditore ha rilasciato i sats. Il pagamento all\'acquirente è in arrivo.';

  @override
  String get tradeCardSuccessTitle => 'Scambio completato';

  @override
  String get tradeCardSuccessMessage =>
      'Lo scambio si è concluso con successo.';

  @override
  String get tradeCardCanceledTitle => 'Scambio annullato';

  @override
  String get tradeCardCanceledMessage => 'Lo scambio è stato annullato.';

  @override
  String get tradeCardExpiredTitle => 'Ordine scaduto';

  @override
  String get tradeCardExpiredMessage =>
      'L\'ordine è scaduto prima che lo scambio potesse proseguire.';

  @override
  String get tradeCardCooperativelyCanceledTitle =>
      'Scambio annullato di comune accordo';

  @override
  String get tradeCardCooperativelyCanceledMessage =>
      'Entrambe le parti hanno accettato di annullare lo scambio.';

  @override
  String get tradeCardDisputeTitle => 'Disputa aperta';

  @override
  String get tradeCardDisputeMessage =>
      'È stata aperta una disputa su questo scambio.';

  @override
  String get tradeCardCanceledByAdminTitle => 'Annullato dal mediatore';

  @override
  String get tradeCardCanceledByAdminMessage =>
      'Il mediatore della disputa ha annullato lo scambio.';

  @override
  String get tradeCardSettledByAdminTitle => 'Risolto dal mediatore';

  @override
  String get tradeCardSettledByAdminMessage =>
      'Il mediatore della disputa ha rilasciato i sats all\'acquirente.';

  @override
  String get tradeCardCompletedByAdminTitle => 'Completato dal mediatore';

  @override
  String get tradeCardCompletedByAdminMessage =>
      'Il mediatore della disputa ha completato lo scambio.';

  @override
  String get tradeCardUpdatedTitle => 'Scambio aggiornato';

  @override
  String get tradeCardUpdatedMessage =>
      'Lo stato di questo scambio è cambiato.';

  @override
  String get tradeCardCanceledByMakerMessage =>
      'Il creatore ha annullato l\'ordine.';

  @override
  String get tradeCardCanceledBondLostRaceMessage =>
      'Un altro utente ha preso questo ordine prima che il deposito fosse pagato.';

  @override
  String get tradeCardCanceledBondExpiredMessage =>
      'La fattura del deposito è scaduta senza essere pagata.';

  @override
  String get chatCardTitle => 'Nuovi messaggi';

  @override
  String get chatCardSolverTitle => 'Messaggi dal mediatore';

  @override
  String chatCardMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count nuovi messaggi dalla tua controparte',
      one: '1 nuovo messaggio dalla tua controparte',
    );
    return '$_temp0';
  }

  @override
  String chatCardSolverMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count nuovi messaggi dal mediatore della disputa',
      one: '1 nuovo messaggio dal mediatore della disputa',
    );
    return '$_temp0';
  }

  @override
  String get invalidTradeIndexError =>
      'Il tuo account non è sincronizzato con questo nodo Mostro, che ha quindi rifiutato l\'ordine. Riprova tra un momento';

  @override
  String get recoveringTradesMessage =>
      'Account importato. Recupero dei tuoi scambi da Mostro…';

  @override
  String recoveredTradesMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Account importato. $count scambi recuperati',
      one: 'Account importato. 1 scambio recuperato',
      zero: 'Account importato. Non avevi scambi in corso',
    );
    return '$_temp0';
  }

  @override
  String get recoverTradesFailedMessage =>
      'Account importato, ma Mostro non ha risposto: i tuoi scambi in corso non sono stati recuperati';

  @override
  String get paymentMethodsChosenLabel => 'Scelti';

  @override
  String paymentMethodsSelectedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count metodi selezionati',
      one: '1 metodo selezionato',
      zero: 'Scegli almeno un metodo',
    );
    return '$_temp0';
  }

  @override
  String get paymentMethodsConfirm => 'Conferma metodi';

  @override
  String get paymentMethodAddCustom => 'Aggiungi metodo personalizzato';

  @override
  String get paymentMethodsDiscardTitle => 'Vuoi annullare le modifiche?';

  @override
  String get paymentMethodsDiscardConfirm => 'Annulla modifiche';

  @override
  String get paymentMethodsKeepEditing => 'Continua a modificare';

  @override
  String get fundsAtRiskTitle => 'Questo utente ha ancora sats in gioco';

  @override
  String get fundsAtRiskBody =>
      'Se continui, le chiavi di questo utente vengono sostituite e nulla di quanto elencato qui potrà essere concluso né recuperato da questo dispositivo. Non è consigliato: puoi perdere questi sats.';

  @override
  String get fundsAtRiskSellerEscrow =>
      'Sats bloccati in garanzia per una vendita';

  @override
  String get fundsAtRiskBondLocked => 'Cauzione bloccata';

  @override
  String get fundsAtRiskPayoutClaim =>
      'Pagamento della cauzione non ancora riscosso';

  @override
  String get fundsAtRiskTradeInProgress => 'Scambio in corso';

  @override
  String get fundsAtRiskBondInvoicePending =>
      'Fattura della cauzione ancora pagabile';

  @override
  String get fundsAtRiskKeep => 'Mantieni questo utente';

  @override
  String get fundsAtRiskContinue => 'Continua comunque';

  @override
  String get restoreSheetTitle => 'Ripristino del tuo account';

  @override
  String get restoreSheetWaiting => 'Può richiedere qualche secondo';

  @override
  String restoreSheetLoading(int done, int total) {
    return '$done di $total ordini recuperati';
  }

  @override
  String get restoreStageConnecting => 'Connessione al nodo Mostro';

  @override
  String get restoreStageConnected => 'Connesso al nodo Mostro';

  @override
  String get restoreStageRequesting => 'Richiesta dei tuoi ordini';

  @override
  String restoreStageFound(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ordini trovati',
      one: '1 ordine trovato',
    );
    return '$_temp0';
  }

  @override
  String get restoreStageLoading => 'Caricamento dei dettagli';

  @override
  String get restoreStageNoResponse => 'Nessuna risposta';

  @override
  String restoreLoadingCountSemantics(int done, int total) {
    return '$done di $total ordini';
  }

  @override
  String get restoreFailedTitle =>
      'Non siamo riusciti a ripristinare i tuoi ordini';

  @override
  String get restoreFailedSubtitle =>
      'Il tuo account è stato comunque importato';

  @override
  String restoreFailedBody(String place) {
    return 'Controlla la connessione e riprova. Puoi riprovare quando vuoi da $place.';
  }

  @override
  String get restoreContinueWithout => 'Continua senza ripristinare';

  @override
  String get restoreDoneTitle => 'Account ripristinato';

  @override
  String get restoreDoneSubtitle =>
      'Abbiamo recuperato tutto ciò che il nodo aveva';

  @override
  String get restoreDoneEmptySubtitle =>
      'Questo account non aveva ordini sul nodo';

  @override
  String get restoreSummaryOrders => 'Ordini';

  @override
  String get restoreSummaryInProgress => 'In corso';

  @override
  String restoreActionNotice(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Hai $count ordini attivi in attesa di una tua azione',
      one: 'Hai 1 ordine attivo in attesa di una tua azione',
    );
    return '$_temp0';
  }

  @override
  String restorePartialNotice(int missing, int total) {
    return '$missing di $total ordini non sono stati caricati';
  }
}

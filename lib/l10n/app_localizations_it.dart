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
  String get tabBuyBtc => 'COMPRA BTC';

  @override
  String get tabSellBtc => 'VENDI BTC';

  @override
  String get filterButtonLabel => 'FILTRA';

  @override
  String offersCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count offerte',
      one: '1 offerta',
    );
    return '$_temp0';
  }

  @override
  String get noOrdersAvailable => 'Nessun ordine disponibile';

  @override
  String get justNow => 'Proprio ora';

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
  String get creatingNewOrderTitle => 'CREAZIONE NUOVO ORDINE';

  @override
  String get youWantToBuyBitcoin => 'Vuoi acquistare Bitcoin';

  @override
  String get youWantToSellBitcoin => 'Vuoi vendere Bitcoin';

  @override
  String get rangeOrderLabel => 'Ordine a intervallo';

  @override
  String get payLightningInvoiceTitle => 'Paga Fattura Lightning';

  @override
  String get invoiceCopied => 'Fattura copiata';

  @override
  String get addInvoiceTitle => 'Aggiungi Fattura';

  @override
  String get submitButtonLabel => 'Invia';

  @override
  String get orderAlreadyTaken => 'L\'ordine è già stato preso';

  @override
  String get bondRequired =>
      'Questo nodo richiede una cauzione anti-abuso, non ancora supportata';

  @override
  String addInvoiceAmount(String sats) {
    return 'Importo da ricevere: $sats sats';
  }

  @override
  String payInvoiceAmount(String sats) {
    return 'Importo da pagare: $sats sats';
  }

  @override
  String get orderIdCopied => 'ID ordine copiato';

  @override
  String get orderDetailsTitle => 'DETTAGLI ORDINE';

  @override
  String get timeRemainingLabel => 'Tempo rimanente:';

  @override
  String get fiatSentButtonLabel => 'FIAT INVIATO';

  @override
  String get disputeButtonLabel => 'DISPUTA';

  @override
  String get contactButtonLabel => 'CONTATTA';

  @override
  String get rateButtonLabel => 'VALUTA';

  @override
  String get viewDisputeButtonLabel => 'VEDI DISPUTA';

  @override
  String get comingSoonMessage => 'Prossimamente';

  @override
  String get tradeStatusActive => 'Attivo';

  @override
  String get tradeStatusFiatSent => 'Fiat inviato';

  @override
  String get tradeStatusCompleted => 'Completato';

  @override
  String get tradeStatusCancelled => 'Annullato';

  @override
  String get tradeStatusDisputed => 'In disputa';

  @override
  String get releaseButtonLabel => 'RILASCIA';

  @override
  String get accountScreenTitle => 'Account';

  @override
  String get secretWordsTitle => 'Parole segrete';

  @override
  String get toRestoreYourAccount => 'Per ripristinare il tuo account';

  @override
  String get privacyCardTitle => 'Privacy';

  @override
  String get controlPrivacySettings => 'Gestisci le impostazioni sulla privacy';

  @override
  String get reputationMode => 'Modalità Reputazione';

  @override
  String get reputationModeSubtitle => 'Privacy standard con reputazione';

  @override
  String get fullPrivacyMode => 'Modalità Privacy Totale';

  @override
  String get fullPrivacyModeSubtitle => 'Anonimato massimo';

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
  String get importMnemonicDialogTitle => 'Importa Mnemonica';

  @override
  String get importMnemonicHintText =>
      'Inserisci la tua frase da 12 o 24 parole…';

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
  String get showButtonLabel => 'Mostra';

  @override
  String get settingsScreenTitle => 'Impostazioni';

  @override
  String get languageSettingTitle => 'Lingua';

  @override
  String get appearanceSettingTitle => 'Aspetto';

  @override
  String get appearanceDialogTitle => 'Aspetto';

  @override
  String get defaultFiatCurrencyTitle => 'Valuta fiat predefinita';

  @override
  String get allCurrencies => 'Tutte le valute';

  @override
  String get lightningAddressSettingTitle => 'Indirizzo Lightning';

  @override
  String get tapToSetSubtitle => 'Tocca per impostare';

  @override
  String get nwcWalletSettingTitle => 'Portafoglio NWC';

  @override
  String get nwcConnectPrompt =>
      'Collega il tuo portafoglio Lightning tramite NWC';

  @override
  String get relaysSettingTitle => 'Relay';

  @override
  String get manageRelayConnections => 'Gestisci connessioni relay';

  @override
  String get pushNotificationsSettingTitle => 'Notifiche push';

  @override
  String get manageNotificationPreferences => 'Gestisci preferenze notifiche';

  @override
  String get logReportSettingTitle => 'Registro diagnostico';

  @override
  String get viewDiagnosticLogs => 'Visualizza log diagnostici';

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
  String get connectWalletTitle => 'Collega portafoglio';

  @override
  String get scanQrCodeTitle => 'Scansiona codice QR';

  @override
  String get pasteNwcUri => 'Incolla URI NWC';

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
  String nwcConnectedBalance(String balance) {
    return 'NWC — Connesso. Saldo: $balance';
  }

  @override
  String get pasteQrCodeHeading => 'Incolla contenuto del codice QR';

  @override
  String get pasteButtonLabel => 'Incolla';

  @override
  String get clipboardEmptyError => 'Gli appunti sono vuoti';

  @override
  String get enterValueError => 'Inserisci un valore';

  @override
  String get pasteOrScanQrCode => 'Incolla o scansiona un codice QR';

  @override
  String get mostroNodeTitle => 'Nodo Mostro';

  @override
  String get currentNodeLabel => 'Nodo attuale';

  @override
  String get trustedBadgeLabel => 'Affidabile';

  @override
  String get useDefaultButtonLabel => 'Usa predefinito';

  @override
  String get confirmButtonLabel => 'Conferma';

  @override
  String get invalidHexPubkey =>
      'Deve essere una stringa esadecimale di 64 caratteri';

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
  String get submitRatingButton => 'INVIA';

  @override
  String get closeRatingButton => 'CHIUDI';

  @override
  String get aboutScreenTitle => 'Informazioni';

  @override
  String get mostroTagline => 'Trading Bitcoin peer-to-peer su Nostr';

  @override
  String get viewDocumentationButton => 'Visualizza documentazione';

  @override
  String get linkCopiedToClipboard => 'Link copiato negli appunti';

  @override
  String get defaultNodeSection => 'Nodo predefinito';

  @override
  String get pubkeyLabel => 'Chiave pubblica';

  @override
  String get relaysLabel => 'Relay';

  @override
  String get pubkeyCopiedToClipboard => 'Chiave pubblica copiata negli appunti';

  @override
  String get footerTagline => 'Open-source. Non custodiale. Privato.';

  @override
  String get drawerTitle => 'MOSTRO';

  @override
  String get betaBadgeLabel => 'Beta';

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
  String get backupConfirmCheckbox =>
      'Ho annotato le mie parole e le ho salvate in modo sicuro';

  @override
  String get cancelTradeDialogTitle => 'Annullare lo scambio?';

  @override
  String get cancelTradeDialogContent =>
      'Annullamento cooperativo richiesto. Anche l\'altra parte deve accettare affinché lo scambio venga annullato.';

  @override
  String get noButtonLabel => 'No';

  @override
  String get yesCancelButtonLabel => 'Sì, annulla';

  @override
  String get cancelRequestSent => 'Richiesta di annullamento inviata';

  @override
  String get cancelRequestFailed => 'Annullamento fallito. Riprovare.';

  @override
  String get fiatSentFailed =>
      'Impossibile contrassegnare il fiat come inviato. Riprovare.';

  @override
  String get releaseFailed => 'Rilascio fallito. Riprovare.';

  @override
  String get orderPillYouAreSelling => 'STAI VENDENDO';

  @override
  String get orderPillYouAreBuying => 'STAI COMPRANDO';

  @override
  String get orderPillSelling => 'VENDITA';

  @override
  String get orderPillBuying => 'ACQUISTO';

  @override
  String get myOrderSellTitle => 'IL TUO ORDINE DI VENDITA';

  @override
  String get myOrderBuyTitle => 'IL TUO ORDINE DI ACQUISTO';

  @override
  String get cancelOrderButton => 'Annulla ordine';

  @override
  String get cancelOrderDialogTitle => 'Annulla ordine';

  @override
  String get cancelOrderDialogContent =>
      'Sei sicuro di voler annullare questo ordine? Questa azione non può essere annullata.';

  @override
  String get cancelOrderFailed => 'Annullamento fallito. Riprovare.';

  @override
  String get closeButtonLabel => 'Chiudi';

  @override
  String get copyButtonLabel => 'Copia';

  @override
  String get orderStatusWaitingForTaker => 'In attesa di un taker';

  @override
  String get orderStatusWaitingBuyerInvoice =>
      'In attesa della fattura dell\'acquirente';

  @override
  String get orderStatusWaitingPayment => 'In attesa del pagamento';

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
  String get aboutAppInfoTitle => 'Informazioni sull\'app';

  @override
  String get aboutDocumentationTitle => 'Documentazione';

  @override
  String get aboutMostroNodeTitle => 'Nodo Mostro';

  @override
  String get aboutVersionLabel => 'Versione';

  @override
  String get aboutGithubRepoLabel => 'Repository GitHub';

  @override
  String get aboutCommitHashLabel => 'Hash del commit';

  @override
  String get aboutLicenseLabel => 'Licenza';

  @override
  String get aboutLicenseName => 'MIT';

  @override
  String get aboutGithubRepoName => 'mostro-mobile';

  @override
  String get aboutDocsUsersEnglish => 'Utenti (Inglese)';

  @override
  String get aboutDocsUsersSpanish => 'Utenti (Spagnolo)';

  @override
  String get aboutDocsTechnical => 'Tecnica';

  @override
  String get aboutDocsRead => 'Leggi';

  @override
  String get aboutCopiedToClipboard => 'Copiato negli appunti';

  @override
  String get aboutLicenseDialogTitle => 'Licenza MIT';

  @override
  String get aboutNodeLoadingText => 'Caricamento informazioni del nodo…';

  @override
  String get aboutNodeUnavailable => 'Informazioni del nodo non disponibili';

  @override
  String get aboutNodeRetry => 'Riprova';

  @override
  String get aboutGeneralInfoSection => 'Informazioni generali';

  @override
  String get aboutTechnicalDetailsSection => 'Dettagli tecnici';

  @override
  String get aboutLightningNetworkSection => 'Rete Lightning';

  @override
  String get aboutMostroPublicKeyLabel => 'Chiave pubblica Mostro';

  @override
  String get aboutMaxOrderAmountLabel => 'Importo massimo ordine';

  @override
  String get aboutMinOrderAmountLabel => 'Importo minimo ordine';

  @override
  String get aboutOrderLifespanLabel => 'Durata dell\'ordine';

  @override
  String get aboutServiceFeeLabel => 'Commissione di servizio';

  @override
  String get aboutFiatCurrenciesLabel => 'Valute fiat';

  @override
  String get aboutMostroVersionLabel => 'Versione Mostro';

  @override
  String get aboutMostroCommitLabel => 'Commit Mostro';

  @override
  String get aboutOrderExpirationLabel => 'Scadenza dell\'ordine';

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
  String get aboutLndNodePublicKeyLabel => 'Chiave pubblica nodo LND';

  @override
  String get aboutLndCommitLabel => 'Commit LND';

  @override
  String get aboutLndNodeAliasLabel => 'Alias nodo LND';

  @override
  String get aboutSupportedChainsLabel => 'Chain supportate';

  @override
  String get aboutSupportedNetworksLabel => 'Reti supportate';

  @override
  String get aboutLndNodeUriLabel => 'URI del nodo LND';

  @override
  String get aboutSatoshisSuffix => 'Satoshi';

  @override
  String get aboutHoursSuffix => 'ore';

  @override
  String get aboutSecondsSuffix => 'secondi';

  @override
  String get aboutBlocksSuffix => 'blocchi';

  @override
  String get aboutFiatCurrenciesAll => 'Tutte';

  @override
  String get aboutMostroPublicKeyExplanation =>
      'La chiave pubblica Nostr del daemon Mostro. Tutti gli ordini e i messaggi cifrati di questa istanza sono pubblicati o instradati da questa chiave.';

  @override
  String get aboutMaxOrderAmountExplanation =>
      'L\'importo fiat massimo consentito per un singolo ordine su questa istanza Mostro.';

  @override
  String get aboutMinOrderAmountExplanation =>
      'L\'importo fiat minimo richiesto per un singolo ordine su questa istanza Mostro.';

  @override
  String get aboutOrderLifespanExplanation =>
      'Per quanto tempo un ordine in attesa rimane aperto prima di scadere automaticamente se non viene trovato un prenditore.';

  @override
  String get aboutServiceFeeExplanation =>
      'La percentuale dell\'importo della transazione addebitata dal daemon Mostro come commissione di servizio.';

  @override
  String get aboutFiatCurrenciesExplanation =>
      'Le valute fiat accettate su questa istanza Mostro. \'Tutte\' significa che non ci sono restrizioni.';

  @override
  String get aboutMostroVersionExplanation =>
      'La versione del software daemon Mostro in esecuzione su questa istanza.';

  @override
  String get aboutMostroCommitExplanation =>
      'L\'hash del commit Git della build del daemon Mostro, utilizzato per identificare la revisione esatta del software.';

  @override
  String get aboutOrderExpirationExplanation =>
      'Il timeout in secondi dopo il quale una transazione in attesa di azione (es. fattura o pagamento) viene automaticamente annullata.';

  @override
  String get aboutHoldInvoiceExpExplanation =>
      'La finestra di tempo in secondi entro cui la hold invoice Lightning deve essere saldata.';

  @override
  String get aboutHoldInvoiceCltvExplanation =>
      'Il delta CLTV (numero di blocchi) utilizzato per le hold invoice, che controlla per quanto tempo l\'HTLC può rimanere bloccato.';

  @override
  String get aboutInvoiceExpWindowExplanation =>
      'La finestra di tempo in secondi entro cui l\'acquirente deve presentare una fattura Lightning dopo l\'avvio della transazione.';

  @override
  String get aboutProofOfWorkExplanation =>
      'La difficoltà minima di proof-of-work richiesta per gli eventi Nostr su questa istanza. 0 significa che non è richiesto PoW.';

  @override
  String get aboutMaxOrdersPerResponseExplanation =>
      'Il numero massimo di ordini restituiti in una singola risposta del relay. Limita l\'utilizzo della larghezza di banda.';

  @override
  String get aboutLndVersionExplanation =>
      'La versione del nodo LND (Lightning Network Daemon) connesso a questa istanza Mostro.';

  @override
  String get aboutLndNodePublicKeyExplanation =>
      'La chiave pubblica del nodo LND. Utilizzata per identificare e verificare il nodo della rete Lightning.';

  @override
  String get aboutLndCommitExplanation =>
      'L\'hash del commit Git della build LND, che identifica la revisione esatta del software del nodo Lightning.';

  @override
  String get aboutLndNodeAliasExplanation =>
      'L\'alias leggibile dall\'uomo del nodo LND configurato dall\'operatore del nodo.';

  @override
  String get aboutSupportedChainsExplanation =>
      'La/le blockchain supportata/e dal nodo LND (es. \'bitcoin\').';

  @override
  String get aboutSupportedNetworksExplanation =>
      'La/le rete/i su cui opera il nodo LND (es. \'mainnet\', \'testnet\').';

  @override
  String get aboutLndNodeUriExplanation =>
      'L\'URI di connessione del nodo LND nel formato pubkey@host:porta. Utilizzato per aprire canali di pagamento diretti.';

  @override
  String get openDisputeFailed => 'Impossibile aprire la disputa. Riprovare.';

  @override
  String get tradeWaitingInvoiceBuyerInstruction =>
      'Invia la tua fattura Lightning per permettere al venditore di bloccare i fondi.';

  @override
  String get tradeWaitingInvoiceSellerInstruction =>
      'In attesa che il compratore invii la propria fattura Lightning.';

  @override
  String get tradeWaitingPaymentBuyerInstruction =>
      'Il venditore sta pagando la fattura hold. Attendere.';

  @override
  String get tradeWaitingPaymentSellerInstruction =>
      'Paga la fattura hold per bloccare i fondi e avviare lo scambio.';

  @override
  String get tradeLoadError =>
      'Si è verificato un errore durante il caricamento dello scambio.';

  @override
  String get tradeWaitingForHoldInvoice => 'In attesa della fattura hold...';

  @override
  String get payInvoiceInstruction =>
      'Paga questa fattura hold per avviare lo scambio.';

  @override
  String get shareButtonLabel => 'Condividi';

  @override
  String get shareFailed => 'Impossibile condividere la fattura';

  @override
  String get waitingForPaymentConfirmation =>
      'In attesa di conferma del pagamento...';

  @override
  String get payWithLightningWallet => 'Paga con wallet Lightning';

  @override
  String get noLightningWalletFound =>
      'Nessun wallet Lightning trovato su questo dispositivo';

  @override
  String get orderNoLongerActive => 'Questo ordine non è più attivo';

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
  String get failedToConfirmBackupMessage =>
      'Impossibile confermare il backup. Riprova.';

  @override
  String get secretWordsInfoContent =>
      'Le tue 12 parole segrete sono l\'unico modo per recuperare il tuo account. Salvale in un luogo sicuro — non condividerle mai con nessuno.';

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
      'Mnemonico non valido. Controlla le tue parole e riprova.';

  @override
  String get enterValidMnemonicError =>
      'Inserisci una frase valida da 12 o 24 parole.';

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
  String get backedUpBadgeLabel => 'Salvato';

  @override
  String get backupBannerTitle => 'Proteggi la tua reputazione';

  @override
  String get backupBannerSubtitle =>
      'Salva le tue 12 parole — bastano 60 secondi.';

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
      'Queste parole verranno nascoste quando lasci questa schermata';

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
  String get allWordsCorrectMessage => 'Tutte e 3 le parole corrette!';

  @override
  String get showWordsAgainButton => 'Mostra di nuovo le parole';

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
  String get remindMeTomorrowButton => 'Ricordamelo domani';

  @override
  String get nwcConnectionFailedMessage =>
      'Connessione non riuscita. Controlla il tuo URI NWC e riprova.';

  @override
  String get connectWalletDescription =>
      'Connetti il tuo wallet Lightning usando un\nURI Nostr Wallet Connect (NWC).';

  @override
  String get nwcUriLabel => 'NWC URI';

  @override
  String get clipboardInvalidNwcUriMessage =>
      'Gli appunti non contengono un URI NWC valido.';

  @override
  String get scanQrButtonLabel => 'Scansiona QR';

  @override
  String get connectButtonLabel => 'Connetti';

  @override
  String get walletConfigurationTitle => 'Configurazione wallet';

  @override
  String get walletDisconnectedMessage => 'Wallet disconnesso';

  @override
  String get connectedBadgeLabel => 'Connesso';

  @override
  String get balanceLabel => 'Saldo';

  @override
  String get relayLabel => 'Relay';

  @override
  String get noWalletConnectedTitle => 'Nessun wallet connesso';

  @override
  String get connectWalletPrompt =>
      'Connetti un wallet per abilitare i pagamenti Lightning automatici.';

  @override
  String get disconnectButtonLabel => 'Disconnetti';

  @override
  String relaysMoreSuffix(int count) {
    return '(+$count altri)';
  }

  @override
  String get chooseNotificationEventsSubtitle =>
      'Scegli quali eventi attivano le notifiche push.';

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
  String get failedToResetNodeMessage => 'Impossibile reimpostare il nodo';

  @override
  String get invalidPubkeyOrBridgeErrorMessage =>
      'Chiave pubblica non valida o errore del bridge';

  @override
  String get currentNodePublicKeyLabel => 'Chiave pubblica del nodo attuale';

  @override
  String get useCustomNodePubkeyLabel =>
      'Usa una chiave pubblica del nodo personalizzata';

  @override
  String get enterHexPubkeyHint =>
      'Inserisci una chiave pubblica hex di 64 caratteri';

  @override
  String get shareLogsTooltip => 'Condividi i log';

  @override
  String get noLogsToShareTooltip => 'Nessun log da condividere';

  @override
  String get disableLoggingTooltip => 'Disattiva la registrazione';

  @override
  String get enableLoggingTooltip => 'Attiva la registrazione';

  @override
  String get loggingEnabledStatus => 'Registrazione attivata';

  @override
  String get loggingDisabledStatus => 'Registrazione disattivata';

  @override
  String get noLogEntriesMessage => 'Nessuna voce di registro';

  @override
  String get failedToShareLogsMessage => 'Impossibile condividere i log';

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
  String get tradeStatusFilterPrefix => 'Stato';

  @override
  String get noTradesTitle => 'Nessuna operazione';

  @override
  String get noTradesSubtitle =>
      'Le tue operazioni attive e completate appariranno qui.';

  @override
  String get couldNotLoadTradesMessage => 'Impossibile caricare le operazioni';

  @override
  String get releaseBitcoinTitle => 'Rilascia Bitcoin';

  @override
  String get releaseBitcoinConfirmation =>
      'Sei sicuro di voler rilasciare i Satoshi all\'acquirente?';

  @override
  String get yesButtonLabel => 'Sì';

  @override
  String get sellingBitcoin => 'Vendita di Bitcoin';

  @override
  String get buyingBitcoin => 'Acquisto di Bitcoin';

  @override
  String get createdByYou => 'Creata da te';

  @override
  String get takenByYou => 'Presa da te';

  @override
  String get timeAgoNow => 'ora';

  @override
  String timeAgoMinutes(int count) {
    return '${count}min';
  }

  @override
  String timeAgoHours(int count) {
    return '${count}h';
  }

  @override
  String timeAgoDays(int count) {
    return '${count}g';
  }

  @override
  String get tradeStatusLoading => 'Caricamento';

  @override
  String get tradeStatusRate => 'Valuta';

  @override
  String get tradeStatusRated => 'Valutato';

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
  String get tradeInstructionPendingRating =>
      'L\'operazione si è conclusa con successo. Valuta la tua controparte per contribuire a costruire fiducia nella comunità.';

  @override
  String get tradeInstructionRated => 'Grazie per la tua valutazione!';

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
  String get tradeHeadlineComplete => 'Operazione completata!';

  @override
  String get tradeHeadlineCompleteRated => 'Operazione completata';

  @override
  String get tradeHeadlineCancelled => 'Ordine annullato';

  @override
  String get tradeHeadlineLoading => 'Caricamento operazione…';

  @override
  String get tradeTimerPendingLabel =>
      'Tempo in cui questo ordine resta nel book';

  @override
  String get tradeTimerPendingConsequence =>
      'Se scade, l\'ordine viene rimosso dal book. Non influirà sulla tua reputazione.';

  @override
  String get tradeTimerWaitingInvoiceLabelBuyer =>
      'Tempo per condividere la tua fattura';

  @override
  String get tradeTimerWaitingInvoiceLabelSeller =>
      'Tempo perché l\'acquirente condivida una fattura';

  @override
  String get tradeTimerWaitingInvoiceConsequence =>
      'Se scade, l\'operazione viene annullata e l\'ordine torna nel book.';

  @override
  String get tradeTimerWaitingPaymentLabelBuyer =>
      'Tempo perché il venditore blocchi i sats';

  @override
  String get tradeTimerWaitingPaymentLabelSeller =>
      'Tempo per pagare la hold invoice';

  @override
  String get tradeTimerActiveLabelBuyer =>
      'Tempo per inviare il pagamento fiat';

  @override
  String get tradeTimerActiveLabelSeller =>
      'Tempo perché l\'acquirente invii il fiat';

  @override
  String get tradeTimerActiveConsequence =>
      'Se scade, l\'operazione può essere annullata. Coordinatevi nella chat se serve più tempo.';

  @override
  String get tradeTimerFiatSentLabelBuyer =>
      'Tempo perché il venditore confermi la ricezione';

  @override
  String get tradeTimerFiatSentLabelSeller =>
      'Tempo per confermare la ricezione e rilasciare';

  @override
  String get tradeTimerFiatSentConsequence =>
      'Se qualcosa non va, apri una disputa dal menu ⋮.';

  @override
  String get tradeStepOrderTaken => 'Ordine preso';

  @override
  String get tradeStepInvoiceBuyer =>
      'Condividi una fattura · il venditore blocca i sats';

  @override
  String get tradeStepInvoiceSeller =>
      'L\'acquirente condivide una fattura · tu blocchi i sats';

  @override
  String get tradeStepFiatBuyer => 'Invii il pagamento fiat';

  @override
  String get tradeStepFiatSeller => 'L\'acquirente invia il pagamento fiat';

  @override
  String get tradeStepReleaseBuyer =>
      'Il venditore conferma e rilascia i tuoi sats';

  @override
  String get tradeStepReleaseSeller => 'Confermi la ricezione e rilasci i sats';

  @override
  String get tradeStepRate => 'Valuta la tua controparte';

  @override
  String get activeTradeTitle => 'OPERAZIONE ATTIVA';

  @override
  String tradeIdShortLabel(String id) {
    return 'ID $id';
  }

  @override
  String tradeCreatedAtLabel(String date) {
    return 'creata $date';
  }

  @override
  String get releaseSatsMenuItem => 'Rilascia sats';

  @override
  String get cancelOrderMenuItem => 'Annulla ordine';

  @override
  String get openDisputeMenuItem => 'Apri disputa';

  @override
  String get stepDoneLabel => 'FATTO';

  @override
  String stepIndicator(int current, int total) {
    return 'PASSO $current DI $total';
  }

  @override
  String get addLightningInvoiceButton => 'Aggiungi fattura Lightning';

  @override
  String get payHoldInvoiceButton => 'Paga hold invoice';

  @override
  String get markFiatSentButton => 'Segna fiat inviato';

  @override
  String get confirmReleaseSatsButton => 'Conferma e rilascia sats';

  @override
  String get viewDisputeButton => 'Vedi disputa';

  @override
  String get waitingForBuyer => 'In attesa dell\'acquirente…';

  @override
  String get waitingForSeller => 'In attesa del venditore…';

  @override
  String get waitingForFiatPayment => 'In attesa del pagamento fiat…';

  @override
  String get waitingForCounterpart => 'In attesa di una controparte…';

  @override
  String get yourTradeTimelineTitle => 'LA TUA OPERAZIONE';

  @override
  String get yourCounterpartFallback => 'la tua controparte';

  @override
  String secureChatUnread(int count) {
    return 'Chat sicura · $count nuovi';
  }

  @override
  String get secureChatEncrypted => 'Chat sicura · crittografata end-to-end';

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
  String get activeTradeConversations =>
      'Le tue conversazioni di operazioni attive';

  @override
  String get noMessagesAvailable => 'Nessun messaggio disponibile';

  @override
  String get disputesAndAdminChat => 'Dispute e chat con amministratori';

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
  String sellingSatsTo(String handle) {
    return 'Stai vendendo sats a $handle';
  }

  @override
  String buyingSatsFrom(String handle) {
    return 'Stai comprando sats da $handle';
  }

  @override
  String youMessagePrefix(String message) {
    return 'Tu: $message';
  }

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
  String get waitingForTradeAmount =>
      'In attesa dell\'importo dell\'operazione — riprova tra poco.';

  @override
  String get fetchingTradeAmount => 'Recupero dell\'importo dell\'operazione…';

  @override
  String get enterInvoiceManually => 'Inserisci la fattura manualmente';

  @override
  String get enterLightningInvoiceInstruction =>
      'Inserisci una fattura Lightning per ricevere i tuoi sats';

  @override
  String get lightningInvoiceLabel => 'Fattura Lightning';

  @override
  String get submitButton => 'Invia';

  @override
  String get sellOrderDetailsTitle => 'DETTAGLI ORDINE DI VENDITA';

  @override
  String get buyOrderDetailsTitle => 'DETTAGLI ORDINE DI ACQUISTO';

  @override
  String get buyTheseSatsButton => 'COMPRA QUESTI SATS';

  @override
  String get sellSatsButton => 'VENDI SATS';

  @override
  String get someoneSellingSats => 'Qualcuno sta vendendo sats';

  @override
  String get someoneBuyingSats => 'Qualcuno sta comprando sats';

  @override
  String get takeOrderForPrefix => 'per ';

  @override
  String get takeOrderAtMarketPrice => ' al prezzo di mercato';

  @override
  String premiumLabel(String premium) {
    return 'Premio: $premium%';
  }

  @override
  String get creatorReputation => 'Reputazione del creatore';

  @override
  String get ratingStatLabel => 'valutazione';

  @override
  String get tradesStatLabel => 'operazioni';

  @override
  String get daysActiveStatLabel => 'giorni attivo';

  @override
  String get timeToTakeOrder => 'TEMPO PER PRENDERE QUEST\'ORDINE';

  @override
  String get orderExpiryRemovedNote =>
      'Se scade, l\'ordine viene rimosso dal book. ';

  @override
  String get orderExpiryNoReputationNote =>
      'Non influirà sulla tua reputazione.';

  @override
  String get minHint => 'Min';

  @override
  String get maxHint => 'Max';

  @override
  String get fiatAmountHint => 'Importo fiat';

  @override
  String get enterAmountForPreview =>
      'Inserisci un importo per vedere un\'anteprima in tempo reale.';

  @override
  String get previewLabel => 'ANTEPRIMA';

  @override
  String previewBuyMarket(String amount, String price) {
    return 'Compri BTC per $amount a $price · attivo per 24 h';
  }

  @override
  String previewSellMarket(String amount, String price) {
    return 'Vendi BTC per $amount a $price · attivo per 24 h';
  }

  @override
  String previewReceiveFixed(String sats, String amount) {
    return 'Ricevi $sats sats per $amount · attivo per 24 h';
  }

  @override
  String previewSellFixed(String sats, String amount) {
    return 'Vendi $sats sats per $amount · attivo per 24 h';
  }

  @override
  String get marketPriceLabel => 'prezzo di mercato';

  @override
  String marketPricePremium(String premium) {
    return 'mercato $premium%';
  }

  @override
  String get priceTypeLabel => 'Tipo di prezzo';

  @override
  String get priceTypeMarket => 'Mercato';

  @override
  String get priceTypeFixed => 'Fisso';

  @override
  String get priceTypeInfoTooltip => 'Info sul tipo di prezzo';

  @override
  String get premiumSectionLabel => 'Premio';

  @override
  String get amountInSatsHint => 'Importo in sats';

  @override
  String get priceTypesDialogTitle => 'Tipi di prezzo';

  @override
  String get priceTypesDialogContent =>
      'Prezzo di mercato: il prezzo del tuo ordine segue il tasso di mercato con una percentuale di premio/sconto applicata.\n\nPrezzo fisso: imposti un prezzo esatto in satoshi.';

  @override
  String get startFromPreset => 'INIZIA DA UN PRESET';

  @override
  String get presetExpressTitle => 'Express';

  @override
  String get recommendedTag => 'CONSIGLIATO';

  @override
  String get presetConservativeTitle => 'Conservativo';

  @override
  String get presetConservativeSubtitle =>
      'Prezzo di mercato · 0% di premio · scegli importo e metodi';

  @override
  String get presetCustomTitle => 'Personalizzato';

  @override
  String get presetCustomSubtitle =>
      'Tutti i campi — importo, intervallo, metodi, premio, prezzo fisso o di mercato';

  @override
  String expressPresetSubtitle(String details) {
    return 'Come il tuo ultimo ordine riuscito — $details';
  }

  @override
  String expressPremiumSuffix(String premium) {
    return '$premium% di premio';
  }

  @override
  String get paymentMethodsLabel => 'Metodi di pagamento';

  @override
  String get addPaymentMethod => 'Aggiungi metodo di pagamento';

  @override
  String get customPaymentMethodHint => 'Metodo di pagamento personalizzato...';

  @override
  String get customMethodAppendedNote =>
      'Il metodo personalizzato verrà aggiunto alla selezione';

  @override
  String get selectPaymentMethodsTitle => 'Seleziona i metodi di pagamento';

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
}

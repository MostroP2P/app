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
      'Per quanto tempo un ordine in attesa rimane aperto prima di scadere automaticamente se non viene trovato un prendere.';

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
}

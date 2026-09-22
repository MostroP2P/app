// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get appName => 'Mostro';

  @override
  String get loading => 'Chargement…';

  @override
  String get error => 'Erreur';

  @override
  String get actionFailedAnnouncement => 'Action échouée';

  @override
  String get cancel => 'Annuler';

  @override
  String get confirm => 'Confirmer';

  @override
  String get done => 'Terminé';

  @override
  String get skip => 'Passer';

  @override
  String get chatTimestampYesterday => 'Hier';

  @override
  String get disputesEmptyState => 'Vos litiges apparaîtront ici';

  @override
  String get disputeAttachFile => 'Joindre un fichier';

  @override
  String get disputeWriteMessageHint => 'Écrire un message…';

  @override
  String get disputeSend => 'Envoyer';

  @override
  String get orderDispute => 'Litige de commande';

  @override
  String get disputeAdminAssigned =>
      'Un administrateur a été assigné à votre litige. Il vous contactera ici sous peu.';

  @override
  String get disputeChatClosed => 'Ce litige a été résolu. Le chat est fermé.';

  @override
  String get messageCopied => 'Copié';

  @override
  String get disputeLoadError =>
      'Impossible de charger les litiges. Veuillez réessayer.';

  @override
  String get disputeMessagingComingSoon =>
      'Messagerie de litige bientôt disponible';

  @override
  String get disputeAttachmentsComingSoon =>
      'Pièces jointes bientôt disponibles';

  @override
  String get disputeNotFound => 'Litige introuvable.';

  @override
  String get disputeNotFoundForOrder =>
      'Aucun litige trouvé pour cette commande.';

  @override
  String get disputeResolved => 'Résolu';

  @override
  String get disputeSuccessfullyCompleted => 'Complété avec succès';

  @override
  String get disputeCoopCancelMessage =>
      'La commande a été annulée coopérativement. Aucun fonds n\'a été transféré.';

  @override
  String disputeWithBuyer(String handle) {
    return 'Litige avec l\'Acheteur : $handle';
  }

  @override
  String disputeWithSeller(String handle) {
    return 'Litige avec le Vendeur : $handle';
  }

  @override
  String orderLabel(String orderId) {
    return 'Commande $orderId';
  }

  @override
  String get disputeInitiated => 'Initié';

  @override
  String get disputeInProgress => 'En cours';

  @override
  String get disputeStatusClosed => 'Fermé';

  @override
  String get disputeLostFundsToBuyer =>
      'L\'administrateur a réglé le litige en faveur de l\'acheteur. Les sats ont été libérés à l\'acheteur.';

  @override
  String get disputeLostFundsToSeller =>
      'L\'administrateur a annulé la commande et retourné les sats au vendeur. Vous n\'avez pas reçu les sats.';

  @override
  String get walkthroughSlideOneTitle =>
      'Échangez du Bitcoin librement — sans KYC';

  @override
  String get walkthroughSlideOneBody =>
      'Mostro est un exchange pair-à-pair qui vous permet d\'échanger du Bitcoin contre n\'importe quelle devise et méthode de paiement — sans KYC et sans avoir à communiquer vos données à qui que ce soit. Il est construit sur Nostr, ce qui le rend résistant à la censure. Personne ne peut vous empêcher de trader.';

  @override
  String get walkthroughSlideTwoTitle => 'Confidentialité par défaut';

  @override
  String get walkthroughSlideTwoBody =>
      'Mostro génère une nouvelle identité pour chaque échange, de sorte que vos transactions ne peuvent pas être liées. Vous pouvez également décider du niveau de confidentialité souhaité :\n• Mode réputation – Permet aux autres de voir vos échanges réussis et votre niveau de confiance.\n• Mode confidentialité totale – Aucune réputation n\'est construite, mais votre activité est totalement anonyme.\nChangez de mode à tout moment depuis l\'écran Compte, où vous devriez également sauvegarder vos mots secrets — ils sont le seul moyen de récupérer votre compte.';

  @override
  String get walkthroughSlideThreeTitle => 'Sécurité à chaque étape';

  @override
  String get walkthroughSlideThreeBody =>
      'Mostro utilise les Hold Invoices (factures retenues) : les sats restent dans le portefeuille du vendeur jusqu\'à la fin de l\'échange. Cela protège les deux parties. L\'application est également conçue pour être intuitive et facile à utiliser pour tous les types d\'utilisateurs.';

  @override
  String get walkthroughSlideFourTitle => 'Chat entièrement chiffré';

  @override
  String get walkthroughSlideFourBody =>
      'Chaque transaction dispose de son propre chat privé, chiffré de bout en bout. Seuls les deux utilisateurs impliqués peuvent le lire. En cas de litige, vous pouvez donner la clé partagée à un administrateur pour l\'aider à résoudre le problème.';

  @override
  String get walkthroughSlideFiveTitle => 'Prenez une offre';

  @override
  String get walkthroughSlideFiveBody =>
      'Parcourez le carnet d\'ordres, choisissez une offre qui vous convient et suivez le déroulement de la transaction étape par étape. Vous pourrez consulter le profil de l\'autre utilisateur, chatter en toute sécurité et finaliser l\'échange facilement.';

  @override
  String get walkthroughSlideSixTitle =>
      'Vous ne trouvez pas ce qu\'il vous faut ?';

  @override
  String get walkthroughSlideSixBody =>
      'Vous pouvez également créer votre propre offre et attendre que quelqu\'un la prenne. Définissez le montant et la méthode de paiement souhaitée — Mostro s\'occupe du reste.';

  @override
  String get tabBuyBtc => 'Acheter BTC';

  @override
  String get tabSellBtc => 'Vendre BTC';

  @override
  String get filterButtonLabel => 'Filtrer';

  @override
  String get noOrdersAvailable => 'Aucun ordre disponible';

  @override
  String get justNow => 'à l\'instant';

  @override
  String minutesAgo(int m) {
    return 'il y a ${m}m';
  }

  @override
  String hoursAgo(int h) {
    return 'il y a ${h}h';
  }

  @override
  String daysAgo(int d) {
    return 'il y a ${d}j';
  }

  @override
  String get invoiceRejected =>
      'Le nœud a refusé cette facture. Vérifiez son montant et son expiration et ajoutez-en une nouvelle.';

  @override
  String get invoiceCopied => 'Facture copiée';

  @override
  String get submitButtonLabel => 'Soumettre';

  @override
  String get orderAlreadyTaken => 'Cet ordre a déjà été pris';

  @override
  String get nodeProtocolUnsupported =>
      'Ce nœud Mostro utilise une version du protocole que cette application ne prend pas en charge. Choisissez un autre nœud dans les Paramètres ou vérifiez si une mise à jour de l\'application est disponible';

  @override
  String get nodeCapabilitiesUnknown =>
      'Vérification en cours des capacités du nœud Mostro sélectionné. Réessayez dans un instant';

  @override
  String get mostroMaintenanceMode =>
      'Le nœud Mostro auquel vous êtes connecté est en maintenance. Réessayez plus tard ou connectez-vous à un autre nœud Mostro dans les Paramètres';

  @override
  String get storageUnavailable =>
      'L\'application ne peut pas créer ni prendre d\'ordres tant que sa base de données locale est indisponible. Redémarrez l\'application et réessayez';

  @override
  String get orderIdCopied => 'ID d\'ordre copié';

  @override
  String get comingSoonMessage => 'Bientôt disponible';

  @override
  String get tradeStatusActive => 'Actif';

  @override
  String get tradeStatusCompleted => 'Terminé';

  @override
  String get tradeStatusCancelled => 'Annulé';

  @override
  String get tradeStatusDisputed => 'En litige';

  @override
  String get accountScreenTitle => 'Compte';

  @override
  String get secretWordsTitle => 'Mots secrets';

  @override
  String get privacyCardTitle => 'Confidentialité';

  @override
  String get reputationMode => 'Mode Réputation';

  @override
  String get reputationModeSubtitle =>
      'Vos échanges comptent pour votre réputation publique';

  @override
  String get fullPrivacyMode => 'Mode Confidentialité Totale';

  @override
  String get fullPrivacyModeSubtitle =>
      'Chaque échange utilise une nouvelle identité, sans réputation';

  @override
  String get generateNewUserButton => 'Générer un nouvel utilisateur';

  @override
  String get importMostroUserButton => 'Importer un utilisateur Mostro';

  @override
  String get generateNewUserDialogTitle => 'Générer un nouvel utilisateur ?';

  @override
  String get generateNewUserDialogContent =>
      'Cela créera une toute nouvelle identité. Vos mots secrets actuels ne fonctionneront plus — assurez-vous de les avoir sauvegardés avant de continuer.';

  @override
  String get continueButtonLabel => 'Continuer';

  @override
  String get importMnemonicDialogTitle => 'Importer le mnémonique';

  @override
  String get importMnemonicHintText => 'Entrez votre phrase de 12 ou 24 mots…';

  @override
  String get importButtonLabel => 'Importer';

  @override
  String get refreshUserDialogTitle => 'Actualiser l\'utilisateur ?';

  @override
  String get refreshUserDialogContent =>
      'Cela va récupérer à nouveau vos transactions et ordres depuis l\'instance Mostro. Utilisez cette option si vous pensez que vos données sont désynchronisées ou si des ordres manquent.';

  @override
  String get hideButtonLabel => 'Masquer';

  @override
  String get showWordsButton => 'Afficher les mots';

  @override
  String get settingsScreenTitle => 'Paramètres';

  @override
  String get languageSettingTitle => 'Langue';

  @override
  String get appearanceSettingTitle => 'Apparence';

  @override
  String get appearanceDialogTitle => 'Apparence';

  @override
  String get allCurrencies => 'Toutes les devises';

  @override
  String get lightningAddressSettingTitle => 'Adresse Lightning';

  @override
  String get nwcWalletSettingTitle => 'Portefeuille NWC';

  @override
  String get relaysSettingTitle => 'Relais';

  @override
  String get pushNotificationsSettingTitle => 'Notifications push';

  @override
  String get logReportSettingTitle => 'Rapport de logs';

  @override
  String get mostroNodeSettingTitle => 'Nœud Mostro';

  @override
  String get themeDark => 'Sombre';

  @override
  String get themeLight => 'Clair';

  @override
  String get themeSystemDefault => 'Par défaut du système';

  @override
  String get lightningAddressDialogTitle => 'Adresse Lightning';

  @override
  String get lightningAddressHintText => 'utilisateur@domaine.com';

  @override
  String get invalidLightningAddressFormat =>
      'Doit être au format utilisateur@domaine';

  @override
  String get clearButtonLabel => 'Effacer';

  @override
  String get saveButtonLabel => 'Enregistrer';

  @override
  String get scanQrCodeTitle => 'Scanner le code QR';

  @override
  String get selectLanguageTitle => 'Sélectionner la langue';

  @override
  String get selectCurrencyDialogTitle => 'Sélectionner la devise';

  @override
  String get addRelayDialogTitle => 'Ajouter un relais';

  @override
  String get addButtonLabel => 'Ajouter';

  @override
  String get relayHintText => 'wss://relay.example.com';

  @override
  String get relayErrorMustStartWithWss => 'Doit commencer par wss://';

  @override
  String get relayErrorUrlTooShort => 'L\'URL est trop courte';

  @override
  String get relayErrorDuplicate => 'Le relais est déjà dans la liste';

  @override
  String get pasteQrCodeHeading => 'Coller le contenu du QR code';

  @override
  String get pasteButtonLabel => 'Coller';

  @override
  String get clipboardEmptyError => 'Le presse-papiers est vide';

  @override
  String get enterValueError => 'Veuillez entrer une valeur';

  @override
  String get trustedBadgeLabel => 'De confiance';

  @override
  String get confirmButtonLabel => 'Confirmer';

  @override
  String get selectMostroNode => 'Choisir un nœud';

  @override
  String get addCustomNode => 'Ajouter votre propre nœud';

  @override
  String get nodePubkeyFieldLabel => 'Clé publique';

  @override
  String get nodePubkeyFieldHint => 'Hex de 64 caractères ou npub…';

  @override
  String get nodeNameOptionalLabel => 'Nom (facultatif)';

  @override
  String get invalidPubkeyFormat =>
      'Entrez une clé publique valide (hex de 64 caractères ou npub)';

  @override
  String get privateKeyNotAllowed =>
      'Ceci est une clé privée — ne la partagez jamais. Entrez la clé publique du nœud';

  @override
  String get nodeAlreadyExists => 'Ce nœud est déjà dans la liste';

  @override
  String get nodeAddedSuccess => 'Nœud ajouté';

  @override
  String nodeSwitchedSuccess(String nodeName) {
    return 'Vous utilisez maintenant $nodeName';
  }

  @override
  String get errorSwitchingNode => 'Échec du changement de nœud';

  @override
  String get cannotRemoveActiveNode =>
      'Le nœud actif ne peut pas être supprimé — passez d\'abord à un autre nœud';

  @override
  String get deleteCustomNodeTitle => 'Supprimer le nœud';

  @override
  String get deleteCustomNodeMessage =>
      'Supprimer ce nœud personnalisé de votre liste ?';

  @override
  String get deleteCustomNodeConfirm => 'Supprimer';

  @override
  String get nodeRemovedSuccess => 'Nœud supprimé';

  @override
  String get nodeStorageUnavailable =>
      'La base de données locale n\'est pas prête. Redémarrez l\'application et réessayez';

  @override
  String nodeSelectorSubtitle(String code) {
    return 'Ordres et devises en $code, votre devise';
  }

  @override
  String get nodeSelectorSubtitleNoCurrency => 'Ordres ouverts sur chaque nœud';

  @override
  String nodeMissingCurrencyChip(String code) {
    return 'SANS $code';
  }

  @override
  String get nodeOrdersNowLabel => 'ordres en cours';

  @override
  String get nodeNoOrdersLabel => 'aucun ordre';

  @override
  String nodeOrdersInCurrency(int count, String code) {
    return '· $count en $code';
  }

  @override
  String get nodeFeeLabel => 'commission';

  @override
  String get nodeFeeTooltip =>
      'Mostro répartit la commission entre les deux parties.';

  @override
  String get nodePerTradeLabel => 'par opération';

  @override
  String get nodeCustodyLightning => 'Garde Lightning';

  @override
  String nodeCustodyCashu(String mint) {
    return 'Garde Cashu · $mint';
  }

  @override
  String get nodeCustodyUnknown => 'Garde —';

  @override
  String nodeBondPct(String pct) {
    return 'Caution $pct%';
  }

  @override
  String get nodeBondNone => 'Sans caution';

  @override
  String nodeStatusOnline(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ordres',
      one: '1 ordre',
    );
    return 'En ligne · $_temp0';
  }

  @override
  String get nodeStatusNoUsefulOrders => 'Aucun ordre dans vos devises';

  @override
  String nodeStatusUnreachable(String ago) {
    return 'Ne répond pas · dernier signal $ago';
  }

  @override
  String get nodeStatusUnreachableNoSignal => 'Ne répond pas';

  @override
  String get nodeDisclaimerShort =>
      'Chaque nœud est exploité par un tiers indépendant. Mostro ne répond ni de sa conduite ni de vos opérations.';

  @override
  String get nodeVerifyKeyWarning =>
      'Vérifiez la clé auprès de l\'opérateur. Un faux nœud peut voir vos ordres.';

  @override
  String get nodeInvalidPubkeyShort => 'Ce n\'est pas une clé publique valide.';

  @override
  String get nodeNameFieldHint => 'Mostro local';

  @override
  String get nodePubkeyCopied => 'Clé copiée';

  @override
  String get nodeNotSelectableOffline => 'Ce nœud ne répond pas';

  @override
  String get nodeStatsLoading => 'Chargement des données du nœud';

  @override
  String get nodeSwitchConfirmTitle => 'Changer de nœud ?';

  @override
  String nodeSwitchConfirmBody(String currentNode, String newNode) {
    return 'Vous avez une opération en cours sur $currentNode. Elle y reste ; le carnet affichera désormais $newNode.';
  }

  @override
  String get nodeSwitchConfirmAction => 'Changer de nœud';

  @override
  String get nodeTradesCheckFailed =>
      'Impossible de vérifier vos opérations. Réessayez.';

  @override
  String get notificationsScreenTitle => 'Notifications';

  @override
  String get markAllAsReadMenuItem => 'Tout marquer comme lu';

  @override
  String get clearAllMenuItem => 'Tout effacer';

  @override
  String get youMustBackUpYourAccount => 'Vous devez sauvegarder votre compte';

  @override
  String get tapToViewAndSaveSecretWords =>
      'Appuyez pour afficher et sauvegarder vos mots secrets.';

  @override
  String get noNotifications => 'Aucune notification';

  @override
  String get markAsRead => 'Marquer comme lu';

  @override
  String get deleteNotificationLabel => 'Supprimer';

  @override
  String get rateScreenHeader => 'NOTER';

  @override
  String get successfulOrder => 'Ordre réussi';

  @override
  String get closeRatingButton => 'FERMER';

  @override
  String get aboutScreenTitle => 'À propos';

  @override
  String get linkCopiedToClipboard => 'Lien copié dans le presse-papiers';

  @override
  String get pubkeyLabel => 'Clé publique';

  @override
  String get relaysLabel => 'Relais';

  @override
  String get footerTagline => 'Open-source. Non-custodial. Privé.';

  @override
  String get drawerTitle => 'Mostro';

  @override
  String get drawerTagline => 'Échange P2P';

  @override
  String get drawerStageBadge => 'Alpha';

  @override
  String drawerVersion(String version) {
    return 'Version $version';
  }

  @override
  String get drawerAccountMenuItem => 'Compte';

  @override
  String get drawerSettingsMenuItem => 'Paramètres';

  @override
  String get drawerAboutMenuItem => 'À propos';

  @override
  String get navOrderBook => 'Carnet d\'ordres';

  @override
  String get navMyTrades => 'Mes transactions';

  @override
  String get navChat => 'Chat';

  @override
  String get loadingOrders => 'Chargement des ordres…';

  @override
  String get errorLoadingOrders =>
      'Impossible de charger les ordres. Vérifiez votre connexion.';

  @override
  String get retry => 'Réessayer';

  @override
  String disableRelayLabel(String url) {
    return 'Désactiver le relais $url';
  }

  @override
  String enableRelayLabel(String url) {
    return 'Activer le relais $url';
  }

  @override
  String get removeRelayTooltip => 'Supprimer le relais';

  @override
  String get relayAddFailed => 'Échec de l\'ajout du relais';

  @override
  String get relayRemoveFailed => 'Échec de la suppression du relais';

  @override
  String get backupRitualSecondFailureMessage =>
      'C\'est encore incorrect. Veuillez vérifier et sauvegarder vos mots secrets, puis recommencer la vérification depuis le début.';

  @override
  String get cancelTradeDialogTitle => 'Annuler l\'échange ?';

  @override
  String get cancelTradeDialogContent =>
      'Annulation coopérative demandée. L\'autre partie doit également accepter pour que l\'échange soit entièrement annulé.';

  @override
  String get cancelTradeDialogContentNotStarted =>
      'L\'échange n\'a pas encore commencé, il est donc annulé immédiatement. L\'autre partie n\'a pas besoin d\'accepter.';

  @override
  String get cancelTradeDialogContentMaybeStarted =>
      'Si l\'échange n\'a pas encore commencé, il est annulé immédiatement. S\'il a déjà commencé, l\'autre partie doit également accepter.';

  @override
  String get noButtonLabel => 'Non';

  @override
  String get yesButtonLabel => 'Oui';

  @override
  String get yesCancelButtonLabel => 'Oui, annuler';

  @override
  String get cancelRequestSent => 'Demande d\'annulation envoyée';

  @override
  String get cancelRequestFailed =>
      'Échec de l\'annulation. Veuillez réessayer.';

  @override
  String get tradeCardCancelRequestedByMeTitle => 'Annulation demandée';

  @override
  String get tradeCardCancelRequestedByMeMessage =>
      'Vous avez demandé l\'annulation de cet échange. Il reste ouvert jusqu\'à ce que l\'autre partie annule aussi. Sans réponse de sa part, vous pouvez ouvrir un litige.';

  @override
  String get tradeCardCancelRequestedByPeerTitle =>
      'L\'autre partie veut annuler';

  @override
  String get tradeCardCancelRequestedByPeerMessage =>
      'Elle a demandé l\'annulation de cet échange. Acceptez pour y mettre fin sans mouvement de fonds, ou poursuivez l\'échange.';

  @override
  String get tradeCancelRequestedByMeNotice =>
      'Vous avez demandé l\'annulation de cet échange. Il reste ouvert jusqu\'à ce que l\'autre partie annule aussi. Sans réponse de sa part, vous pouvez ouvrir un litige.';

  @override
  String get tradeCancelRequestedByPeerNotice =>
      'L\'autre partie a demandé l\'annulation de cet échange. Acceptez pour y mettre fin sans mouvement de fonds, ou poursuivez l\'échange.';

  @override
  String get acceptCancelButton => 'Accepter l\'annulation';

  @override
  String get cancelTradeDialogContentAccept =>
      'L\'autre partie a demandé l\'annulation. Annuler maintenant met fin à l\'échange pour vous deux, sans mouvement de fonds.';

  @override
  String get fiatSentFailed =>
      'Échec de la confirmation du paiement fiat. Veuillez réessayer.';

  @override
  String get releaseFailed => 'Échec de la libération. Veuillez réessayer.';

  @override
  String get cancelTradeButton => 'Annuler l\'échange';

  @override
  String get payHoldInvoiceButton => 'Payer la facture hold';

  @override
  String get openDisputeButton => 'Ouvrir un litige';

  @override
  String get releaseSatsButton => 'Libérer les sats';

  @override
  String get confirmReleaseSatsButton => 'Confirmer et libérer les sats';

  @override
  String get shareOrderButton => 'Partager l\'ordre';

  @override
  String get orderPillYouAreSelling => 'VOUS VENDEZ';

  @override
  String get orderPillYouAreBuying => 'VOUS ACHETEZ';

  @override
  String get myOrderSellTitle => 'Ton ordre de vente';

  @override
  String get myOrderBuyTitle => 'Ton ordre d\'achat';

  @override
  String get cancelOrderFailed =>
      'Échec de l\'annulation de la commande. Veuillez réessayer.';

  @override
  String get closeButtonLabel => 'Fermer';

  @override
  String get copyButtonLabel => 'Copier';

  @override
  String get orderStatusWaitingForTaker => 'En attente d\'un preneur';

  @override
  String get orderStatusInProgress => 'En cours';

  @override
  String get orderStatusExpired => 'Expirée';

  @override
  String get copyOrderIdTooltip => 'Copier l\'ID de la commande';

  @override
  String get orderNotFoundTitle => 'Commande introuvable';

  @override
  String get orderNotFoundMessage => 'Cette commande n\'est plus disponible.';

  @override
  String get orderCancelledSuccess => 'Commande annulée avec succès.';

  @override
  String get aboutDocumentationTitle => 'Documentation';

  @override
  String get aboutMostroNodeTitle => 'Nœud Mostro';

  @override
  String get aboutVersionLabel => 'Version';

  @override
  String get aboutCommitHashLabel => 'Hash du commit';

  @override
  String get aboutLicenseLabel => 'Licence';

  @override
  String get aboutLicenseName => 'AGPLv3+';

  @override
  String get aboutGithubRepoName => 'MostroP2P/app';

  @override
  String get aboutCopiedToClipboard => 'Copié dans le presse-papiers';

  @override
  String get aboutLicenseDialogTitle =>
      'Licence publique générale Affero GNU v3';

  @override
  String get aboutNodeLoadingText => 'Chargement des informations du nœud…';

  @override
  String get aboutNodeUnavailable => 'Informations du nœud indisponibles';

  @override
  String get aboutNodeRetry => 'Réessayer';

  @override
  String get aboutLightningNetworkSection => 'Réseau Lightning';

  @override
  String get aboutFiatCurrenciesLabel => 'Devises fiat';

  @override
  String get aboutMostroVersionLabel => 'Version Mostro';

  @override
  String get aboutMostroCommitLabel => 'Commit Mostro';

  @override
  String get aboutHoldInvoiceExpLabel => 'Expiration de la hold invoice';

  @override
  String get aboutHoldInvoiceCltvLabel => 'CLTV de la hold invoice';

  @override
  String get aboutInvoiceExpWindowLabel => 'Fenêtre d\'expiration de facture';

  @override
  String get aboutProofOfWorkLabel => 'Preuve de travail';

  @override
  String get aboutMaxOrdersPerResponseLabel => 'Max commandes/réponse';

  @override
  String get aboutLndVersionLabel => 'Version LND';

  @override
  String get aboutSupportedChainsLabel => 'Chaînes supportées';

  @override
  String get aboutSupportedNetworksLabel => 'Réseaux supportés';

  @override
  String get aboutSatoshisSuffix => 'Satoshis';

  @override
  String get aboutBlocksSuffix => 'blocs';

  @override
  String get aboutFiatCurrenciesAll => 'Toutes';

  @override
  String get aboutAntiAbuseBondSection => 'Caution anti-abus';

  @override
  String get aboutBondEnabledValue => 'Activée';

  @override
  String get aboutBondDisabledValue => 'Désactivée';

  @override
  String get aboutBondUnsupportedValue => 'Non prise en charge';

  @override
  String get aboutBondStatusLabel => 'État de la caution';

  @override
  String get aboutBondAppliesToLabel => 'S\'applique à';

  @override
  String get aboutBondAppliesToTakers => 'Preneurs';

  @override
  String get aboutBondAppliesToMakers => 'Créateurs';

  @override
  String get aboutBondAppliesToBoth => 'Créateurs et preneurs';

  @override
  String get aboutBondAmountLabel => 'Montant de la caution';

  @override
  String get aboutBondBaseAmountLabel => 'Caution minimale';

  @override
  String get aboutBondNodeShareLabel => 'Part du nœud en cas de saisie';

  @override
  String get aboutBondSlashOnTimeoutLabel => 'Saisie en cas de délai dépassé';

  @override
  String get aboutBondClaimWindowLabel => 'Délai de réclamation du paiement';

  @override
  String aboutBondClaimWindowValue(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count jours',
      one: '$count jour',
    );
    return '$_temp0';
  }

  @override
  String get openDisputeFailed =>
      'Impossible d\'ouvrir le litige. Veuillez réessayer.';

  @override
  String get openDisputeTitle => 'Ouvrir un litige';

  @override
  String get openDisputeConfirmation =>
      'Êtes-vous sûr de vouloir ouvrir un litige ? Cela transmet l\'échange à un administrateur et ne peut pas être annulé.';

  @override
  String get disputeAlreadyOpen =>
      'Un litige est déjà ouvert pour cet échange.';

  @override
  String get tradeNotDisputable =>
      'Un litige ne peut être ouvert qu\'une fois les fonds bloqués pour cet échange.';

  @override
  String get tradeWaitingInvoiceBuyerInstruction =>
      'Soumettez votre facture Lightning pour que le vendeur puisse bloquer les fonds.';

  @override
  String get tradeWaitingInvoiceSellerInstruction =>
      'En attente de la facture Lightning de l\'acheteur.';

  @override
  String get tradeWaitingPaymentSellerInstruction =>
      'Payez la facture hold pour bloquer les fonds et démarrer l\'échange.';

  @override
  String get tradeLoadError =>
      'Une erreur s\'est produite lors du chargement de l\'échange.';

  @override
  String get tradeWaitingForHoldInvoice => 'En attente de la facture hold...';

  @override
  String get shareButtonLabel => 'Partager';

  @override
  String get shareFailed => 'Impossible de partager la facture';

  @override
  String get waitingForPaymentConfirmation =>
      'En attente de la confirmation du paiement...';

  @override
  String get orderNoLongerActive => 'Cet ordre n\'est plus actif';

  @override
  String get tradeNoLongerYours => 'Vous ne participez plus à cet échange';

  @override
  String get sessionTimeoutMessage =>
      'Aucune réponse reçue, vérifiez votre connexion et réessayez plus tard';

  @override
  String get noIdentityFoundMessage =>
      'Aucune identité trouvée — essayez de redémarrer l\'application.';

  @override
  String get failedToLoadSecretWordsMessage =>
      'Échec du chargement des mots secrets. Veuillez réessayer.';

  @override
  String get privacyModesInfoTitle => 'Modes de confidentialité';

  @override
  String get privacyModesInfoContent =>
      'Le mode réputation permet aux autres de voir vos transactions réussies.\n\nLe mode confidentialité totale garde votre activité complètement anonyme — aucune réputation n\'est construite.';

  @override
  String get failedToGenerateIdentityMessage =>
      'Échec de la génération de l\'identité. Veuillez réessayer.';

  @override
  String get invalidMnemonicMessage =>
      'Phrase mnémonique invalide. Veuillez vérifier vos mots et réessayer.';

  @override
  String get enterValidMnemonicError =>
      'Entrez une phrase valide de 12 ou 24 mots.';

  @override
  String get orderBookRefreshedMessage => 'Carnet d\'ordres actualisé';

  @override
  String get refreshFailedMessage => 'Échec de l\'actualisation';

  @override
  String get refreshButtonLabel => 'Actualiser';

  @override
  String get okButtonLabel => 'OK';

  @override
  String get moreInformationTooltip => 'Plus d\'informations';

  @override
  String get backedUpBadgeLabel => 'Sauvegardés';

  @override
  String get backupBannerTitle => 'Sécurisez votre réputation';

  @override
  String get backupBannerSubtitle =>
      'Sauvegardez vos 12 mots — cela prend 60 secondes.';

  @override
  String get failedToSaveBackupStatusMessage =>
      'Échec de l\'enregistrement de l\'état de la sauvegarde. Veuillez réessayer.';

  @override
  String get backupRitualStep1Title => 'Étape 1 sur 3 · Notez vos mots';

  @override
  String get backupRitualStep2Title => 'Étape 2 sur 3 · Vérifier';

  @override
  String get backupRitualStep3Title => 'Étape 3 sur 3 · Terminé';

  @override
  String get backupRitualWarningTitle => 'Notez-les sur papier. ';

  @override
  String get backupRitualWarningBody =>
      'Ne les stockez pas dans des photos, des captures d\'écran ou le cloud — quiconque possède ces 12 mots peut voler votre réputation.';

  @override
  String get wordsHiddenOnLeaveNote =>
      'Ils seront masqués quand vous quitterez cet écran';

  @override
  String get wroteThemDownVerifyButton => 'Je les ai notés — vérifier';

  @override
  String get tapCorrectWordsTitle => 'Appuyez sur les mots corrects';

  @override
  String get verifyInstructionsBody =>
      'Nous en demandons 3 au hasard. Si vous les trouvez, nous savons qu\'ils sont bien notés.';

  @override
  String optionsForWordLabel(int number) {
    return 'OPTIONS POUR LE MOT #$number';
  }

  @override
  String get wrongPickMessage =>
      'Pas tout à fait — vérifiez votre papier et réessayez.';

  @override
  String get allWordsCorrectMessage => 'Les 3 mots sont corrects';

  @override
  String get reviewWordsButton => 'Voir les mots';

  @override
  String get accountBackedUpTitle => 'Votre compte est sauvegardé';

  @override
  String get accountBackedUpBody =>
      'Votre réputation est en sécurité. Si vous perdez un jour votre téléphone, restaurez votre compte avec vos 12 mots.';

  @override
  String wordNumberLabel(int number) {
    return 'Mot #$number';
  }

  @override
  String get backupTriggerBody =>
      'Votre réputation réside dans une clé que vous seul détenez. Si vous perdez votre téléphone, vous perdez cette réputation — ';

  @override
  String get backupTriggerBodyHighlight => 'sauvegardez-la en 60 secondes.';

  @override
  String get backupStepWriteDown => 'Notez vos 12 mots sur papier';

  @override
  String get backupStepVerifyRandom =>
      'Nous en demandons 3 au hasard pour confirmer';

  @override
  String get backupStepSecured => 'Terminé — votre compte est sécurisé';

  @override
  String get backupNowButton => 'Sauvegarder maintenant';

  @override
  String get backupLaterButton => 'Je le ferai plus tard';

  @override
  String get nwcConnectionFailedMessage =>
      'La connexion a échoué. Veuillez vérifier votre URI NWC et réessayer.';

  @override
  String get clipboardInvalidNwcUriMessage =>
      'Le presse-papiers ne contient pas d\'URI NWC valide.';

  @override
  String get scanQrButtonLabel => 'Scanner QR';

  @override
  String get connectButtonLabel => 'Connecter';

  @override
  String get walletDisconnectedMessage => 'Portefeuille déconnecté';

  @override
  String get relayLabel => 'Relais';

  @override
  String get disconnectButtonLabel => 'Déconnecter';

  @override
  String relaysMoreSuffix(int count) {
    return '(+$count de plus)';
  }

  @override
  String get chooseNotificationEventsSubtitle =>
      'Choisissez quels événements affichent une notification dans l’app.';

  @override
  String get notifTradeUpdatesTitle => 'Mises à jour des transactions';

  @override
  String get notifTradeUpdatesSubtitle =>
      'Changements de statut de vos transactions actives';

  @override
  String get notifNewMessagesTitle => 'Nouveaux messages';

  @override
  String get notifNewMessagesSubtitle => 'Messages de votre contrepartie';

  @override
  String get notifPaymentAlertsTitle => 'Alertes de paiement';

  @override
  String get notifPaymentAlertsSubtitle =>
      'Confirmations et échecs de paiements Lightning';

  @override
  String get notifDisputeUpdatesTitle => 'Mises à jour des litiges';

  @override
  String get notifDisputeUpdatesSubtitle =>
      'Actions des administrateurs et résolutions de litiges';

  @override
  String get searchCurrenciesHint => 'Rechercher des devises…';

  @override
  String get noCurrenciesFoundMessage => 'Aucune devise trouvée';

  @override
  String get shareLogsTooltip => 'Partager les journaux';

  @override
  String get noLogsToShareTooltip => 'Aucun journal à partager';

  @override
  String get noLogEntriesMessage => 'Aucune entrée de journal';

  @override
  String get failedToShareLogsMessage => 'Échec du partage des journaux';

  @override
  String get logReportShareHeading => 'Rapport de journaux Mostro';

  @override
  String get tradeFilterAll => 'Tous';

  @override
  String get tradeFilterPending => 'En attente';

  @override
  String get tradeFilterWaitingInvoice => 'En attente de facture';

  @override
  String get tradeFilterWaitingPayment => 'En attente de paiement';

  @override
  String get tradeFilterActive => 'Actif';

  @override
  String get tradeFilterFiatSent => 'Fiat envoyé';

  @override
  String get tradeFilterSuccess => 'Réussi';

  @override
  String get tradeFilterCanceled => 'Annulé';

  @override
  String get tradeFilterDispute => 'Litige';

  @override
  String get menuTooltip => 'Menu';

  @override
  String get noTradesTitle => 'Aucune transaction';

  @override
  String get noTradesSubtitle =>
      'Vos transactions actives et terminées apparaîtront ici.';

  @override
  String get couldNotLoadTradesMessage =>
      'Impossible de charger les transactions';

  @override
  String get sellingBitcoin => 'Vente de Bitcoin';

  @override
  String get buyingBitcoin => 'Achat de Bitcoin';

  @override
  String get tradeInstructionActiveBuyer =>
      'Une fois l\'argent envoyé, marquez-le ci-dessous. N\'ouvrez un litige que si le vendeur cesse de répondre.';

  @override
  String get tradeInstructionFiatSentBuyer =>
      'Paiement fiat marqué comme envoyé. En attente que le vendeur confirme la réception et libère vos sats.';

  @override
  String get tradeInstructionActiveSeller =>
      'Contactez l\'acheteur avec les instructions de paiement via le chat ci-dessus.';

  @override
  String get tradeInstructionFiatSentSeller =>
      'L\'acheteur a confirmé avoir envoyé le paiement fiat. Une fois la réception vérifiée, libérez les sats.';

  @override
  String get tradeInstructionDisputed =>
      'Un médiateur de litige a été assigné. Il vous contactera via l\'application.';

  @override
  String get tradeInstructionPending =>
      'Votre ordre est publié et attend qu\'une contrepartie le prenne. Vous pouvez l\'annuler à tout moment.';

  @override
  String get tradeInstructionCancelled =>
      'Cette transaction a été annulée. Aucun fonds n\'a été échangé.';

  @override
  String get tradeInstructionInProgress => 'Transaction en cours.';

  @override
  String get theAgreedAmount => 'le montant convenu';

  @override
  String get tradeHeadlinePending =>
      'En attente que quelqu\'un prenne votre ordre';

  @override
  String get tradeHeadlineInProgress =>
      'L\'échange est en cours de préparation';

  @override
  String get tradeHeadlineWaitingInvoiceBuyer =>
      'Partagez une facture Lightning pour recevoir vos sats';

  @override
  String get tradeHeadlineWaitingInvoiceSeller =>
      'En attente que l\'acheteur partage une facture';

  @override
  String get tradeHeadlineWaitingPaymentBuyer =>
      'En attente que le vendeur verrouille les sats';

  @override
  String get tradeHeadlineWaitingPaymentSeller =>
      'Payez la facture de retenue pour verrouiller les sats';

  @override
  String tradeHeadlineActiveBuyer(String amount) {
    return 'Envoyez $amount au vendeur';
  }

  @override
  String tradeHeadlineActiveSeller(String amount) {
    return 'En attente que l\'acheteur envoie $amount';
  }

  @override
  String get tradeHeadlineFiatSentBuyer =>
      'En attente que le vendeur libère vos sats';

  @override
  String tradeHeadlineFiatSentSeller(String amount) {
    return 'Confirmez que vous avez reçu $amount';
  }

  @override
  String get tradeHeadlineDisputed => 'Litige en cours';

  @override
  String get tradeHeadlineCancelled => 'Ordre annulé';

  @override
  String get tradeHeadlineLoading => 'Chargement de la transaction…';

  @override
  String get tradeTimerPendingConsequence =>
      'S\'il expire, l\'ordre est retiré du carnet. Cela n\'affectera pas votre réputation.';

  @override
  String get tradeTimerWaitingInvoiceConsequence =>
      'S\'il expire, la transaction est annulée et l\'ordre retourne au carnet.';

  @override
  String get tradeStepOrderTaken => 'Ordre pris';

  @override
  String get tradeStepInvoiceBuyer => 'Le vendeur bloque les sats';

  @override
  String get tradeStepInvoiceSeller => 'Vous bloquez les sats';

  @override
  String get tradeStepFiatBuyer => 'Vous envoyez le paiement fiat';

  @override
  String get tradeStepFiatSeller => 'L\'acheteur envoie le paiement fiat';

  @override
  String get tradeStepReleaseBuyer => 'Le vendeur libère vos sats';

  @override
  String get tradeStepReleaseSeller => 'Vous confirmez et libérez les sats';

  @override
  String get tradeStepRate => 'Vous notez l\'opération';

  @override
  String tradeCreatedAtLabel(String date) {
    return 'créé $date';
  }

  @override
  String stepIndicator(int current, int total) {
    return 'ÉTAPE $current SUR $total';
  }

  @override
  String get addLightningInvoiceButton => 'Ajouter une facture Lightning';

  @override
  String get viewDisputeButton => 'Voir le litige';

  @override
  String get yourTradeTimelineTitle => 'VOTRE TRANSACTION';

  @override
  String get messageSendFailed =>
      'Échec de l\'envoi du message. Veuillez réessayer.';

  @override
  String get invalidTradeId => 'ID de transaction invalide';

  @override
  String get selectForDetailsHint => 'Sélectionnez ℹ ou 👤\npour les détails';

  @override
  String noMessagesYet(String handle) {
    return 'Pas encore de messages.\nDites bonjour à $handle !';
  }

  @override
  String get exchangeInfoTooltip => 'Infos sur l\'échange';

  @override
  String get userInfoTooltip => 'Infos utilisateur';

  @override
  String chattingWith(String handle) {
    return 'Vous discutez avec $handle';
  }

  @override
  String get unknownPeerHandle => 'Inconnu';

  @override
  String get messagesTab => 'Messages';

  @override
  String get disputesTab => 'Litiges';

  @override
  String get tradeInformationTitle => 'Informations sur la transaction';

  @override
  String get orderIdLabel => 'ID de l\'ordre';

  @override
  String get fiatAmountLabel => 'Montant fiat';

  @override
  String get satsAmountLabel => 'Montant en sats';

  @override
  String get statusLabel => 'Statut';

  @override
  String get paymentMethodLabel => 'Moyen de paiement';

  @override
  String get createdLabel => 'Créé';

  @override
  String get tradeDetailsPlaceholder =>
      'Détails disponibles lorsque le fournisseur de transactions sera prêt (Phase 10+)';

  @override
  String get userInformationTitle => 'Informations utilisateur';

  @override
  String get peerPublicKeyLabel => 'Clé publique du pair';

  @override
  String get yourSharedKeyLabel => 'Votre clé partagée';

  @override
  String get sharedKeyPlaceholder =>
      'Disponible après l\'intégration du pont (Phase 10+)';

  @override
  String get sharedKeySafetyNote =>
      'Conservez votre clé partagée en sécurité — elle est nécessaire pour la résolution des litiges';

  @override
  String get attachmentLabel => '[Pièce jointe]';

  @override
  String get downloadTooltip => 'Télécharger';

  @override
  String get fileDownloadPlaceholder =>
      'Téléchargement de fichiers disponible en Phase 10+';

  @override
  String get fileTypeVideo => 'Vidéo';

  @override
  String get fileTypeImage => 'Image';

  @override
  String get fileTypeArchive => 'Archive';

  @override
  String get fileTypeFile => 'Fichier';

  @override
  String get tapToDownload => 'Appuyez pour télécharger';

  @override
  String get imageDownloadPlaceholder =>
      'Téléchargement d\'images disponible en Phase 10+';

  @override
  String buyingSatsAmount(String sats) {
    return 'Achat de $sats sats';
  }

  @override
  String sellingSatsAmount(String sats) {
    return 'Vente de $sats sats';
  }

  @override
  String get viewOrderLink => 'Voir l\'ordre';

  @override
  String timeLeftLabel(String time) {
    return '$time restant';
  }

  @override
  String get invoiceNoLongerExpected =>
      'Cet ordre n\'attend plus de facture. Mise à jour de son statut…';

  @override
  String get invoiceSubmitInFlight =>
      'Une facture pour cet ordre est déjà en cours d\'envoi. Attendez la réponse.';

  @override
  String get waitingForTradeAmount =>
      'En attente du montant de la transaction — veuillez réessayer sous peu.';

  @override
  String get fetchingTradeAmount =>
      'Récupération du montant de la transaction…';

  @override
  String get enterInvoiceManually => 'Saisir la facture manuellement';

  @override
  String get submitButton => 'Envoyer';

  @override
  String get buyerReputation => 'Réputation de l\'acheteur';

  @override
  String get sellerReputation => 'Réputation du vendeur';

  @override
  String get ratingStatLabel => 'note';

  @override
  String get tradesStatLabel => 'transactions';

  @override
  String get daysActiveStatLabel => 'jours actifs';

  @override
  String timeRemainingLabel(String time) {
    return 'Temps restant : $time';
  }

  @override
  String orderAmountOutOfRange(int min, int max) {
    return 'Le montant doit être compris entre $min et $max sats pour ce nœud Mostro';
  }

  @override
  String orderAmountOutOfRangeFiat(int min, int max, String currency) {
    return 'Le montant doit être compris entre $min et $max $currency pour ce nœud Mostro';
  }

  @override
  String get priceTypeMarket => 'Marché';

  @override
  String get priceTypeFixed => 'Fixe';

  @override
  String get priceTypeInfoTooltip => 'Infos sur le type de prix';

  @override
  String get premiumSectionLabel => 'Prime';

  @override
  String get fixedPriceRangeNotAvailable =>
      'Le prix fixe n\'est pas disponible pour les ordres à fourchette. Désactivez la fourchette pour utiliser un prix fixe.';

  @override
  String get priceTypesDialogTitle => 'Types de prix';

  @override
  String get priceTypesDialogContent =>
      'Prix du marché : le prix de votre ordre suit le taux du marché avec un pourcentage de prime/remise appliqué.\n\nPrix fixe : vous définissez un prix exact en satoshis.';

  @override
  String get newOrderTitle => 'Nouvel ordre';

  @override
  String get amountSectionSell => 'Combien vous vendez';

  @override
  String get amountSectionBuy => 'Combien vous achetez';

  @override
  String get amountModeSingle => 'Unique';

  @override
  String get amountModeRange => 'Plage';

  @override
  String get amountMinLabel => 'Minimum';

  @override
  String get amountMaxLabel => 'Maximum';

  @override
  String paymentMethodsChosenCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count choisis',
      one: '1 choisi',
      zero: 'aucun choisi',
    );
    return '$_temp0';
  }

  @override
  String get paymentMethodAdd => 'Ajouter';

  @override
  String get paymentMethodSearchHint => 'Rechercher un moyen';

  @override
  String get customPaymentMethodLabel => 'Moyen de paiement personnalisé';

  @override
  String get priceSectionTitle => 'Prix';

  @override
  String premiumSellAbove(String premium) {
    return 'Vous vendez $premium% au-dessus du prix du marché';
  }

  @override
  String premiumSellBelow(String premium) {
    return 'Vous vendez $premium% sous le marché';
  }

  @override
  String premiumBuyBelow(String premium) {
    return 'Vous payez $premium% de moins que le marché';
  }

  @override
  String premiumBuyAbove(String premium) {
    return 'Vous payez $premium% de plus';
  }

  @override
  String get premiumExactMarket => 'Prix du marché exact';

  @override
  String get fixedPriceNote =>
      'À prix fixe, l\'ordre ne suit pas le marché : le montant en sats reste tel que vous l\'écrivez.';

  @override
  String get previewHintNoAmount =>
      'Saisissez un montant et vous verrez ici à quoi ressemble l\'ordre.';

  @override
  String previewSellMarket(String amount, String premium, String active) {
    return 'Vous vendez des BTC pour $amount au prix du marché $premium$active';
  }

  @override
  String previewSellMarketExact(String amount, String active) {
    return 'Vous vendez des BTC pour $amount au prix du marché$active';
  }

  @override
  String previewBuyMarket(String amount, String premium, String active) {
    return 'Vous achetez des BTC pour $amount au prix du marché $premium$active';
  }

  @override
  String previewBuyMarketExact(String amount, String active) {
    return 'Vous achetez des BTC pour $amount au prix du marché$active';
  }

  @override
  String previewSellFixed(String sats, String amount, String active) {
    return 'Vous vendez $sats pour $amount à prix fixe$active';
  }

  @override
  String previewBuyFixed(String sats, String amount, String active) {
    return 'Vous achetez $sats pour $amount à prix fixe$active';
  }

  @override
  String previewActiveSuffix(String hours) {
    return ' · actif $hours';
  }

  @override
  String get publishOrder => 'Publier l\'ordre';

  @override
  String removePaymentMethod(String method) {
    return 'Retirer $method';
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
  String get paymentMethodsLabel => 'Moyens de paiement';

  @override
  String get customPaymentMethodHint => 'Moyen de paiement personnalisé...';

  @override
  String amountRangeError(String min, String max) {
    return 'Le montant doit être entre $min et $max';
  }

  @override
  String get enterAmountTitle => 'Saisir le montant';

  @override
  String minMaxRangeLabel(String min, String max, String currency) {
    return 'Min : $min – Max : $max $currency';
  }

  @override
  String get ratingFailed => 'Échec de l\'évaluation. Veuillez réessayer.';

  @override
  String get submitUppercaseButton => 'ENVOYER';

  @override
  String selectStarTooltip(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Sélectionner $count étoiles',
      one: 'Sélectionner 1 étoile',
    );
    return '$_temp0';
  }

  @override
  String get disputeDetailsTitle => 'Détails du litige';

  @override
  String get disputeIdLabel => 'ID du litige';

  @override
  String disputeReasonLabel(String reason) {
    return 'Raison : $reason';
  }

  @override
  String get adminLabel => 'Administrateur';

  @override
  String get disputeScreenTitle => 'Litige';

  @override
  String get filtersDialogTitle => 'Filtres';

  @override
  String get resetButton => 'Réinitialiser';

  @override
  String get currencyLabel => 'Devise';

  @override
  String get ratingLabel => 'Note';

  @override
  String get applyButton => 'Appliquer';

  @override
  String get successLabel => 'Succès';

  @override
  String get copyButton => 'Copier';

  @override
  String get shareButton => 'Partager';

  @override
  String sendSatsToAddress(String sats) {
    return 'Envoyez $sats sats à :';
  }

  @override
  String get changeButton => 'Modifier';

  @override
  String get unableToOpenNotification =>
      'Impossible d\'ouvrir les détails de la notification.';

  @override
  String get reasonBestPremium => 'Meilleure prime';

  @override
  String get reasonMostReputable => 'Plus réputé';

  @override
  String get marketPriceCaption => 'Prix du marché';

  @override
  String reputationTradesLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'transactions',
      one: 'transaction',
    );
    return '$_temp0';
  }

  @override
  String reputationDaysLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'jours',
      one: 'jour',
    );
    return '$_temp0';
  }

  @override
  String get sortNewest => 'Plus récentes';

  @override
  String ordersCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ordres',
      one: '1 ordre',
    );
    return '$_temp0';
  }

  @override
  String get sortBestPremium => 'Meilleure prime';

  @override
  String get sortBestReputation => 'Meilleure réputation';

  @override
  String get sortSheetTitle => 'Trier par';

  @override
  String get orderCardPremiumCaption => 'prime';

  @override
  String orderFixedAmount(String sats) {
    return 'Montant fixe · pour $sats';
  }

  @override
  String get reputationNew => 'Nouveau';

  @override
  String get reputationNoTrades => 'aucune transaction';

  @override
  String get bottomNavBook => 'Carnet';

  @override
  String get bottomNavTrades => 'Transactions';

  @override
  String get fabDismissHint => 'Touchez à l’extérieur pour fermer';

  @override
  String get addOrderFabLabel => 'Créer un ordre';

  @override
  String get ordersEmptyHint =>
      'Les nouveaux ordres apparaissent ici dès leur publication.';

  @override
  String get ordersEmptyFilteredHint =>
      'Aucun ordre ne correspond à vos filtres.';

  @override
  String get clearFiltersButton => 'Effacer les filtres';

  @override
  String get hideEarlierEvents => 'Masquer les événements précédents';

  @override
  String viewEarlierEvents(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Voir $count événements précédents',
      one: 'Voir 1 événement précédent',
    );
    return '$_temp0';
  }

  @override
  String get goToTrade => 'Aller à la transaction';

  @override
  String get disputeWord => 'Litige';

  @override
  String get tradeWord => 'Transaction';

  @override
  String get notifFilterAll => 'Toutes';

  @override
  String get notifFilterDisputes => 'Litiges';

  @override
  String notifFilterDisputesCount(int count) {
    return 'Litiges · $count';
  }

  @override
  String get notifFilterSystem => 'Système';

  @override
  String notifFilterSystemCount(int count) {
    return 'Système · $count';
  }

  @override
  String get payingStatus => 'Paiement...';

  @override
  String get payWithWalletButton => 'Payer avec le portefeuille';

  @override
  String get generatingInvoiceNwc => 'Génération de la facture via NWC...';

  @override
  String get unableToGenerateInvoice =>
      'Impossible de générer la facture automatiquement';

  @override
  String get avatarIconLabel => 'Icône d\'avatar';

  @override
  String get disputeDescResolvedBuyerFavour =>
      'Litige résolu en faveur de l\'acheteur';

  @override
  String get disputeDescResolvedYourFavour => 'Litige résolu en votre faveur';

  @override
  String get disputeDescResolvedSellerFavour =>
      'Litige résolu en faveur du vendeur';

  @override
  String get disputeDescCooperativeCancel => 'Commande annulée coopérativement';

  @override
  String get disputeDescResolved => 'Litige résolu';

  @override
  String get disputeDescYouOpened => 'Vous avez ouvert ce litige';

  @override
  String get disputeDescCounterpartOpened =>
      'La contrepartie a ouvert ce litige';

  @override
  String get notificationsBellNoUnread =>
      'Notifications, aucune notification non lue';

  @override
  String get notificationsBellBackupActive =>
      'Notifications, rappel de sauvegarde actif';

  @override
  String notificationsBellUnread(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Notifications, $count non lues',
      one: 'Notifications, 1 non lue',
    );
    return '$_temp0';
  }

  @override
  String drawerBadgeNewCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count nouveaux',
      one: '1 nouveau',
    );
    return '$_temp0';
  }

  @override
  String get bondSlashedViewPolicy => 'Voir la politique';

  @override
  String get bondSlashedViewTrade => 'Voir l\'échange';

  @override
  String bondSlashedTradeNoticeDispute(String sats) {
    return 'Le nœud a confisqué votre dépôt de $sats sats dans ce litige.';
  }

  @override
  String bondSlashedTradeNoticeTimeout(String sats) {
    return 'Le nœud a confisqué votre dépôt de $sats sats après l\'expiration d\'une étape.';
  }

  @override
  String get bondSlashedTitle => 'Caution confisquée';

  @override
  String bondSlashedMessageTimeout(String amount, String orderId) {
    return 'Votre caution anti-abus de $amount sats pour la commande $orderId a été confisquée après l\'expiration du délai d\'attente. Le statut de votre commande est inchangé.';
  }

  @override
  String bondSlashedMessageDispute(String amount, String orderId) {
    return 'Votre caution anti-abus de $amount sats pour la commande $orderId a été confisquée après la résolution d\'un litige. Le statut de votre commande est inchangé.';
  }

  @override
  String get bondSlashedCauseTimeout => 'Délai d\'attente expiré';

  @override
  String get bondSlashedCauseDispute => 'Résolution du litige';

  @override
  String get bondSlashedDetailOrder => 'Commande';

  @override
  String get bondSlashedDetailAmount => 'Montant de la caution';

  @override
  String get bondSlashedDetailCause => 'Cause';

  @override
  String get bondSlashedDetailFiat => 'Fiat';

  @override
  String get bondSlashedDetailPaymentMethod => 'Moyen de paiement';

  @override
  String aboutDaysValue(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count jours',
      one: '$count jour',
    );
    return '$_temp0';
  }

  @override
  String get aboutCashuEscrowSection => 'Séquestre Cashu';

  @override
  String get aboutCashuMintUrlLabel => 'Mint';

  @override
  String get aboutCashuMintNotAdvertised => 'Non annoncé';

  @override
  String get aboutCashuLocktimeLabel => 'Verrouillage du séquestre';

  @override
  String get aboutCashuSettlementMarginLabel => 'Marge de règlement';

  @override
  String get escrowModeLightning => 'Lightning';

  @override
  String get escrowModeCashu => 'Cashu';

  @override
  String get escrowModeUnknown => 'Non annoncé';

  @override
  String get settingsEscrowOverrideTitle =>
      'Backend de séquestre (développeur)';

  @override
  String get settingsEscrowOverrideSubtitle =>
      'Testez Cashu avec un nœud qui ne l\'annonce pas encore. Builds de débogage uniquement.';

  @override
  String get settingsForceCashuLabel => 'Forcer le séquestre Cashu';

  @override
  String get settingsCashuMintOverrideLabel => 'URL de mint alternative';

  @override
  String get settingsCashuMintOverrideApply => 'Appliquer';

  @override
  String get settingsCashuMintOverrideInvalid =>
      'Ce n\'est pas une URL de mint valide. Utilisez http ou https avec un hôte.';

  @override
  String settingsEscrowEffectiveMode(String mode) {
    return 'Backend effectif : $mode';
  }

  @override
  String settingsEscrowEffectiveMint(String mint) {
    return 'Mint effectif : $mint';
  }

  @override
  String get settingsEscrowCashuUnavailable =>
      'Cashu ne peut pas fonctionner sans mint : configurez-en un ci-dessous.';

  @override
  String get tradeStatusPayoutPending => 'Paiement en attente';

  @override
  String get tradeHeadlinePayoutPending =>
      'En attente du paiement à l’acheteur';

  @override
  String get tradeInstructionPayoutPending =>
      'Le vendeur a libéré les fonds en séquestre. En attente de la réussite du paiement Lightning à l’acheteur.';

  @override
  String get tradeScreenTitle => 'Votre opération';

  @override
  String get tradeChipWaiting => 'EN ATTENTE';

  @override
  String get tradeChipActive => 'ACTIVE';

  @override
  String get tradeChipYourTurn => 'À VOUS';

  @override
  String get tradeChipDispute => 'LITIGE';

  @override
  String get tradeChatLockedNote =>
      'Pas encore de chat : tant que l\'opération n\'est pas active, aucune des deux parties ne sait qui est l\'autre.';

  @override
  String get tradeChatEncrypted => 'Chat chiffré de bout en bout';

  @override
  String get tradeBodyWaitingPaymentBuyer =>
      'Le vendeur paie la facture de dépôt. Une fois les sats bloqués, ce sera à vous de payer le fiat.';

  @override
  String tradeBodyActiveSeller(String method) {
    return 'Transmettez vos coordonnées $method dans le chat ci-dessus.';
  }

  @override
  String tradeBodyActiveBuyer(String method) {
    return 'Par $method, avec les coordonnées reçues dans le chat. Une fois envoyé, indiquez-le ci-dessous.';
  }

  @override
  String tradeBodyFiatSentSeller(String method) {
    return 'L\'acheteur a marqué le paiement comme envoyé. Vérifiez votre compte $method avant de libérer.';
  }

  @override
  String get tradeReleaseIrreversible =>
      'La libération des sats est irréversible.';

  @override
  String get tradeTimerYouHave => 'Il vous reste';

  @override
  String get tradeTimerTheyHave => 'Il leur reste';

  @override
  String get tradeTimerOrderHas => 'Temps restant';

  @override
  String get tradeTimerNoteCoordinate =>
      'S\'il vous faut plus de temps, convenez-en dans le chat avant l\'expiration.';

  @override
  String get tradeRoleBuyer => 'Acheteur';

  @override
  String get tradeRoleSeller => 'Vendeur';

  @override
  String reputationTradesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count opérations',
      one: '1 opération',
    );
    return '$_temp0';
  }

  @override
  String reputationDaysOnMostro(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count jours sur Mostro',
      one: '1 jour sur Mostro',
    );
    return '$_temp0';
  }

  @override
  String get tradeFiatSentAction => 'J\'ai envoyé le paiement';

  @override
  String get tradeCloseAction => 'Fermer';

  @override
  String get tradeSendRatingAction => 'Envoyer la note';

  @override
  String get tradeCompletedTitle => 'Opération terminée';

  @override
  String tradeRatedCounterpart(String alias, String score) {
    return 'Vous avez noté $alias $score';
  }

  @override
  String get tradeIdLabel => 'ID';

  @override
  String tradeCreatedTodayLabel(String time) {
    return 'créée aujourd\'hui à $time';
  }

  @override
  String get releaseSheetTitle => 'Libérer les sats ?';

  @override
  String get releaseSheetBody =>
      'C\'est irréversible. Ne libérez que si l\'argent est déjà sur votre compte.';

  @override
  String get releaseSheetConfirm => 'Oui, libérer';

  @override
  String get releaseSheetBack => 'Retour';

  @override
  String get orderSideChipSell => 'Tu vends du BTC';

  @override
  String get orderSideChipBuy => 'Tu achètes du BTC';

  @override
  String orderDetailMarketPremium(String premium) {
    return 'Prix du marché · $premium de prime';
  }

  @override
  String myOrderWaitingNote(String ago) {
    return 'Publiée $ago. On te prévient dès que quelqu\'un la prend : tu peux fermer cet écran.';
  }

  @override
  String get orderStatusTakenWaitingInvoice =>
      'Prise · en attente de la facture';

  @override
  String get orderStatusTakenWaitingPayment => 'Prise · en attente du paiement';

  @override
  String get orderDetailCreatedLabel => 'Créée';

  @override
  String get orderDetailIdLabel => 'ID';

  @override
  String paymentMethodsMore(String first, int count) {
    return '$first +$count';
  }

  @override
  String get paymentMethodsSheetTitle => 'Moyens de paiement';

  @override
  String get cancelOrderSheetTitle => 'Annuler l\'ordre ?';

  @override
  String get cancelOrderSheetBody =>
      'Il est retiré du carnet d\'ordres et cela ne peut pas être annulé.';

  @override
  String get goBackButtonLabel => 'Retour';

  @override
  String get takeOrderYouPay => 'Tu paies';

  @override
  String get takeOrderYouReceive => 'Tu reçois';

  @override
  String get takeOrderYouSend => 'Tu envoies';

  @override
  String takeOrderSatsFrom(String sats) {
    return 'à partir de $sats';
  }

  @override
  String takeOrderMarketFooter(String premium) {
    return 'Prix du marché · $premium de prime. Le montant final est fixé à la prise.';
  }

  @override
  String takeOrderFixedFooterSeller(String sats) {
    return 'Montant fixe · le vendeur demande $sats';
  }

  @override
  String takeOrderFixedFooterBuyer(String sats) {
    return 'Montant fixe · l\'acheteur propose $sats';
  }

  @override
  String get counterpartySeller => 'Vendeur';

  @override
  String get counterpartyBuyer => 'Acheteur';

  @override
  String counterpartyTrades(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count échanges',
      one: '$count échange',
    );
    return '$_temp0';
  }

  @override
  String counterpartyDaysOnMostro(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count jours sur Mostro',
      one: '$count jour sur Mostro',
    );
    return '$_temp0';
  }

  @override
  String get takeOrderPayWithLabel => 'Tu paies avec';

  @override
  String get takeOrderPaidWithLabel => 'On te paie avec';

  @override
  String get takeOrderPublishedLabel => 'Publiée';

  @override
  String get takeOrderNoteBuyer =>
      'Quand tu la prends, le vendeur bloque les sats dans Mostro. Tu ne paies qu\'une fois qu\'ils sont bloqués.';

  @override
  String get takeOrderNoteSeller =>
      'Quand tu la prends, tu bloques les sats dans Mostro. L\'acheteur paie ensuite.';

  @override
  String get takeOrderButton => 'Prendre l\'ordre';

  @override
  String get takeOrderTaking => 'Prise en cours…';

  @override
  String get takeOrderUnavailable => 'Plus disponible';

  @override
  String get takeOrderClosed => 'Fermée';

  @override
  String get easterEggWhitepaper =>
      '31 octobre 2008 : neuf pages, la permission de personne. Joyeux Halloween.';

  @override
  String get easterEggGenesis =>
      'The Times 03/Jan/2009 Chancellor on brink of second bailout for banks';

  @override
  String get easterEggPizzaDay =>
      '22 mai 2010 : 10 000 BTC pour deux pizzas. On espère qu\'elles étaient bonnes.';

  @override
  String get settingsGroupApp => 'Application';

  @override
  String get settingsGroupPayments => 'Paiements';

  @override
  String get settingsGroupNetwork => 'Réseau';

  @override
  String get settingsGroupHelp => 'Aide';

  @override
  String get fiatCurrencySettingTitle => 'Devise fiat';

  @override
  String notificationsEnabledOfTotal(int count, int total) {
    return '$count sur $total';
  }

  @override
  String get notificationsAllOff => 'Désactivées';

  @override
  String get lightningAddressUnset => 'Non configurée';

  @override
  String get nwcWalletNotConnected => 'Non connecté';

  @override
  String relaysConnectedOfTotal(int connected, int total) {
    return '$connected sur $total connectés';
  }

  @override
  String get relaysSummaryHealthy =>
      'Vous recevez ordres et messages normalement';

  @override
  String get relaysSummaryAtRisk =>
      'Vous risquez de ne plus voir les nouveaux ordres';

  @override
  String get relayStatusConnected => 'Connecté';

  @override
  String get relayStatusOffline => 'Pas de connexion';

  @override
  String get addRelayButtonLabel => 'Ajouter un relais';

  @override
  String get relaysFootnote =>
      'Les relais transportent vos ordres et vos messages. Avec moins de deux connectés, vous risquez de ne plus voir les nouveaux ordres.';

  @override
  String get lastRelayBlockedMessage =>
      'Gardez au moins un relais actif : sans relais, vous ne pouvez ni voir ni publier d’ordres.';

  @override
  String get nwcExplainerTitle => 'Connecter votre portefeuille';

  @override
  String get nwcExplainerSubtitle => 'Avec Nostr Wallet Connect';

  @override
  String get nwcExplainerBody =>
      'Mostro encaissera et paiera les factures de vos opérations depuis ce portefeuille, sans que vous ayez à copier une facture à la main.';

  @override
  String get nwcUriFieldLabel => 'URI de connexion';

  @override
  String get nwcUriPlaceholder => 'nostr+walletconnect://…';

  @override
  String get nwcStorageFootnote =>
      'L’URI est stockée uniquement sur cet appareil et n’est jamais publiée sur Nostr.';

  @override
  String get walletConnectedMessage => 'Portefeuille connecté';

  @override
  String get nwcConnectedStatus => 'Connecté';

  @override
  String nwcBalanceSats(String sats) {
    return '$sats sats';
  }

  @override
  String get notificationsSystemDenied =>
      'Les notifications sont désactivées dans les réglages du système.';

  @override
  String get openSystemSettingsAction => 'Ouvrir les réglages';

  @override
  String get notificationsPrivacyFootnote =>
      'Les notifications ne contiennent ni montants ni contreparties. Un push passe par les serveurs de Google ou d’Apple et signale seulement qu’il y a quelque chose à voir.';

  @override
  String get pushMasterToggleTitle => 'Notifications push';

  @override
  String get pushMasterToggleSubtitle =>
      'Réveille l’app quand une mise à jour d’échange ou un message arrive. La notification elle-même ne contient rien.';

  @override
  String get pushStatusOff =>
      'Désactivées : rien n’est enregistré auprès du serveur push';

  @override
  String pushStatusCleanupPending(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Désactivées — suppression de $count inscriptions push en attente',
      one: 'Désactivées — suppression de 1 inscription push en attente',
    );
    return '$_temp0';
  }

  @override
  String get pushStatusNoToken => 'En attente du jeton push de cet appareil';

  @override
  String get pushStatusIdle => 'Activées : aucun échange ouvert à enregistrer';

  @override
  String pushStatusRegistered(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Enregistré pour $count échanges',
      one: 'Enregistré pour 1 échange',
    );
    return '$_temp0';
  }

  @override
  String pushStatusLastRegistered(String ago) {
    return 'dernier enregistrement $ago';
  }

  @override
  String get pushStatusUnreachable =>
      'Serveur push injoignable : nouvelle tentative';

  @override
  String get pushStatusNodeRefused =>
      'Ce nœud Mostro n’est pas accepté par le serveur push';

  @override
  String get pushStatusRateLimited =>
      'Limite de requêtes push atteinte : nouvelle tentative sous peu';

  @override
  String get pushUnsupportedPlatform =>
      'Les notifications push ne sont pas disponibles sur cette plateforme';

  @override
  String get pushToggleSaveFailed =>
      'Impossible de modifier les notifications push';

  @override
  String get pushNewMessageBody => 'Vous avez un nouveau message';

  @override
  String get notificationPrefSaveFailed =>
      'Impossible d’enregistrer cette préférence';

  @override
  String get logsScreenTitle => 'Journaux';

  @override
  String get logFilterAll => 'Tous';

  @override
  String get logFilterRelays => 'Relays';

  @override
  String get logFilterOrders => 'Ordres';

  @override
  String get logFilterPayments => 'Paiements';

  @override
  String get verboseLoggingTitle => 'Journalisation détaillée';

  @override
  String get verboseLoggingSubtitle => 'Plus de détail, plus de consommation';

  @override
  String get newLogsChipLabel => 'Nouveaux journaux';

  @override
  String get noLogsForFilter => 'Aucune entrée pour ce filtre';

  @override
  String get aboutAppSection => 'Application';

  @override
  String get aboutSourceCodeLabel => 'Code source';

  @override
  String get aboutUserGuideLabel => 'Guide utilisateur';

  @override
  String get aboutTechnicalDocsLabel => 'Documentation technique';

  @override
  String get aboutLanguageSpanish => 'Espagnol';

  @override
  String get aboutLanguageEnglish => 'Anglais';

  @override
  String get aboutConnectedNodeTitle => 'Nœud connecté';

  @override
  String get aboutMinOrderCell => 'Commande min.';

  @override
  String get aboutMaxOrderCell => 'Commande max.';

  @override
  String get aboutFeeCell => 'Frais';

  @override
  String aboutFeeValue(String value) {
    return '$value %';
  }

  @override
  String get aboutLimitsFootnote => 'Limites en satoshis par commande';

  @override
  String get aboutNodeTechnicalDataRow => 'Données techniques du nœud';

  @override
  String aboutFieldCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count champs',
      one: '$count champ',
    );
    return '$_temp0';
  }

  @override
  String get aboutTechnicalDataTitle => 'Données techniques';

  @override
  String get aboutPublicKeyLabel => 'Clé publique';

  @override
  String get aboutOrderExpiryLabel => 'Expiration de commande';

  @override
  String get aboutWaitingTimeoutLabel => 'Délai d\'attente';

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
  String get aboutNodePublicKeyLabel => 'Clé publique du nœud';

  @override
  String get aboutNodeUriLabel => 'URI du nœud';

  @override
  String get aboutCommitLabel => 'Commit';

  @override
  String get aboutChainNetworkLabel => 'Chaîne et réseau';

  @override
  String get aboutTechnicalFootnote =>
      'Ces données identifient le nœud avec lequel vous échangez. Utiles pour le support ou pour le vérifier avant d\'envoyer des fonds.';

  @override
  String get aboutCopyAllData => 'Copier toutes les données';

  @override
  String get tradesGroupNeedsAction => 'Action requise';

  @override
  String get tradesGroupInProgress => 'En cours';

  @override
  String get tradesGroupClosed => 'Terminées';

  @override
  String get tradesDirectionSell => 'Vous vendez';

  @override
  String get tradesDirectionBondClaim => 'Réclamation de dépôt';

  @override
  String get tradesDirectionBuy => 'Vous achetez';

  @override
  String tradesCounterpartyTo(String handle) {
    return 'à $handle';
  }

  @override
  String tradesCounterpartyFrom(String handle) {
    return 'à $handle';
  }

  @override
  String get tradeListChipYourTurn => 'À vous';

  @override
  String get tradeListChipPublished => 'Publiée';

  @override
  String get tradeListChipInProgress => 'En cours';

  @override
  String get tradeListChipWaitingInvoice => 'En attente de facture';

  @override
  String get tradeListChipWaitingPayment => 'En attente de paiement';

  @override
  String get tradeListChipWaitingSats => 'En attente des sats';

  @override
  String get tradeListChipDispute => 'En litige';

  @override
  String get tradeListChipCompleted => 'Terminée';

  @override
  String get tradeListChipCancelled => 'Annulée';

  @override
  String get tradeListChipExpired => 'Expirée';

  @override
  String get tradeVerbAddInvoice => 'Ajouter la facture';

  @override
  String get tradeVerbPayBond => 'Payer le dépôt';

  @override
  String get tradeHeadlineWaitingBond => 'Verrouille ton dépôt pour continuer';

  @override
  String get tradeInstructionWaitingBond =>
      'Le nœud retient cette prise jusqu\'au paiement du dépôt remboursable. L\'ordre reste ouvert aux autres entre-temps.';

  @override
  String get takeOrderBondNotice =>
      'Ce nœud demande à qui prend l\'ordre de verrouiller d\'abord un dépôt remboursable ; il revient quand l\'échange se termine honnêtement.';

  @override
  String takeOrderBondNoticeEstimate(String sats) {
    return 'Ce nœud demande à qui prend l\'ordre de verrouiller d\'abord un dépôt remboursable de ≈ $sats sats ; il revient quand l\'échange se termine honnêtement.';
  }

  @override
  String get tradeVerbPayInvoice => 'Payer la facture';

  @override
  String get tradeVerbSendPayment => 'Envoyer le paiement';

  @override
  String get tradeVerbReleaseSats => 'Libérer les sats';

  @override
  String get tradeVerbRate => 'Évaluer';

  @override
  String get tradeListFilterAll => 'Toutes';

  @override
  String get tradeListFilterActive => 'Actives';

  @override
  String get tradeListFilterCompleted => 'Terminées';

  @override
  String get tradeListFilterCancelled => 'Annulées';

  @override
  String get tradeListFilterTitle => 'Afficher les échanges';

  @override
  String get relativeTimeNow => 'maintenant';

  @override
  String relativeTimeMinutes(int count) {
    return 'il y a $count min';
  }

  @override
  String relativeTimeHours(int count) {
    return 'il y a $count h';
  }

  @override
  String get relativeTimeYesterday => 'hier';

  @override
  String satsFigureEstimate(String sats) {
    return '≈ $sats sats';
  }

  @override
  String satsFigureExact(String sats) {
    return '$sats sats';
  }

  @override
  String get chatGroupActive => 'Échanges actifs';

  @override
  String chatContextSellActive(String amount, String currency) {
    return 'Vous vendez $amount $currency';
  }

  @override
  String chatContextBuyActive(String amount, String currency) {
    return 'Vous achetez $amount $currency';
  }

  @override
  String chatContextSellClosed(String amount, String currency) {
    return 'Vous avez vendu $amount $currency';
  }

  @override
  String chatContextBuyClosed(String amount, String currency) {
    return 'Vous avez acheté $amount $currency';
  }

  @override
  String get chatTurnAddInvoice => 'à vous d\'ajouter la facture';

  @override
  String get chatTurnPayBond => 'à vous de payer le dépôt';

  @override
  String get chatTurnPayInvoice => 'à vous de payer la facture';

  @override
  String get chatTurnSendPayment => 'à vous de payer';

  @override
  String get chatTurnRelease => 'à vous de libérer';

  @override
  String get chatTurnRate => 'à vous d\'évaluer';

  @override
  String get chatYouLabel => 'Vous :';

  @override
  String get chatListFootnote =>
      'Chaque conversation appartient à un échange et est chiffrée de bout en bout. Une fois l\'échange terminé, elle reste consultable ici.';

  @override
  String get chatListEmptyTitle => 'Pas encore de conversations';

  @override
  String get chatListEmptyBody =>
      'Le chat s\'ouvre quand un échange devient actif.';

  @override
  String get chatClosedNotice =>
      'L\'échange est terminé. La conversation reste consultable ici.';

  @override
  String disputeOpenedByYou(String time) {
    return 'Vous l\'avez ouvert $time';
  }

  @override
  String disputeOpenedByPeer(String time) {
    return 'La contrepartie l\'a ouvert $time';
  }

  @override
  String get invoiceReceiveTitle => 'Recevoir tes sats';

  @override
  String get invoiceLockTitle => 'Bloquer tes sats';

  @override
  String get bondTitle => 'Dépôt de garantie';

  @override
  String get bondRefundableLabel => 'DÉPÔT REMBOURSABLE';

  @override
  String get bondComesBack => 'te revient une fois l\'échange terminé';

  @override
  String bondFiatComesBack(String fiat) {
    return '≈ $fiat · te revient une fois l\'échange terminé';
  }

  @override
  String bondPaySemantics(String sats) {
    return 'Dépôt remboursable de $sats sats';
  }

  @override
  String bondReleasesIn(String time) {
    return 'L\'ordre est libéré si tu ne paies pas dans $time';
  }

  @override
  String bondRowHeld(String bold) {
    return 'Les sats restent $bold, ils ne sont pas dépensés';
  }

  @override
  String get bondRowHeldBold => 'bloqués dans ton portefeuille';

  @override
  String bondRowReleased(String bold) {
    return 'Si l\'échange se termine bien, $bold';
  }

  @override
  String get bondRowReleasedBold => 'il est libéré tout seul';

  @override
  String bondRowLost(String bold) {
    return 'Tu ne le perds que s\'il y a un litige et que $bold';
  }

  @override
  String bondRowLostTimeout(String bold) {
    return 'Tu le perds si tu laisses expirer une étape, ou s\'il y a un litige et que $bold';
  }

  @override
  String get bondRowLostBold => 'tu le perds';

  @override
  String get bondWhyTitle => 'Pourquoi Mostro demande un dépôt';

  @override
  String get bondWhyCustody =>
      'Mostro ne garde pas de fonds, il ne peut donc pas sanctionner qui abandonne un échange ; le dépôt fait ce travail et protège tous les utilisateurs contre les escrocs.';

  @override
  String bondWhyHold(String hold) {
    return 'C\'est une facture $hold : ton portefeuille réserve les sats sans les envoyer ; à la fin de l\'échange, la réservation est annulée toute seule.';
  }

  @override
  String get bondWhyDispute =>
      'Si tu ouvres un litige et que tu gagnes, tu le récupères aussi. Il n\'est prélevé que si tu perds un litige.';

  @override
  String get bondWhyDisputeTimeout =>
      'Si tu ouvres un litige et que tu gagnes, tu le récupères aussi. Il n\'est prélevé que si tu perds un litige ou si tu laisses expirer une étape.';

  @override
  String get bondReadDocs => 'Lire la documentation';

  @override
  String get bondContextOrder => 'Ordre';

  @override
  String bondContextBuy(String fiat) {
    return 'Tu achètes $fiat';
  }

  @override
  String bondContextSell(String fiat) {
    return 'Tu vends $fiat';
  }

  @override
  String get bondContextEquals => 'Le dépôt équivaut à';

  @override
  String bondContextPercent(String pct) {
    return '$pct % du montant';
  }

  @override
  String get bondDontPublish => 'Ne pas publier l\'ordre';

  @override
  String get bondAbandoned =>
      'Ordre abandonné. Rien n\'a été publié ni facturé.';

  @override
  String bondPublishesIn(String time) {
    return 'Pas encore publié : l\'ordre est abandonné si vous ne payez pas dans $time';
  }

  @override
  String get bondInvoiceMissingMaker =>
      'Cet appareil n\'a pas de copie de la facture du dépôt et le nœud ne la renvoie pas pour un ordre que vous avez créé. Abandonnez l\'ordre et recréez-le.';

  @override
  String get bondExpiredBodyMaker =>
      'Il n\'a pas été payé à temps : l\'ordre n\'a jamais été publié et aucun sat n\'a quitté votre portefeuille.';

  @override
  String get bondExpiredNoticeMaker =>
      'La facture du dépôt a expiré ; l\'ordre n\'a pas été publié';

  @override
  String get orderStatusWaitingBond =>
      'En attente de votre dépôt — pas encore publié';

  @override
  String get bondCancelNotAllowed =>
      'Cet ordre ne peut pas être annulé tant que son dépôt est en attente. Abandonnez-le depuis l\'écran du dépôt.';

  @override
  String createOrderBondNoticeEstimate(String sats) {
    return 'Ce nœud vous demande de verrouiller un dépôt remboursable de ≈ $sats sats avant de publier l\'ordre ; il revient quand l\'échange se termine honnêtement.';
  }

  @override
  String get createOrderBondNotice =>
      'Ce nœud vous demande de verrouiller un dépôt remboursable avant de publier l\'ordre ; il revient quand l\'échange se termine honnêtement.';

  @override
  String get bondClaimTitle => 'Réclamer votre part';

  @override
  String get bondClaimShareLabel => 'VOTRE PART';

  @override
  String bondClaimShareSemantics(String sats) {
    return 'Part de $sats sats à réclamer';
  }

  @override
  String bondClaimContext(String context) {
    return 'De l\'échange de $context';
  }

  @override
  String bondClaimDeadline(String date) {
    return 'Réclamez avant le $date';
  }

  @override
  String get bondClaimExplainer =>
      'Le dépôt de l\'autre partie a été confisqué en votre faveur. Ajoutez une facture pour exactement ce montant et le nœud vous le paie.';

  @override
  String get bondClaimFieldLabel => 'Facture Lightning';

  @override
  String get bondClaimFieldHint => 'lnbc… pour exactement la part';

  @override
  String get bondClaimSubmit => 'Envoyer la facture';

  @override
  String get bondClaimSent => 'Facture envoyée au nœud';

  @override
  String get bondClaimSubmittedTitle => 'Facture envoyée';

  @override
  String get bondClaimSubmittedBody => 'En attente de la confirmation du nœud.';

  @override
  String get bondClaimAcknowledgedTitle => 'Paiement en cours';

  @override
  String get bondClaimAcknowledgedBody =>
      'Le nœud a accepté votre facture et la paie. S\'il ne peut pas la router, une nouvelle vous sera demandée.';

  @override
  String get bondClaimCompletedTitle => 'Payé';

  @override
  String bondClaimCompletedBody(String sats) {
    return '$sats sats sont arrivés dans votre portefeuille.';
  }

  @override
  String get bondClaimExpiredTitle => 'Le délai de réclamation est écoulé';

  @override
  String bondClaimExpiredBody(String date) {
    return 'Il s\'est terminé le $date. La part ne peut plus être réclamée.';
  }

  @override
  String get bondClaimMissing => 'Aucune réclamation trouvée pour cet ordre.';

  @override
  String get bondClaimErrorAmount =>
      'La facture doit être pour exactement la part indiquée.';

  @override
  String get bondClaimErrorExpired =>
      'Le délai de réclamation est écoulé ; la part ne peut plus être réclamée.';

  @override
  String get bondClaimErrorRejected =>
      'Le nœud n\'a pas accepté la facture. Essayez-en une autre.';

  @override
  String get bondClaimErrorNotClaimable =>
      'Cette réclamation n\'accepte pas de facture pour le moment.';

  @override
  String get bondClaimErrorNoKey =>
      'Cet appareil n\'a pas la clé de cet échange et ne peut donc pas réclamer la part.';

  @override
  String get tradeVerbClaimPayout => 'Réclamer le paiement';

  @override
  String get chatTurnClaimPayout => 'à vous de réclamer le paiement';

  @override
  String get tradeBadgePayoutPending => 'Paiement en attente';

  @override
  String get tradeBadgePayoutInProgress => 'Paiement en cours';

  @override
  String get tradeBadgePayoutPaid => 'Paiement reçu';

  @override
  String bondBannerPendingTitle(String sats) {
    return '$sats sats sont prêts à vous revenir';
  }

  @override
  String bondBannerPendingBody(String sats) {
    return 'Le dépôt de l\'autre partie a été confisqué en votre faveur. Ajoutez une facture Lightning de $sats sats pour le réclamer.';
  }

  @override
  String get bondBannerAddInvoice => 'Ajouter une facture de paiement';

  @override
  String get bondBannerView => 'Voir la réclamation';

  @override
  String get bondBannerInProgressTitle => 'Paiement en cours';

  @override
  String bondBannerInProgressBody(String sats) {
    return 'Le nœud paie votre part de $sats sats.';
  }

  @override
  String get bondBannerPaidTitle => 'Paiement reçu';

  @override
  String bondBannerPaidBody(String sats, String date) {
    return '$sats sats vous ont été payés le $date.';
  }

  @override
  String bondBannerExpired(String date) {
    return 'La réclamation sur le dépôt de l\'autre partie s\'est terminée le $date.';
  }

  @override
  String get bondClaimNewTitle => 'Paiement de dépôt à réclamer';

  @override
  String bondClaimNewMessage(String sats) {
    return 'Vous pouvez réclamer $sats sats d\'un dépôt confisqué. Ajoutez une facture Lightning pour les recevoir.';
  }

  @override
  String get bondClaimPaidTitle => 'Paiement de dépôt reçu';

  @override
  String bondClaimPaidMessage(String sats) {
    return 'Paiement de dépôt de $sats sats reçu.';
  }

  @override
  String get bondDontTake => 'Ne pas prendre l\'ordre';

  @override
  String get bondLockedNowEscrow =>
      'Dépôt verrouillé. Verrouille maintenant le montant de l\'échange.';

  @override
  String get bondLostRace =>
      'Un autre utilisateur a pris cet ordre avant que ton dépôt ne soit payé';

  @override
  String get bondMakerCanceled => 'Le créateur a annulé cet ordre';

  @override
  String get bondExpiredNotice =>
      'La facture du dépôt a expiré ; l\'ordre est retourné dans le carnet';

  @override
  String get bondExpiredTitle => 'La facture du dépôt a expiré';

  @override
  String get bondExpiredBody =>
      'Elle n\'a pas été payée à temps : l\'ordre est retourné dans le carnet et aucun sat n\'a quitté ton portefeuille.';

  @override
  String get bondInvoiceMissing =>
      'Cet appareil n\'a pas de copie de la facture du dépôt. Redemande-la au nœud pour continuer à prendre l\'ordre.';

  @override
  String get bondRequestAgain => 'Redemander la facture';

  @override
  String get bondRequestFailed =>
      'Le nœud n\'a pas renvoyé la facture du dépôt';

  @override
  String get invoiceOrderIdCopied => 'ID de l\'ordre copié';

  @override
  String get invoiceYouReceiveLabel => 'Tu vas recevoir';

  @override
  String get invoiceToPayLabel => 'À payer';

  @override
  String invoiceReceiveSemantics(String sats) {
    return '$sats satoshis à recevoir';
  }

  @override
  String invoicePaySemantics(String sats) {
    return '$sats satoshis à payer';
  }

  @override
  String invoiceFeeIncluded(String sats) {
    return 'Dont $sats sats de frais Mostro';
  }

  @override
  String invoiceTimeToSend(String time) {
    return 'Tu as $time pour l\'envoyer';
  }

  @override
  String invoiceExpiresIn(String time) {
    return 'La facture expire dans $time';
  }

  @override
  String get invoiceFieldLabel => 'Facture ou adresse Lightning';

  @override
  String get invoiceFieldHint => 'lnbc… ou utilisateur@domaine';

  @override
  String get invoiceFieldPromptLabel => 'Collez votre facture ici';

  @override
  String get invoiceFieldFilledLabel => 'Facture Lightning';

  @override
  String get invoiceFieldAddressLabel => 'Adresse Lightning';

  @override
  String get invoiceScanButton => 'Scanner';

  @override
  String get invoiceReplaceButton => 'Remplacer';

  @override
  String get invoiceFieldSemantics =>
      'Facture ou adresse Lightning, obligatoire';

  @override
  String invoiceFilledSemantics(String sats) {
    return 'Facture Lightning de $sats sats';
  }

  @override
  String get invoiceValidAddress =>
      'Adresse valide · la facture sera demandée à l\'envoi';

  @override
  String invoiceValidInvoice(String sats) {
    return 'Facture valide · $sats sats';
  }

  @override
  String invoiceErrorWrongAmount(String actual, String expected) {
    return 'La facture est de $actual sats, elle doit être de $expected';
  }

  @override
  String get invoiceErrorExpired => 'La facture a déjà expiré';

  @override
  String invoiceErrorExpiresTooSoon(String minutes) {
    return 'La facture expire dans moins de $minutes minutes, le nœud a besoin de plus de temps pour la payer';
  }

  @override
  String get invoiceErrorMalformed =>
      'Cette facture est incomplète ou mal copiée';

  @override
  String get invoiceErrorUnrecognized =>
      'Ni une facture (lnbc…) ni une adresse Lightning (utilisateur@domaine)';

  @override
  String get invoiceSellerLabel => 'Vendeur';

  @override
  String get invoiceBuyerLabel => 'Acheteur';

  @override
  String get invoiceYouPayLabel => 'Tu paies';

  @override
  String get invoiceYouGetLabel => 'Tu reçois';

  @override
  String get invoiceNoTrades => 'aucune opération';

  @override
  String get invoiceSendButton => 'Envoyer la facture';

  @override
  String get invoiceCancelTrade => 'Annuler l\'opération';

  @override
  String get invoiceOpenWallet => 'Ouvrir dans mon portefeuille';

  @override
  String invoiceHoldNote(String hold) {
    return 'C\'est une facture $hold : les sats sont retenus, ils ne quittent pas ton portefeuille tant que tu n\'as pas confirmé le paiement de l\'acheteur.';
  }

  @override
  String invoiceQrSemantics(String invoice) {
    return 'QR code de la facture Lightning : $invoice';
  }

  @override
  String get invoiceExpiredTitle => 'La facture a expiré';

  @override
  String get invoiceExpiredBody =>
      'Elle n\'a pas été payée à temps : Mostro annule l\'opération et aucun sat n\'a quitté ton portefeuille.';

  @override
  String get invoiceBackToBook => 'Retour au carnet d\'ordres';

  @override
  String get invoiceTimeUpTitle => 'Le temps est écoulé';

  @override
  String get invoiceTimeUpBody =>
      'La facture n\'a pas été envoyée à temps : Mostro annule l\'opération. Rien n\'a été engagé de ton côté.';

  @override
  String invoiceErrorWrongNetwork(String invoice, String node) {
    return 'La facture est pour $invoice, le nœud utilise $node';
  }

  @override
  String invoiceCountdownHours(String hours, String minutes) {
    return '$hours h $minutes';
  }

  @override
  String get tradeCardWaitingBuyerInvoiceTitle =>
      'En attente de la facture de l\'acheteur';

  @override
  String get tradeCardWaitingBuyerInvoiceMessage =>
      'L\'échange reprend dès que l\'acheteur ajoute une facture Lightning.';

  @override
  String get tradeCardWaitingPaymentTitle =>
      'En attente du paiement du vendeur';

  @override
  String get tradeCardWaitingPaymentMessage =>
      'L\'échange reprend dès que le vendeur paie la facture hold.';

  @override
  String get tradeCardWaitingTakerBondTitle => 'Paiement de caution en attente';

  @override
  String get tradeCardWaitingTakerBondMessage =>
      'La caution anti-abus du preneur doit être payée avant le début de l\'échange.';

  @override
  String get tradeCardActiveTitle => 'Échange actif';

  @override
  String get tradeCardActiveMessage =>
      'Les sats sont bloqués. L\'acheteur peut maintenant envoyer le paiement fiat.';

  @override
  String get tradeCardFiatSentTitle => 'Fiat marqué comme envoyé';

  @override
  String get tradeCardFiatSentMessage =>
      'L\'acheteur a marqué le paiement fiat comme envoyé.';

  @override
  String get tradeCardSettledHoldInvoiceTitle => 'Sats libérés';

  @override
  String get tradeCardSettledHoldInvoiceMessage =>
      'Le vendeur a libéré les sats. Le paiement de l\'acheteur est en route.';

  @override
  String get tradeCardSuccessTitle => 'Échange terminé';

  @override
  String get tradeCardSuccessMessage =>
      'L\'échange s\'est terminé avec succès.';

  @override
  String get tradeCardCanceledTitle => 'Échange annulé';

  @override
  String get tradeCardCanceledMessage => 'L\'échange a été annulé.';

  @override
  String get tradeCardExpiredTitle => 'Ordre expiré';

  @override
  String get tradeCardExpiredMessage =>
      'L\'ordre a expiré avant que l\'échange puisse continuer.';

  @override
  String get tradeCardCooperativelyCanceledTitle =>
      'Échange annulé d\'un commun accord';

  @override
  String get tradeCardCooperativelyCanceledMessage =>
      'Les deux parties ont accepté d\'annuler l\'échange.';

  @override
  String get tradeCardDisputeTitle => 'Litige ouvert';

  @override
  String get tradeCardDisputeMessage =>
      'Un litige a été ouvert sur cet échange.';

  @override
  String get tradeCardCanceledByAdminTitle => 'Annulé par le médiateur';

  @override
  String get tradeCardCanceledByAdminMessage =>
      'Le médiateur du litige a annulé l\'échange.';

  @override
  String get tradeCardSettledByAdminTitle => 'Réglé par le médiateur';

  @override
  String get tradeCardSettledByAdminMessage =>
      'Le médiateur du litige a libéré les sats à l\'acheteur.';

  @override
  String get tradeCardCompletedByAdminTitle => 'Terminé par le médiateur';

  @override
  String get tradeCardCompletedByAdminMessage =>
      'Le médiateur du litige a terminé l\'échange.';

  @override
  String get tradeCardUpdatedTitle => 'Échange mis à jour';

  @override
  String get tradeCardUpdatedMessage => 'Le statut de cet échange a changé.';

  @override
  String get tradeCardCanceledByMakerMessage =>
      'Le créateur a annulé l\'ordre.';

  @override
  String get tradeCardCanceledBondLostRaceMessage =>
      'Un autre utilisateur a pris cet ordre avant le paiement de la caution.';

  @override
  String get tradeCardCanceledBondExpiredMessage =>
      'La facture de caution a expiré sans être payée.';

  @override
  String get chatCardTitle => 'Nouveaux messages';

  @override
  String get chatCardSolverTitle => 'Messages du médiateur';

  @override
  String chatCardMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count nouveaux messages de votre contrepartie',
      one: '1 nouveau message de votre contrepartie',
    );
    return '$_temp0';
  }

  @override
  String chatCardSolverMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count nouveaux messages du médiateur du litige',
      one: '1 nouveau message du médiateur du litige',
    );
    return '$_temp0';
  }

  @override
  String get invalidTradeIndexError =>
      'Votre compte n\'est pas synchronisé avec ce nœud Mostro, qui a donc refusé l\'ordre. Réessayez dans un instant';

  @override
  String get recoveringTradesMessage =>
      'Compte importé. Récupération de vos échanges depuis Mostro…';

  @override
  String recoveredTradesMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Compte importé. $count échanges récupérés',
      one: 'Compte importé. 1 échange récupéré',
      zero: 'Compte importé. Vous n\'aviez aucun échange en cours',
    );
    return '$_temp0';
  }

  @override
  String get recoverTradesFailedMessage =>
      'Compte importé, mais Mostro n\'a pas répondu : vos échanges en cours n\'ont pas été récupérés';

  @override
  String get paymentMethodsChosenLabel => 'Choisis';

  @override
  String paymentMethodsSelectedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count méthodes sélectionnées',
      one: '1 méthode sélectionnée',
      zero: 'Choisis au moins une méthode',
    );
    return '$_temp0';
  }

  @override
  String get paymentMethodsConfirm => 'Confirmer les méthodes';

  @override
  String get paymentMethodAddCustom => 'Ajouter une méthode personnalisée';

  @override
  String get paymentMethodsDiscardTitle => 'Abandonner les modifications ?';

  @override
  String get paymentMethodsDiscardConfirm => 'Abandonner';

  @override
  String get paymentMethodsKeepEditing => 'Continuer à modifier';

  @override
  String get fundsAtRiskTitle => 'Cet utilisateur a encore des sats en jeu';

  @override
  String get fundsAtRiskBody =>
      'Si tu continues, les clés de cet utilisateur sont remplacées et rien de ce qui figure ici ne pourra être terminé ni récupéré depuis cet appareil. Ce n\'est pas recommandé : tu peux perdre ces sats.';

  @override
  String get fundsAtRiskSellerEscrow =>
      'Sats bloqués en séquestre pour une vente';

  @override
  String get fundsAtRiskBondLocked => 'Caution bloquée';

  @override
  String get fundsAtRiskPayoutClaim =>
      'Paiement de caution pas encore encaissé';

  @override
  String get fundsAtRiskTradeInProgress => 'Échange en cours';

  @override
  String get fundsAtRiskBondInvoicePending =>
      'Facture de caution encore payable';

  @override
  String get fundsAtRiskKeep => 'Garder cet utilisateur';

  @override
  String get fundsAtRiskContinue => 'Continuer quand même';
}

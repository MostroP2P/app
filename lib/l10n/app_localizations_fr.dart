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
  String get tabBuyBtc => 'ACHETER BTC';

  @override
  String get tabSellBtc => 'VENDRE BTC';

  @override
  String get filterButtonLabel => 'FILTRER';

  @override
  String offersCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count offres',
      one: '1 offre',
    );
    return '$_temp0';
  }

  @override
  String get noOrdersAvailable => 'Aucun ordre disponible';

  @override
  String get justNow => 'À l\'instant';

  @override
  String minutesAgo(int m) {
    return 'Il y a ${m}m';
  }

  @override
  String hoursAgo(int h) {
    return 'Il y a ${h}h';
  }

  @override
  String daysAgo(int d) {
    return 'Il y a ${d}j';
  }

  @override
  String get creatingNewOrderTitle => 'CRÉATION D\'UN NOUVEL ORDRE';

  @override
  String get youWantToBuyBitcoin => 'Vous voulez acheter du Bitcoin';

  @override
  String get youWantToSellBitcoin => 'Vous voulez vendre du Bitcoin';

  @override
  String get rangeOrderLabel => 'Ordre à plage';

  @override
  String get payLightningInvoiceTitle => 'Payer la facture Lightning';

  @override
  String get invoiceCopied => 'Facture copiée';

  @override
  String get addInvoiceTitle => 'Ajouter une facture';

  @override
  String get submitButtonLabel => 'Soumettre';

  @override
  String get orderAlreadyTaken => 'Cet ordre a déjà été pris';

  @override
  String get bondRequired =>
      'Ce nœud exige une caution anti-abus, qui n\'est pas encore prise en charge';

  @override
  String addInvoiceAmount(String sats) {
    return 'Montant à recevoir : $sats sats';
  }

  @override
  String payInvoiceAmount(String sats) {
    return 'Montant à payer : $sats sats';
  }

  @override
  String get orderIdCopied => 'ID d\'ordre copié';

  @override
  String get orderDetailsTitle => 'DÉTAILS DE L\'ORDRE';

  @override
  String get timeRemainingLabel => 'Temps restant :';

  @override
  String get fiatSentButtonLabel => 'FIAT ENVOYÉ';

  @override
  String get disputeButtonLabel => 'LITIGE';

  @override
  String get contactButtonLabel => 'CONTACTER';

  @override
  String get rateButtonLabel => 'NOTER';

  @override
  String get viewDisputeButtonLabel => 'Voir le litige';

  @override
  String get comingSoonMessage => 'Bientôt disponible';

  @override
  String get tradeStatusActive => 'Actif';

  @override
  String get tradeStatusFiatSent => 'Fiat envoyé';

  @override
  String get tradeStatusCompleted => 'Terminé';

  @override
  String get tradeStatusCancelled => 'Annulé';

  @override
  String get tradeStatusDisputed => 'En litige';

  @override
  String get releaseButtonLabel => 'LIBÉRER';

  @override
  String get accountScreenTitle => 'Compte';

  @override
  String get secretWordsTitle => 'Mots secrets';

  @override
  String get toRestoreYourAccount => 'Pour restaurer votre compte';

  @override
  String get privacyCardTitle => 'Confidentialité';

  @override
  String get controlPrivacySettings =>
      'Gérez vos paramètres de confidentialité';

  @override
  String get reputationMode => 'Mode Réputation';

  @override
  String get reputationModeSubtitle =>
      'Confidentialité standard avec réputation';

  @override
  String get fullPrivacyMode => 'Mode Confidentialité Totale';

  @override
  String get fullPrivacyModeSubtitle => 'Anonymat maximal';

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
  String get showButtonLabel => 'Afficher';

  @override
  String get settingsScreenTitle => 'Paramètres';

  @override
  String get languageSettingTitle => 'Langue';

  @override
  String get appearanceSettingTitle => 'Apparence';

  @override
  String get appearanceDialogTitle => 'Apparence';

  @override
  String get defaultFiatCurrencyTitle => 'Devise fiat par défaut';

  @override
  String get allCurrencies => 'Toutes les devises';

  @override
  String get lightningAddressSettingTitle => 'Adresse Lightning';

  @override
  String get tapToSetSubtitle => 'Appuyez pour configurer';

  @override
  String get nwcWalletSettingTitle => 'Portefeuille NWC';

  @override
  String get nwcConnectPrompt =>
      'Connectez votre portefeuille Lightning via NWC';

  @override
  String get relaysSettingTitle => 'Relais';

  @override
  String get manageRelayConnections => 'Gérer les connexions de relais';

  @override
  String get pushNotificationsSettingTitle => 'Notifications push';

  @override
  String get manageNotificationPreferences =>
      'Gérer les préférences de notifications';

  @override
  String get logReportSettingTitle => 'Rapport de logs';

  @override
  String get viewDiagnosticLogs => 'Voir les logs de diagnostic';

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
  String get connectWalletTitle => 'Connecter le portefeuille';

  @override
  String get scanQrCodeTitle => 'Scanner le code QR';

  @override
  String get pasteNwcUri => 'Coller l\'URI NWC';

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
  String nwcConnectedBalance(String balance) {
    return 'NWC — Connecté. Solde : $balance';
  }

  @override
  String get pasteQrCodeHeading => 'Coller le contenu du QR code';

  @override
  String get pasteButtonLabel => 'Coller';

  @override
  String get clipboardEmptyError => 'Le presse-papiers est vide';

  @override
  String get enterValueError => 'Veuillez entrer une valeur';

  @override
  String get pasteOrScanQrCode => 'Coller ou scanner un QR code';

  @override
  String get mostroNodeTitle => 'Nœud Mostro';

  @override
  String get currentNodeLabel => 'Nœud actuel';

  @override
  String get trustedBadgeLabel => 'De confiance';

  @override
  String get useDefaultButtonLabel => 'Utiliser le défaut';

  @override
  String get confirmButtonLabel => 'Confirmer';

  @override
  String get invalidHexPubkey =>
      'Doit être une chaîne hexadécimale de 64 caractères';

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
  String get submitRatingButton => 'SOUMETTRE';

  @override
  String get closeRatingButton => 'FERMER';

  @override
  String get aboutScreenTitle => 'À propos';

  @override
  String get mostroTagline => 'Trading Bitcoin pair-à-pair sur Nostr';

  @override
  String get viewDocumentationButton => 'Voir la documentation';

  @override
  String get linkCopiedToClipboard => 'Lien copié dans le presse-papiers';

  @override
  String get defaultNodeSection => 'Nœud par défaut';

  @override
  String get pubkeyLabel => 'Clé publique';

  @override
  String get relaysLabel => 'Relais';

  @override
  String get pubkeyCopiedToClipboard =>
      'Clé publique copiée dans le presse-papiers';

  @override
  String get footerTagline => 'Open-source. Non-custodial. Privé.';

  @override
  String get drawerTitle => 'MOSTRO';

  @override
  String get betaBadgeLabel => 'Bêta';

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
  String get backupConfirmCheckbox =>
      'J\'ai noté mes mots et les ai sauvegardés en lieu sûr';

  @override
  String get backupRitualSecondFailureMessage =>
      'C\'est encore incorrect. Veuillez vérifier et sauvegarder vos mots secrets, puis recommencer la vérification depuis le début.';

  @override
  String get cancelTradeDialogTitle => 'Annuler l\'échange ?';

  @override
  String get cancelTradeDialogContent =>
      'Annulation coopérative demandée. L\'autre partie doit également accepter pour que l\'échange soit entièrement annulé.';

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
  String get markFiatSentButton => 'Marquer comme envoyé';

  @override
  String get confirmReleaseSatsButton => 'Confirmer et libérer les sats';

  @override
  String get shareOrderButton => 'Partager l\'ordre';

  @override
  String get orderPillYouAreSelling => 'VOUS VENDEZ';

  @override
  String get orderPillYouAreBuying => 'VOUS ACHETEZ';

  @override
  String get orderPillSelling => 'VENTE';

  @override
  String get orderPillBuying => 'ACHAT';

  @override
  String get myOrderSellTitle => 'VOTRE ORDRE DE VENTE';

  @override
  String get myOrderBuyTitle => 'VOTRE ORDRE D\'ACHAT';

  @override
  String get cancelOrderButton => 'Annuler la commande';

  @override
  String get cancelOrderDialogTitle => 'Annuler la commande';

  @override
  String get cancelOrderDialogContent =>
      'Êtes-vous sûr de vouloir annuler cette commande ? Cette action est irréversible.';

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
  String get orderStatusWaitingBuyerInvoice =>
      'En attente de la facture de l\'acheteur';

  @override
  String get orderStatusWaitingPayment => 'En attente du paiement';

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
  String get aboutAppInfoTitle => 'Informations sur l\'application';

  @override
  String get aboutDocumentationTitle => 'Documentation';

  @override
  String get aboutMostroNodeTitle => 'Nœud Mostro';

  @override
  String get aboutVersionLabel => 'Version';

  @override
  String get aboutGithubRepoLabel => 'Dépôt GitHub';

  @override
  String get aboutCommitHashLabel => 'Hash du commit';

  @override
  String get aboutLicenseLabel => 'Licence';

  @override
  String get aboutLicenseName => 'MIT';

  @override
  String get aboutGithubRepoName => 'mostro-mobile';

  @override
  String get aboutDocsUsersEnglish => 'Utilisateurs (Anglais)';

  @override
  String get aboutDocsUsersSpanish => 'Utilisateurs (Espagnol)';

  @override
  String get aboutDocsTechnical => 'Technique';

  @override
  String get aboutDocsRead => 'Lire';

  @override
  String get aboutCopiedToClipboard => 'Copié dans le presse-papiers';

  @override
  String get aboutLicenseDialogTitle => 'Licence MIT';

  @override
  String get aboutNodeLoadingText => 'Chargement des informations du nœud…';

  @override
  String get aboutNodeUnavailable => 'Informations du nœud indisponibles';

  @override
  String get aboutNodeRetry => 'Réessayer';

  @override
  String get aboutGeneralInfoSection => 'Informations générales';

  @override
  String get aboutTechnicalDetailsSection => 'Détails techniques';

  @override
  String get aboutLightningNetworkSection => 'Réseau Lightning';

  @override
  String get aboutMostroPublicKeyLabel => 'Clé publique Mostro';

  @override
  String get aboutMaxOrderAmountLabel => 'Montant maximum de commande';

  @override
  String get aboutMinOrderAmountLabel => 'Montant minimum de commande';

  @override
  String get aboutOrderLifespanLabel => 'Durée de vie de la commande';

  @override
  String get aboutServiceFeeLabel => 'Frais de service';

  @override
  String get aboutFiatCurrenciesLabel => 'Devises fiat';

  @override
  String get aboutMostroVersionLabel => 'Version Mostro';

  @override
  String get aboutMostroCommitLabel => 'Commit Mostro';

  @override
  String get aboutOrderExpirationLabel => 'Expiration de la commande';

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
  String get aboutLndNodePublicKeyLabel => 'Clé publique du nœud LND';

  @override
  String get aboutLndCommitLabel => 'Commit LND';

  @override
  String get aboutLndNodeAliasLabel => 'Alias du nœud LND';

  @override
  String get aboutSupportedChainsLabel => 'Chaînes supportées';

  @override
  String get aboutSupportedNetworksLabel => 'Réseaux supportés';

  @override
  String get aboutLndNodeUriLabel => 'URI du nœud LND';

  @override
  String get aboutSatoshisSuffix => 'Satoshis';

  @override
  String get aboutHoursSuffix => 'heures';

  @override
  String get aboutSecondsSuffix => 'secondes';

  @override
  String get aboutBlocksSuffix => 'blocs';

  @override
  String get aboutFiatCurrenciesAll => 'Toutes';

  @override
  String get aboutMostroPublicKeyExplanation =>
      'La clé publique Nostr du daemon Mostro. Toutes les commandes et messages chiffrés de cette instance sont publiés ou acheminés par cette clé.';

  @override
  String get aboutMaxOrderAmountExplanation =>
      'Le montant fiat maximum autorisé pour une seule commande sur cette instance Mostro.';

  @override
  String get aboutMinOrderAmountExplanation =>
      'Le montant fiat minimum requis pour une seule commande sur cette instance Mostro.';

  @override
  String get aboutOrderLifespanExplanation =>
      'La durée pendant laquelle une commande en attente reste ouverte avant d\'expirer automatiquement si aucun preneur n\'est trouvé.';

  @override
  String get aboutServiceFeeExplanation =>
      'Le pourcentage du montant de la transaction prélevé par le daemon Mostro en tant que frais de service.';

  @override
  String get aboutFiatCurrenciesExplanation =>
      'Les devises fiat acceptées sur cette instance Mostro. \'Toutes\' signifie qu\'il n\'y a pas de restrictions.';

  @override
  String get aboutMostroVersionExplanation =>
      'La version du logiciel daemon Mostro exécutant cette instance.';

  @override
  String get aboutMostroCommitExplanation =>
      'Le hash de commit Git du build du daemon Mostro, utilisé pour identifier la révision exacte du logiciel.';

  @override
  String get aboutOrderExpirationExplanation =>
      'Le délai d\'attente en secondes après lequel une transaction en attente d\'action (ex. facture ou paiement) est automatiquement annulée.';

  @override
  String get aboutHoldInvoiceExpExplanation =>
      'La fenêtre de temps en secondes pendant laquelle la hold invoice Lightning doit être réglée.';

  @override
  String get aboutHoldInvoiceCltvExplanation =>
      'Le delta CLTV (nombre de blocs) utilisé pour les hold invoices, contrôlant la durée de verrouillage du HTLC.';

  @override
  String get aboutInvoiceExpWindowExplanation =>
      'La fenêtre de temps en secondes dans laquelle l\'acheteur doit soumettre une facture Lightning après le début de la transaction.';

  @override
  String get aboutProofOfWorkExplanation =>
      'La difficulté minimale de preuve de travail requise pour les événements Nostr sur cette instance. 0 signifie qu\'aucun PoW n\'est requis.';

  @override
  String get aboutMaxOrdersPerResponseExplanation =>
      'Le nombre maximum de commandes retournées dans une seule réponse relay. Limite la consommation de bande passante.';

  @override
  String get aboutLndVersionExplanation =>
      'La version du nœud LND (Lightning Network Daemon) connecté à cette instance Mostro.';

  @override
  String get aboutLndNodePublicKeyExplanation =>
      'La clé publique du nœud LND. Utilisée pour identifier et vérifier le nœud du réseau Lightning.';

  @override
  String get aboutLndCommitExplanation =>
      'Le hash de commit Git du build LND, identifiant la révision exacte du logiciel du nœud Lightning.';

  @override
  String get aboutLndNodeAliasExplanation =>
      'L\'alias lisible par l\'homme du nœud LND tel que configuré par l\'opérateur du nœud.';

  @override
  String get aboutSupportedChainsExplanation =>
      'La ou les blockchain(s) supportée(s) par le nœud LND (ex. \'bitcoin\').';

  @override
  String get aboutSupportedNetworksExplanation =>
      'Le ou les réseau(x) sur lesquels le nœud LND opère (ex. \'mainnet\', \'testnet\').';

  @override
  String get aboutLndNodeUriExplanation =>
      'L\'URI de connexion du nœud LND au format pubkey@hôte:port. Utilisée pour ouvrir des canaux de paiement directs.';

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
  String get aboutBondStatusExplanation =>
      'Indique si cette instance Mostro exige une caution anti-abus : une petite facture à retenue Lightning bloquée pendant toute la durée de l\'échange et libérée lorsque celui-ci se termine normalement. « Non prise en charge » signifie que le démon est antérieur à cette fonctionnalité.';

  @override
  String get aboutBondAppliesToLabel => 'S\'applique à';

  @override
  String get aboutBondAppliesToExplanation =>
      'Quelle partie de l\'échange doit bloquer une caution : le preneur, le créateur, ou les deux.';

  @override
  String get aboutBondAppliesToTakers => 'Preneurs';

  @override
  String get aboutBondAppliesToMakers => 'Créateurs';

  @override
  String get aboutBondAppliesToBoth => 'Créateurs et preneurs';

  @override
  String get aboutBondAmountLabel => 'Montant de la caution';

  @override
  String get aboutBondAmountExplanation =>
      'La caution en pourcentage du montant de l\'ordre. Le plus élevé entre cette valeur et la caution minimale est retenu.';

  @override
  String get aboutBondBaseAmountLabel => 'Caution minimale';

  @override
  String get aboutBondBaseAmountExplanation =>
      'Le plancher d\'une caution, en satoshis. Il s\'applique lorsque le pourcentage du montant de l\'ordre passe en dessous.';

  @override
  String get aboutBondNodeShareLabel => 'Part du nœud en cas de saisie';

  @override
  String get aboutBondNodeShareExplanation =>
      'La part d\'une caution saisie conservée par le nœud. Le reste est transmis à la contrepartie lésée.';

  @override
  String get aboutBondSlashOnTimeoutLabel => 'Saisie en cas de délai dépassé';

  @override
  String get aboutBondSlashOnTimeoutExplanation =>
      'Indique si la caution est saisie lorsqu\'une partie laisse expirer un état d\'attente au lieu d\'agir.';

  @override
  String get aboutBondClaimWindowLabel => 'Délai de réclamation du paiement';

  @override
  String get aboutBondClaimWindowExplanation =>
      'Le temps dont dispose la contrepartie lésée pour envoyer une facture Lightning et réclamer sa part d\'une caution saisie.';

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
  String get tradeWaitingInvoiceBuyerInstruction =>
      'Soumettez votre facture Lightning pour que le vendeur puisse bloquer les fonds.';

  @override
  String get tradeWaitingInvoiceSellerInstruction =>
      'En attente de la facture Lightning de l\'acheteur.';

  @override
  String get tradeWaitingPaymentBuyerInstruction =>
      'Le vendeur est en train de payer la facture hold. Veuillez patienter.';

  @override
  String get tradeWaitingPaymentSellerInstruction =>
      'Payez la facture hold pour bloquer les fonds et démarrer l\'échange.';

  @override
  String get tradeLoadError =>
      'Une erreur s\'est produite lors du chargement de l\'échange.';

  @override
  String get tradeWaitingForHoldInvoice => 'En attente de la facture hold...';

  @override
  String get payInvoiceInstruction =>
      'Payez cette facture hold pour démarrer l\'échange.';

  @override
  String get shareButtonLabel => 'Partager';

  @override
  String get shareFailed => 'Impossible de partager la facture';

  @override
  String get waitingForPaymentConfirmation =>
      'En attente de la confirmation du paiement...';

  @override
  String get payWithLightningWallet => 'Payer avec un portefeuille Lightning';

  @override
  String get noLightningWalletFound =>
      'Aucun portefeuille Lightning trouvé sur cet appareil';

  @override
  String get orderNoLongerActive => 'Cet ordre n\'est plus actif';

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
  String get failedToConfirmBackupMessage =>
      'Échec de la confirmation de la sauvegarde. Veuillez réessayer.';

  @override
  String get secretWordsInfoContent =>
      'Vos 12 mots secrets sont le seul moyen de récupérer votre compte. Sauvegardez-les dans un endroit sûr — ne les partagez jamais avec personne.';

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
  String get backedUpBadgeLabel => 'Sauvegardé';

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
      'Ces mots seront masqués lorsque vous quitterez cet écran';

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
  String get allWordsCorrectMessage => 'Les 3 mots sont corrects !';

  @override
  String get showWordsAgainButton => 'Afficher à nouveau les mots';

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
  String get remindMeTomorrowButton => 'Rappelez-moi demain';

  @override
  String get nwcConnectionFailedMessage =>
      'La connexion a échoué. Veuillez vérifier votre URI NWC et réessayer.';

  @override
  String get connectWalletDescription =>
      'Connectez votre portefeuille Lightning à l\'aide d\'une\nURI Nostr Wallet Connect (NWC).';

  @override
  String get nwcUriLabel => 'NWC URI';

  @override
  String get clipboardInvalidNwcUriMessage =>
      'Le presse-papiers ne contient pas d\'URI NWC valide.';

  @override
  String get scanQrButtonLabel => 'Scanner QR';

  @override
  String get connectButtonLabel => 'Connecter';

  @override
  String get walletConfigurationTitle => 'Configuration du portefeuille';

  @override
  String get walletDisconnectedMessage => 'Portefeuille déconnecté';

  @override
  String get connectedBadgeLabel => 'Connecté';

  @override
  String get balanceLabel => 'Solde';

  @override
  String get relayLabel => 'Relais';

  @override
  String get noWalletConnectedTitle => 'Aucun portefeuille connecté';

  @override
  String get connectWalletPrompt =>
      'Connectez un portefeuille pour activer les paiements Lightning automatiques.';

  @override
  String get disconnectButtonLabel => 'Déconnecter';

  @override
  String relaysMoreSuffix(int count) {
    return '(+$count de plus)';
  }

  @override
  String get chooseNotificationEventsSubtitle =>
      'Choisissez quels événements déclenchent les notifications push.';

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
  String get failedToResetNodeMessage => 'Échec de la réinitialisation du nœud';

  @override
  String get invalidPubkeyOrBridgeErrorMessage =>
      'Clé publique invalide ou erreur du pont';

  @override
  String get currentNodePublicKeyLabel => 'Clé publique du nœud actuel';

  @override
  String get useCustomNodePubkeyLabel =>
      'Utiliser une clé publique de nœud personnalisée';

  @override
  String get enterHexPubkeyHint =>
      'Entrez une clé publique hex de 64 caractères';

  @override
  String get shareLogsTooltip => 'Partager les journaux';

  @override
  String get noLogsToShareTooltip => 'Aucun journal à partager';

  @override
  String get disableLoggingTooltip => 'Désactiver la journalisation';

  @override
  String get enableLoggingTooltip => 'Activer la journalisation';

  @override
  String get loggingEnabledStatus => 'Journalisation activée';

  @override
  String get loggingDisabledStatus => 'Journalisation désactivée';

  @override
  String get noLogEntriesMessage => 'Aucune entrée de journal';

  @override
  String get failedToShareLogsMessage => 'Échec du partage des journaux';

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
  String get tradeStatusFilterPrefix => 'Statut';

  @override
  String get noTradesTitle => 'Aucune transaction';

  @override
  String get noTradesSubtitle =>
      'Vos transactions actives et terminées apparaîtront ici.';

  @override
  String get couldNotLoadTradesMessage =>
      'Impossible de charger les transactions';

  @override
  String get releaseBitcoinTitle => 'Libérer les Bitcoin';

  @override
  String get releaseBitcoinConfirmation =>
      'Êtes-vous sûr de vouloir libérer les Satoshis à l\'acheteur ?';

  @override
  String get sellingBitcoin => 'Vente de Bitcoin';

  @override
  String get buyingBitcoin => 'Achat de Bitcoin';

  @override
  String get createdByYou => 'Créé par vous';

  @override
  String get takenByYou => 'Pris par vous';

  @override
  String get timeAgoNow => 'maintenant';

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
    return '${count}j';
  }

  @override
  String get tradeStatusLoading => 'Chargement';

  @override
  String get tradeStatusRate => 'Évaluer';

  @override
  String get tradeStatusRated => 'Évalué';

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
  String get tradeInstructionPendingRating =>
      'La transaction s\'est terminée avec succès. Évaluez votre contrepartie pour renforcer la confiance dans la communauté.';

  @override
  String get tradeInstructionRated => 'Merci pour votre évaluation !';

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
  String get tradeHeadlineComplete => 'Transaction terminée !';

  @override
  String get tradeHeadlineCompleteRated => 'Transaction terminée';

  @override
  String get tradeHeadlineCancelled => 'Ordre annulé';

  @override
  String get tradeHeadlineLoading => 'Chargement de la transaction…';

  @override
  String get tradeTimerPendingLabel =>
      'Temps pour que cet ordre reste dans le carnet';

  @override
  String get tradeTimerPendingConsequence =>
      'S\'il expire, l\'ordre est retiré du carnet. Cela n\'affectera pas votre réputation.';

  @override
  String get tradeTimerWaitingInvoiceLabelBuyer =>
      'Temps pour partager votre facture';

  @override
  String get tradeTimerWaitingInvoiceLabelSeller =>
      'Temps pour que l\'acheteur partage une facture';

  @override
  String get tradeTimerWaitingInvoiceConsequence =>
      'S\'il expire, la transaction est annulée et l\'ordre retourne au carnet.';

  @override
  String get tradeTimerWaitingPaymentLabelBuyer =>
      'Temps pour que le vendeur verrouille les sats';

  @override
  String get tradeTimerWaitingPaymentLabelSeller =>
      'Temps pour payer la facture de retenue';

  @override
  String get tradeTimerActiveLabelBuyer =>
      'Temps pour envoyer le paiement fiat';

  @override
  String get tradeTimerActiveLabelSeller =>
      'Temps pour que l\'acheteur envoie le fiat';

  @override
  String get tradeTimerActiveConsequence =>
      'S\'il expire, la transaction peut être annulée. Coordonnez-vous dans le chat si plus de temps est nécessaire.';

  @override
  String get tradeTimerFiatSentLabelBuyer =>
      'Temps pour que le vendeur confirme la réception';

  @override
  String get tradeTimerFiatSentLabelSeller =>
      'Temps pour confirmer la réception et libérer';

  @override
  String get tradeTimerFiatSentConsequence =>
      'Si quelque chose semble anormal, ouvrez un litige avec le bouton ci-dessous.';

  @override
  String get tradeStepOrderTaken => 'Ordre pris';

  @override
  String get tradeStepInvoiceBuyer =>
      'Vous partagez une facture · le vendeur verrouille les sats';

  @override
  String get tradeStepInvoiceSeller =>
      'L\'acheteur partage une facture · vous verrouillez les sats';

  @override
  String get tradeStepFiatBuyer => 'Vous envoyez le paiement fiat';

  @override
  String get tradeStepFiatSeller => 'L\'acheteur envoie le paiement fiat';

  @override
  String get tradeStepReleaseBuyer => 'Le vendeur confirme et libère vos sats';

  @override
  String get tradeStepReleaseSeller =>
      'Vous confirmez la réception et libérez les sats';

  @override
  String get tradeStepRate => 'Évaluez votre contrepartie';

  @override
  String get activeTradeTitle => 'TRANSACTION ACTIVE';

  @override
  String tradeIdShortLabel(String id) {
    return 'ID $id';
  }

  @override
  String tradeCreatedAtLabel(String date) {
    return 'créé $date';
  }

  @override
  String get releaseSatsMenuItem => 'Libérer les sats';

  @override
  String get cancelOrderMenuItem => 'Annuler l\'ordre';

  @override
  String get openDisputeMenuItem => 'Ouvrir un litige';

  @override
  String get stepDoneLabel => 'TERMINÉ';

  @override
  String stepIndicator(int current, int total) {
    return 'ÉTAPE $current SUR $total';
  }

  @override
  String get addLightningInvoiceButton => 'Ajouter une facture Lightning';

  @override
  String get viewDisputeButton => 'Voir le litige';

  @override
  String get waitingForBuyer => 'En attente de l\'acheteur…';

  @override
  String get waitingForSeller => 'En attente du vendeur…';

  @override
  String get waitingForFiatPayment => 'En attente du paiement fiat…';

  @override
  String get waitingForCounterpart => 'En attente d\'une contrepartie…';

  @override
  String get yourTradeTimelineTitle => 'VOTRE TRANSACTION';

  @override
  String get yourCounterpartFallback => 'votre contrepartie';

  @override
  String secureChatUnread(int count) {
    return 'Chat sécurisé · $count nouveaux';
  }

  @override
  String get secureChatEncrypted => 'Chat sécurisé · chiffré de bout en bout';

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
  String get activeTradeConversations =>
      'Vos conversations de transactions actives';

  @override
  String get noMessagesAvailable => 'Aucun message disponible';

  @override
  String get disputesAndAdminChat => 'Litiges et chat administrateur';

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
  String sellingSatsTo(String handle) {
    return 'Vous vendez des sats à $handle';
  }

  @override
  String buyingSatsFrom(String handle) {
    return 'Vous achetez des sats à $handle';
  }

  @override
  String youMessagePrefix(String message) {
    return 'Vous : $message';
  }

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
  String get waitingForTradeAmount =>
      'En attente du montant de la transaction — veuillez réessayer sous peu.';

  @override
  String get fetchingTradeAmount =>
      'Récupération du montant de la transaction…';

  @override
  String get enterInvoiceManually => 'Saisir la facture manuellement';

  @override
  String get enterLightningInvoiceInstruction =>
      'Saisissez une facture Lightning pour recevoir vos sats';

  @override
  String get lightningInvoiceLabel => 'Facture Lightning';

  @override
  String get submitButton => 'Envoyer';

  @override
  String get sellOrderDetailsTitle => 'DÉTAILS DE L\'ORDRE DE VENTE';

  @override
  String get buyOrderDetailsTitle => 'DÉTAILS DE L\'ORDRE D\'ACHAT';

  @override
  String get buyTheseSatsButton => 'ACHETER CES SATS';

  @override
  String get sellSatsButton => 'VENDRE DES SATS';

  @override
  String get someoneSellingSats => 'Quelqu\'un vend des sats';

  @override
  String get someoneBuyingSats => 'Quelqu\'un achète des sats';

  @override
  String get takeOrderForPrefix => 'pour ';

  @override
  String get takeOrderAtMarketPrice => ' au prix du marché';

  @override
  String premiumLabel(String premium) {
    return 'Prime : $premium%';
  }

  @override
  String get creatorReputation => 'Réputation du créateur';

  @override
  String get ratingStatLabel => 'note';

  @override
  String get tradesStatLabel => 'transactions';

  @override
  String get daysActiveStatLabel => 'jours actifs';

  @override
  String get timeToTakeOrder => 'TEMPS POUR PRENDRE CET ORDRE';

  @override
  String get orderExpiryRemovedNote =>
      'S\'il expire, l\'ordre est retiré du carnet. ';

  @override
  String get orderExpiryNoReputationNote =>
      'Cela n\'affectera pas votre réputation.';

  @override
  String get minHint => 'Min';

  @override
  String get maxHint => 'Max';

  @override
  String get fiatAmountHint => 'Montant fiat';

  @override
  String get enterAmountForPreview =>
      'Saisissez un montant pour voir un aperçu en direct.';

  @override
  String get previewLabel => 'APERÇU';

  @override
  String previewBuyMarket(String amount, String price) {
    return 'Vous achetez des BTC pour *$amount* à *$price* · actif pendant *24 h*';
  }

  @override
  String previewSellMarket(String amount, String price) {
    return 'Vous vendez des BTC pour *$amount* à *$price* · actif pendant *24 h*';
  }

  @override
  String previewReceiveFixed(String sats, String amount) {
    return 'Vous recevez *$sats sats* pour *$amount* · actif pendant *24 h*';
  }

  @override
  String previewSellFixed(String sats, String amount) {
    return 'Vous vendez *$sats sats* pour *$amount* · actif pendant *24 h*';
  }

  @override
  String get marketPriceLabel => 'prix du marché';

  @override
  String marketPricePremium(String premium) {
    return 'marché $premium%';
  }

  @override
  String get priceTypeLabel => 'Type de prix';

  @override
  String get priceTypeMarket => 'Marché';

  @override
  String get priceTypeFixed => 'Fixe';

  @override
  String get priceTypeInfoTooltip => 'Infos sur le type de prix';

  @override
  String get premiumSectionLabel => 'Prime';

  @override
  String get amountInSatsHint => 'Montant en sats';

  @override
  String get priceTypesDialogTitle => 'Types de prix';

  @override
  String get priceTypesDialogContent =>
      'Prix du marché : le prix de votre ordre suit le taux du marché avec un pourcentage de prime/remise appliqué.\n\nPrix fixe : vous définissez un prix exact en satoshis.';

  @override
  String get startFromPreset => 'PARTIR D\'UN PRÉRÉGLAGE';

  @override
  String get presetExpressTitle => 'Express';

  @override
  String get recommendedTag => 'RECOMMANDÉ';

  @override
  String get presetConservativeTitle => 'Conservateur';

  @override
  String get presetConservativeSubtitle =>
      'Prix du marché · 0% de prime · vous choisissez le montant et les méthodes';

  @override
  String get presetCustomTitle => 'Personnalisé';

  @override
  String get presetCustomSubtitle =>
      'Tous les champs — montant, plage, méthodes, prime, prix fixe ou du marché';

  @override
  String expressPresetSubtitle(String details) {
    return 'Comme votre dernier ordre réussi — $details';
  }

  @override
  String expressPremiumSuffix(String premium) {
    return '$premium% de prime';
  }

  @override
  String get paymentMethodsLabel => 'Moyens de paiement';

  @override
  String get addPaymentMethod => 'Ajouter un moyen de paiement';

  @override
  String get customPaymentMethodHint => 'Moyen de paiement personnalisé...';

  @override
  String get customMethodAppendedNote =>
      'Le moyen personnalisé sera ajouté à la sélection';

  @override
  String get selectPaymentMethodsTitle => 'Sélectionnez les moyens de paiement';

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
  String get buyLabel => 'Acheter';

  @override
  String get sellLabel => 'Vendre';

  @override
  String get unableToOpenNotification =>
      'Impossible d\'ouvrir les détails de la notification.';

  @override
  String get reasonBestPremium => '⚡ Meilleure prime';

  @override
  String get reasonMostReputable => '⭐ Plus réputé';

  @override
  String get reasonJustPublished => '🆕 Vient d\'être publié';

  @override
  String get marketPriceCaption => 'Prix du marché';

  @override
  String orderReputationStats(int trades, int days) {
    return ' · $trades transactions · $days jours';
  }

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
  String marketPricePremiumLabel(String premium) {
    return 'Prix du marché ($premium%)';
  }

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
  String get lightningInvoiceQrLabel => 'QR code de la facture Lightning';

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
}

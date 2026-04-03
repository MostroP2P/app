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
  String get viewDisputeButtonLabel => 'VOIR LE LITIGE';

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
  String get cancelTradeDialogTitle => 'Annuler l\'échange ?';

  @override
  String get cancelTradeDialogContent =>
      'Annulation coopérative demandée. L\'autre partie doit également accepter pour que l\'échange soit entièrement annulé.';

  @override
  String get noButtonLabel => 'Non';

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
}

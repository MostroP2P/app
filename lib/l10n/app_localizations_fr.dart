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
}

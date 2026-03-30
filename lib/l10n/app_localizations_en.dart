// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appName => 'Mostro';

  @override
  String get loading => 'Loading…';

  @override
  String get error => 'Error';

  @override
  String get cancel => 'Cancel';

  @override
  String get confirm => 'Confirm';

  @override
  String get done => 'Done';

  @override
  String get skip => 'Skip';

  @override
  String get chatTimestampYesterday => 'Yesterday';

  @override
  String get disputesEmptyState => 'Your disputes will appear here';

  @override
  String get disputeAttachFile => 'Attach file';

  @override
  String get disputeWriteMessageHint => 'Write a message…';

  @override
  String get disputeSend => 'Send';

  @override
  String get orderDispute => 'Order dispute';

  @override
  String get disputeAdminAssigned =>
      'An administrator has been assigned to your dispute. They will contact you here shortly.';

  @override
  String get disputeChatClosed =>
      'This dispute has been resolved. The chat is closed.';

  @override
  String get messageCopied => 'Copied';

  @override
  String get disputeLoadError => 'Failed to load disputes. Please try again.';

  @override
  String get disputeMessagingComingSoon => 'Dispute messaging coming soon';

  @override
  String get disputeAttachmentsComingSoon => 'File attachments coming soon';

  @override
  String get disputeNotFound => 'Dispute not found.';

  @override
  String get disputeNotFoundForOrder => 'Dispute not found for this order.';

  @override
  String get disputeResolved => 'Resolved';

  @override
  String get disputeSuccessfullyCompleted => 'Successfully completed';

  @override
  String get disputeCoopCancelMessage =>
      'The order was cooperatively cancelled. No funds were transferred.';

  @override
  String disputeWithBuyer(String handle) {
    return 'Dispute with Buyer: $handle';
  }

  @override
  String disputeWithSeller(String handle) {
    return 'Dispute with Seller: $handle';
  }

  @override
  String orderLabel(String orderId) {
    return 'Order $orderId';
  }

  @override
  String get disputeInitiated => 'Initiated';

  @override
  String get disputeInProgress => 'In progress';

  @override
  String get disputeStatusClosed => 'Closed';

  @override
  String get disputeLostFundsToBuyer =>
      'The administrator settled the dispute in the buyer\'s favour. The sats were released to the buyer.';

  @override
  String get disputeLostFundsToSeller =>
      'The administrator canceled the order and returned the sats to the seller. You did not receive the sats.';
}

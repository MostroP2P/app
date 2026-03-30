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
}

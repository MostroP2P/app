import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_de.dart';
import 'app_localizations_en.dart';
import 'app_localizations_es.dart';
import 'app_localizations_fr.dart';
import 'app_localizations_it.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('de'),
    Locale('en'),
    Locale('es'),
    Locale('fr'),
    Locale('it')
  ];

  /// Application name
  ///
  /// In en, this message translates to:
  /// **'Mostro'**
  String get appName;

  /// Generic loading label
  ///
  /// In en, this message translates to:
  /// **'Loading…'**
  String get loading;

  /// Generic error label
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get error;

  /// Cancel action
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// Confirm action
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirm;

  /// Done action
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// Skip action
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get skip;

  /// Timestamp label for messages from yesterday
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get chatTimestampYesterday;

  /// Empty state message on the disputes list screen
  ///
  /// In en, this message translates to:
  /// **'Your disputes will appear here'**
  String get disputesEmptyState;

  /// Tooltip for the attach file button in dispute chat
  ///
  /// In en, this message translates to:
  /// **'Attach file'**
  String get disputeAttachFile;

  /// Hint text for the dispute chat message input field
  ///
  /// In en, this message translates to:
  /// **'Write a message…'**
  String get disputeWriteMessageHint;

  /// Tooltip for the send button in dispute chat
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get disputeSend;

  /// Title label for a dispute list item
  ///
  /// In en, this message translates to:
  /// **'Order dispute'**
  String get orderDispute;

  /// Banner shown when an admin is assigned but no messages exist yet
  ///
  /// In en, this message translates to:
  /// **'An administrator has been assigned to your dispute. They will contact you here shortly.'**
  String get disputeAdminAssigned;

  /// Lock banner shown when the dispute is resolved
  ///
  /// In en, this message translates to:
  /// **'This dispute has been resolved. The chat is closed.'**
  String get disputeChatClosed;

  /// Snackbar text after copying a chat message to clipboard
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get messageCopied;

  /// Error message shown when disputes fail to load
  ///
  /// In en, this message translates to:
  /// **'Failed to load disputes. Please try again.'**
  String get disputeLoadError;

  /// Snackbar shown when user tries to send a dispute message
  ///
  /// In en, this message translates to:
  /// **'Dispute messaging coming soon'**
  String get disputeMessagingComingSoon;

  /// Snackbar shown when user tries to attach a file in dispute chat
  ///
  /// In en, this message translates to:
  /// **'File attachments coming soon'**
  String get disputeAttachmentsComingSoon;

  /// Body text shown when a dispute cannot be found by ID
  ///
  /// In en, this message translates to:
  /// **'Dispute not found.'**
  String get disputeNotFound;

  /// Snackbar shown when no dispute exists for the current trade
  ///
  /// In en, this message translates to:
  /// **'Dispute not found for this order.'**
  String get disputeNotFoundForOrder;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['de', 'en', 'es', 'fr', 'it'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'de':
      return AppLocalizationsDe();
    case 'en':
      return AppLocalizationsEn();
    case 'es':
      return AppLocalizationsEs();
    case 'fr':
      return AppLocalizationsFr();
    case 'it':
      return AppLocalizationsIt();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}

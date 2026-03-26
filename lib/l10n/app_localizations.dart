import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';

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
  static const List<Locale> supportedLocales = <Locale>[Locale('en')];

  /// App name displayed in app bar and splash screen
  ///
  /// In en, this message translates to:
  /// **'Mostro'**
  String get appTitle;

  /// Generic loading indicator label
  ///
  /// In en, this message translates to:
  /// **'Loading…'**
  String get loading;

  /// Generic error fallback message
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Please try again.'**
  String get errorUnknown;

  /// Retry button label
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// Cancel button label
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// Confirm button label
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirm;

  /// Save button label
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// Done button label
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// Next step button label
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get next;

  /// Back navigation button label
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get back;

  /// Skip optional step button label
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get skip;

  /// Copy to clipboard button label
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get copyToClipboard;

  /// Snackbar message after copying
  ///
  /// In en, this message translates to:
  /// **'Copied to clipboard'**
  String get copiedToClipboard;

  /// Banner shown when app is offline
  ///
  /// In en, this message translates to:
  /// **'You are offline — showing cached data'**
  String get offlineBanner;

  /// Onboarding welcome screen title
  ///
  /// In en, this message translates to:
  /// **'Welcome to Mostro'**
  String get onboardingWelcomeTitle;

  /// Onboarding welcome screen subtitle
  ///
  /// In en, this message translates to:
  /// **'Peer-to-peer bitcoin trading over Nostr'**
  String get onboardingWelcomeSubtitle;

  /// Button to create a new identity
  ///
  /// In en, this message translates to:
  /// **'Create New Identity'**
  String get onboardingCreateIdentity;

  /// Button to import an existing identity
  ///
  /// In en, this message translates to:
  /// **'Import Existing Identity'**
  String get onboardingImportIdentity;

  /// Title on create-identity screen showing mnemonic
  ///
  /// In en, this message translates to:
  /// **'Your Recovery Phrase'**
  String get createIdentityTitle;

  /// Instructions for saving the mnemonic
  ///
  /// In en, this message translates to:
  /// **'Write down these 12 words in order and keep them safe. Anyone with these words can access your identity.'**
  String get createIdentityInstruction;

  /// Checkbox to confirm mnemonic has been saved
  ///
  /// In en, this message translates to:
  /// **'I have safely saved my recovery phrase'**
  String get createIdentityConfirmCheckbox;

  /// CTA button after mnemonic confirmation
  ///
  /// In en, this message translates to:
  /// **'I\'ve Saved My Phrase'**
  String get createIdentityCta;

  /// Title on import-identity screen
  ///
  /// In en, this message translates to:
  /// **'Import Identity'**
  String get importIdentityTitle;

  /// Input label for mnemonic import
  ///
  /// In en, this message translates to:
  /// **'Recovery Phrase (12 or 24 words)'**
  String get importIdentityMnemonicLabel;

  /// Input label for nsec import
  ///
  /// In en, this message translates to:
  /// **'Private Key (nsec…)'**
  String get importIdentityNsecLabel;

  /// Error when mnemonic is invalid
  ///
  /// In en, this message translates to:
  /// **'Invalid recovery phrase — check spelling'**
  String get importIdentityInvalidMnemonic;

  /// Error when nsec format is invalid
  ///
  /// In en, this message translates to:
  /// **'Invalid private key format'**
  String get importIdentityInvalidNsec;

  /// CTA button to confirm identity import
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get importIdentityCta;

  /// Title on PIN setup screen
  ///
  /// In en, this message translates to:
  /// **'Set a PIN'**
  String get pinSetupTitle;

  /// Subtitle explaining PIN purpose
  ///
  /// In en, this message translates to:
  /// **'Protect your identity with a 4–8 digit PIN'**
  String get pinSetupSubtitle;

  /// Label for PIN entry field
  ///
  /// In en, this message translates to:
  /// **'Enter PIN'**
  String get pinSetupEnterPin;

  /// Label for PIN confirmation field
  ///
  /// In en, this message translates to:
  /// **'Confirm PIN'**
  String get pinSetupConfirmPin;

  /// Error when PIN confirmation does not match
  ///
  /// In en, this message translates to:
  /// **'PINs do not match'**
  String get pinSetupMismatch;

  /// Toggle to enable biometrics alongside PIN
  ///
  /// In en, this message translates to:
  /// **'Also enable biometric unlock'**
  String get pinSetupEnableBiometric;

  /// Skip PIN setup (optional)
  ///
  /// In en, this message translates to:
  /// **'Skip (not recommended)'**
  String get pinSetupSkip;

  /// Home screen app bar title
  ///
  /// In en, this message translates to:
  /// **'Orders'**
  String get homeTitle;

  /// Filter tab: show all orders
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get homeFilterAll;

  /// Filter tab: show only buy orders
  ///
  /// In en, this message translates to:
  /// **'Buy'**
  String get homeFilterBuy;

  /// Filter tab: show only sell orders
  ///
  /// In en, this message translates to:
  /// **'Sell'**
  String get homeFilterSell;

  /// Empty state message when no orders match filter
  ///
  /// In en, this message translates to:
  /// **'No orders found'**
  String get homeNoOrders;

  /// Search/filter placeholder for payment method
  ///
  /// In en, this message translates to:
  /// **'Payment method'**
  String get homeSearchPaymentMethod;

  /// Order detail screen title
  ///
  /// In en, this message translates to:
  /// **'Order Details'**
  String get orderDetailTitle;

  /// CTA button to take an order
  ///
  /// In en, this message translates to:
  /// **'Take Order'**
  String get orderDetailTakeOrder;

  /// Message when user tries to take an order while in a trade
  ///
  /// In en, this message translates to:
  /// **'You already have an active trade'**
  String get orderDetailAlreadyInTrade;

  /// Order kind label: buyer wants to buy bitcoin
  ///
  /// In en, this message translates to:
  /// **'Buy'**
  String get orderKindBuy;

  /// Order kind label: seller wants to sell bitcoin
  ///
  /// In en, this message translates to:
  /// **'Sell'**
  String get orderKindSell;

  /// Formatted order fiat amount with currency
  ///
  /// In en, this message translates to:
  /// **'{amount} {currency}'**
  String orderAmount(String amount, String currency);

  /// Formatted order fiat amount range with currency
  ///
  /// In en, this message translates to:
  /// **'{min}–{max} {currency}'**
  String orderAmountRange(String min, String max, String currency);

  /// Order premium percentage label
  ///
  /// In en, this message translates to:
  /// **'{premium}% premium'**
  String orderPremium(String premium);

  /// Trade screen app bar title
  ///
  /// In en, this message translates to:
  /// **'Active Trade'**
  String get tradeTitle;

  /// Button for buyer to confirm fiat payment sent
  ///
  /// In en, this message translates to:
  /// **'I Sent the Fiat'**
  String get tradeFiatSent;

  /// Button for seller to release bitcoin to buyer
  ///
  /// In en, this message translates to:
  /// **'Release Bitcoin'**
  String get tradeRelease;

  /// Button to request cooperative trade cancellation
  ///
  /// In en, this message translates to:
  /// **'Cancel Trade'**
  String get tradeCancel;

  /// Button to open a dispute
  ///
  /// In en, this message translates to:
  /// **'Open Dispute'**
  String get tradeDispute;

  /// Button for buyer to add their Lightning invoice
  ///
  /// In en, this message translates to:
  /// **'Add Lightning Invoice'**
  String get tradeAddInvoice;

  /// Countdown showing when the trade hold invoice expires
  ///
  /// In en, this message translates to:
  /// **'Trade expires in {time}'**
  String tradeTimeout(String time);

  /// Chat input field placeholder
  ///
  /// In en, this message translates to:
  /// **'Message…'**
  String get chatInputHint;

  /// Chat send button label
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get chatSend;

  /// Dispute screen title
  ///
  /// In en, this message translates to:
  /// **'Dispute'**
  String get disputeTitle;

  /// Trade history screen title
  ///
  /// In en, this message translates to:
  /// **'Trade History'**
  String get historyTitle;

  /// Empty state for trade history
  ///
  /// In en, this message translates to:
  /// **'No completed trades yet'**
  String get historyNoTrades;

  /// Trade history outcome: successful
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get historyOutcomeSuccess;

  /// Trade history outcome: canceled
  ///
  /// In en, this message translates to:
  /// **'Canceled'**
  String get historyOutcomeCanceled;

  /// Trade history outcome: disputed
  ///
  /// In en, this message translates to:
  /// **'Disputed'**
  String get historyOutcomeDisputed;

  /// Settings screen title
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// Theme setting label
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get settingsTheme;

  /// Theme option: follow system preference
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get settingsThemeSystem;

  /// Theme option: always light
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get settingsThemeLight;

  /// Theme option: always dark
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get settingsThemeDark;

  /// Language setting label
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingsLanguage;

  /// Relay settings section label
  ///
  /// In en, this message translates to:
  /// **'Relays'**
  String get settingsRelays;

  /// Wallet settings section label
  ///
  /// In en, this message translates to:
  /// **'Lightning Wallet'**
  String get settingsWallet;

  /// Privacy settings section label
  ///
  /// In en, this message translates to:
  /// **'Privacy'**
  String get settingsPrivacy;

  /// Notifications settings section label
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get settingsNotifications;

  /// Toggle to hide sensitive trade info from screenshots
  ///
  /// In en, this message translates to:
  /// **'Privacy Mode'**
  String get settingsPrivacyMode;

  /// Relay connection status: connected
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get relayStatusConnected;

  /// Relay connection status: connecting
  ///
  /// In en, this message translates to:
  /// **'Connecting…'**
  String get relayStatusConnecting;

  /// Relay connection status: disconnected
  ///
  /// In en, this message translates to:
  /// **'Disconnected'**
  String get relayStatusDisconnected;

  /// Relay connection status: error
  ///
  /// In en, this message translates to:
  /// **'Connection error'**
  String get relayStatusError;

  /// Button to connect an NWC wallet
  ///
  /// In en, this message translates to:
  /// **'Connect Wallet'**
  String get walletConnectCta;

  /// Input label for NWC URI
  ///
  /// In en, this message translates to:
  /// **'Wallet connect URI (nostr+walletconnect://…)'**
  String get walletNwcUriLabel;

  /// Error for invalid NWC URI
  ///
  /// In en, this message translates to:
  /// **'Invalid wallet connect URI'**
  String get walletNwcUriInvalid;

  /// Prompt to rate the trading counterparty
  ///
  /// In en, this message translates to:
  /// **'Rate your trade partner'**
  String get rateCounterparty;

  /// Submit rating button label
  ///
  /// In en, this message translates to:
  /// **'Submit Rating'**
  String get rateSubmit;

  /// About screen title
  ///
  /// In en, this message translates to:
  /// **'About Mostro'**
  String get aboutTitle;

  /// App version string on about screen
  ///
  /// In en, this message translates to:
  /// **'Version {version}'**
  String aboutVersion(String version);

  /// Title when landing via deep link to a shared order
  ///
  /// In en, this message translates to:
  /// **'Shared Order'**
  String get sharedOrderTitle;

  /// QR scanner screen title
  ///
  /// In en, this message translates to:
  /// **'Scan QR Code'**
  String get qrScanTitle;

  /// Message when camera permission is denied
  ///
  /// In en, this message translates to:
  /// **'Camera permission is required to scan QR codes'**
  String get qrScanPermissionDenied;

  /// Attachment picker sheet title
  ///
  /// In en, this message translates to:
  /// **'Add Attachment'**
  String get attachmentPickerTitle;

  /// Error when file upload to Blossom fails
  ///
  /// In en, this message translates to:
  /// **'Upload failed — try again'**
  String get attachmentUploadFailed;

  /// PIN unlock screen title
  ///
  /// In en, this message translates to:
  /// **'Enter PIN to unlock'**
  String get pinUnlockTitle;

  /// Error message for wrong PIN
  ///
  /// In en, this message translates to:
  /// **'Incorrect PIN'**
  String get pinUnlockWrong;

  /// Button to use biometric instead of PIN
  ///
  /// In en, this message translates to:
  /// **'Use biometrics'**
  String get pinUnlockBiometric;

  /// Recovery screen title
  ///
  /// In en, this message translates to:
  /// **'Recover Session'**
  String get recoveryTitle;

  /// Instruction on recovery screen
  ///
  /// In en, this message translates to:
  /// **'Enter your recovery phrase to restore your identity'**
  String get recoveryInstruction;
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
      <String>['en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}

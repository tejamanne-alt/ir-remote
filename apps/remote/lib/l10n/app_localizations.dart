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

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'IR Remote'**
  String get appTitle;

  /// No description provided for @onboardingDetecting.
  ///
  /// In en, this message translates to:
  /// **'Checking what this phone can do…'**
  String get onboardingDetecting;

  /// No description provided for @pathEmitterTitle.
  ///
  /// In en, this message translates to:
  /// **'Your phone can send IR'**
  String get pathEmitterTitle;

  /// No description provided for @pathEmitterBody.
  ///
  /// In en, this message translates to:
  /// **'This phone has a built-in IR blaster, so it can control TVs, set-top boxes, ACs and more directly.'**
  String get pathEmitterBody;

  /// No description provided for @pathHubTitle.
  ///
  /// In en, this message translates to:
  /// **'Connect a hub'**
  String get pathHubTitle;

  /// No description provided for @pathHubBodyIos.
  ///
  /// In en, this message translates to:
  /// **'iPhones have no IR blaster. To control appliances, this app needs a compatible Wi-Fi IR hub on your home network.'**
  String get pathHubBodyIos;

  /// No description provided for @pathNoEmitterTitle.
  ///
  /// In en, this message translates to:
  /// **'This phone can\'t send IR. Here\'s what works'**
  String get pathNoEmitterTitle;

  /// No description provided for @pathNoEmitterBody.
  ///
  /// In en, this message translates to:
  /// **'This phone has no IR blaster. You can still use the app with a compatible Wi-Fi IR hub on your home network.'**
  String get pathNoEmitterBody;

  /// No description provided for @supportedHubsTitle.
  ///
  /// In en, this message translates to:
  /// **'Supported hubs'**
  String get supportedHubsTitle;

  /// No description provided for @hubEspBridge.
  ///
  /// In en, this message translates to:
  /// **'IR Bridge (ESP32, build it yourself)'**
  String get hubEspBridge;

  /// No description provided for @hubBroadlink.
  ///
  /// In en, this message translates to:
  /// **'Broadlink RM4 mini (best effort)'**
  String get hubBroadlink;

  /// No description provided for @irBasics.
  ///
  /// In en, this message translates to:
  /// **'Tip: point the phone or hub at the appliance, with a clear line of sight.'**
  String get irBasics;

  /// No description provided for @actionAddFirstDevice.
  ///
  /// In en, this message translates to:
  /// **'Add your first device'**
  String get actionAddFirstDevice;

  /// No description provided for @actionConnectHub.
  ///
  /// In en, this message translates to:
  /// **'Connect a hub'**
  String get actionConnectHub;

  /// No description provided for @actionUseSimulator.
  ///
  /// In en, this message translates to:
  /// **'Use the simulator (debug builds only)'**
  String get actionUseSimulator;

  /// No description provided for @actionContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get actionContinue;

  /// No description provided for @actionLater.
  ///
  /// In en, this message translates to:
  /// **'Later'**
  String get actionLater;

  /// No description provided for @homeTitle.
  ///
  /// In en, this message translates to:
  /// **'Remotes'**
  String get homeTitle;

  /// No description provided for @homeEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No remotes yet'**
  String get homeEmptyTitle;

  /// No description provided for @homeEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'Add a TV, set-top box, AC or other appliance to get started.'**
  String get homeEmptyBody;

  /// No description provided for @actionAddDevice.
  ///
  /// In en, this message translates to:
  /// **'Add device'**
  String get actionAddDevice;

  /// No description provided for @sectionFavourites.
  ///
  /// In en, this message translates to:
  /// **'Favourites'**
  String get sectionFavourites;

  /// No description provided for @sectionRecents.
  ///
  /// In en, this message translates to:
  /// **'Recent'**
  String get sectionRecents;

  /// No description provided for @sectionNoRoom.
  ///
  /// In en, this message translates to:
  /// **'Other devices'**
  String get sectionNoRoom;

  /// No description provided for @noTransportBanner.
  ///
  /// In en, this message translates to:
  /// **'Nothing can send IR yet. Connect a hub to control your devices.'**
  String get noTransportBanner;

  /// No description provided for @menuHubs.
  ///
  /// In en, this message translates to:
  /// **'Hubs'**
  String get menuHubs;

  /// No description provided for @menuSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get menuSettings;

  /// No description provided for @deviceSubtitle.
  ///
  /// In en, this message translates to:
  /// **'{category} · {brand}'**
  String deviceSubtitle(String category, String brand);

  /// No description provided for @categoryTv.
  ///
  /// In en, this message translates to:
  /// **'TV'**
  String get categoryTv;

  /// No description provided for @categorySetTopBox.
  ///
  /// In en, this message translates to:
  /// **'Set-top box'**
  String get categorySetTopBox;

  /// No description provided for @categoryAirConditioner.
  ///
  /// In en, this message translates to:
  /// **'Air conditioner'**
  String get categoryAirConditioner;

  /// No description provided for @categoryFan.
  ///
  /// In en, this message translates to:
  /// **'Fan'**
  String get categoryFan;

  /// No description provided for @categoryProjector.
  ///
  /// In en, this message translates to:
  /// **'Projector'**
  String get categoryProjector;

  /// No description provided for @categorySoundbar.
  ///
  /// In en, this message translates to:
  /// **'Soundbar or AV receiver'**
  String get categorySoundbar;

  /// No description provided for @categoryAirPurifier.
  ///
  /// In en, this message translates to:
  /// **'Air purifier or cooler'**
  String get categoryAirPurifier;

  /// No description provided for @categoryGeneric.
  ///
  /// In en, this message translates to:
  /// **'Custom remote'**
  String get categoryGeneric;

  /// No description provided for @addDeviceTitle.
  ///
  /// In en, this message translates to:
  /// **'Add device'**
  String get addDeviceTitle;

  /// No description provided for @chooseCategory.
  ///
  /// In en, this message translates to:
  /// **'What do you want to control?'**
  String get chooseCategory;

  /// No description provided for @chooseBrand.
  ///
  /// In en, this message translates to:
  /// **'Choose the brand'**
  String get chooseBrand;

  /// No description provided for @searchBrands.
  ///
  /// In en, this message translates to:
  /// **'Search brands'**
  String get searchBrands;

  /// No description provided for @brandNotListed.
  ///
  /// In en, this message translates to:
  /// **'Not listed'**
  String get brandNotListed;

  /// No description provided for @brandNotListedHint.
  ///
  /// In en, this message translates to:
  /// **'Try common codes for this kind of device'**
  String get brandNotListedHint;

  /// No description provided for @noBrandsMatch.
  ///
  /// In en, this message translates to:
  /// **'No brands match \"{query}\".'**
  String noBrandsMatch(String query);

  /// No description provided for @matchingTitle.
  ///
  /// In en, this message translates to:
  /// **'Find the right code'**
  String get matchingTitle;

  /// No description provided for @matchingProgress.
  ///
  /// In en, this message translates to:
  /// **'Set {current} of {total}'**
  String matchingProgress(int current, int total);

  /// No description provided for @matchingPointAt.
  ///
  /// In en, this message translates to:
  /// **'Point at the appliance and tap Send.'**
  String get matchingPointAt;

  /// No description provided for @matchingSend.
  ///
  /// In en, this message translates to:
  /// **'Send {key}'**
  String matchingSend(String key);

  /// No description provided for @matchingDidItRespond.
  ///
  /// In en, this message translates to:
  /// **'Did it respond?'**
  String get matchingDidItRespond;

  /// No description provided for @matchingPowerNote.
  ///
  /// In en, this message translates to:
  /// **'Power is often a toggle, so \"it turned off\" counts as a response.'**
  String get matchingPowerNote;

  /// No description provided for @matchingConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'One more check'**
  String get matchingConfirmTitle;

  /// No description provided for @matchingConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'Now try {key}. Did it respond too?'**
  String matchingConfirmBody(String key);

  /// No description provided for @answerYes.
  ///
  /// In en, this message translates to:
  /// **'Yes'**
  String get answerYes;

  /// No description provided for @answerNo.
  ///
  /// In en, this message translates to:
  /// **'No'**
  String get answerNo;

  /// No description provided for @answerSendAgain.
  ///
  /// In en, this message translates to:
  /// **'Send again'**
  String get answerSendAgain;

  /// No description provided for @matchingAllFailedTitle.
  ///
  /// In en, this message translates to:
  /// **'None of the codes worked'**
  String get matchingAllFailedTitle;

  /// No description provided for @matchingAllFailedBody.
  ///
  /// In en, this message translates to:
  /// **'You can still set up this device:'**
  String get matchingAllFailedBody;

  /// No description provided for @noCodeSets.
  ///
  /// In en, this message translates to:
  /// **'There are no codes for this choice yet.'**
  String get noCodeSets;

  /// No description provided for @optionLearn.
  ///
  /// In en, this message translates to:
  /// **'Learn from your original remote (hub required)'**
  String get optionLearn;

  /// No description provided for @optionImportFlipper.
  ///
  /// In en, this message translates to:
  /// **'Import a Flipper .ir file'**
  String get optionImportFlipper;

  /// No description provided for @optionPastePronto.
  ///
  /// In en, this message translates to:
  /// **'Paste a Pronto Hex code'**
  String get optionPastePronto;

  /// No description provided for @saveDeviceTitle.
  ///
  /// In en, this message translates to:
  /// **'Name your device'**
  String get saveDeviceTitle;

  /// No description provided for @deviceNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get deviceNameLabel;

  /// No description provided for @deviceNameError.
  ///
  /// In en, this message translates to:
  /// **'Enter a name (up to 40 characters).'**
  String get deviceNameError;

  /// No description provided for @roomLabel.
  ///
  /// In en, this message translates to:
  /// **'Room'**
  String get roomLabel;

  /// No description provided for @roomNone.
  ///
  /// In en, this message translates to:
  /// **'No room'**
  String get roomNone;

  /// No description provided for @roomNew.
  ///
  /// In en, this message translates to:
  /// **'New room…'**
  String get roomNew;

  /// No description provided for @roomNewTitle.
  ///
  /// In en, this message translates to:
  /// **'New room'**
  String get roomNewTitle;

  /// No description provided for @actionSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get actionSave;

  /// No description provided for @actionCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get actionCancel;

  /// No description provided for @actionDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get actionDelete;

  /// No description provided for @actionDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get actionDone;

  /// No description provided for @actionAdd.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get actionAdd;

  /// No description provided for @deviceSaved.
  ///
  /// In en, this message translates to:
  /// **'{name} is ready.'**
  String deviceSaved(String name);

  /// No description provided for @keyPower.
  ///
  /// In en, this message translates to:
  /// **'Power'**
  String get keyPower;

  /// No description provided for @keyPowerOn.
  ///
  /// In en, this message translates to:
  /// **'On'**
  String get keyPowerOn;

  /// No description provided for @keyPowerOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get keyPowerOff;

  /// No description provided for @keyInput.
  ///
  /// In en, this message translates to:
  /// **'Input'**
  String get keyInput;

  /// No description provided for @keyVolUp.
  ///
  /// In en, this message translates to:
  /// **'Volume up'**
  String get keyVolUp;

  /// No description provided for @keyVolDown.
  ///
  /// In en, this message translates to:
  /// **'Volume down'**
  String get keyVolDown;

  /// No description provided for @keyMute.
  ///
  /// In en, this message translates to:
  /// **'Mute'**
  String get keyMute;

  /// No description provided for @keyChUp.
  ///
  /// In en, this message translates to:
  /// **'Channel up'**
  String get keyChUp;

  /// No description provided for @keyChDown.
  ///
  /// In en, this message translates to:
  /// **'Channel down'**
  String get keyChDown;

  /// No description provided for @keyUp.
  ///
  /// In en, this message translates to:
  /// **'Up'**
  String get keyUp;

  /// No description provided for @keyDown.
  ///
  /// In en, this message translates to:
  /// **'Down'**
  String get keyDown;

  /// No description provided for @keyLeft.
  ///
  /// In en, this message translates to:
  /// **'Left'**
  String get keyLeft;

  /// No description provided for @keyRight.
  ///
  /// In en, this message translates to:
  /// **'Right'**
  String get keyRight;

  /// No description provided for @keyOk.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get keyOk;

  /// No description provided for @keyBack.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get keyBack;

  /// No description provided for @keyHome.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get keyHome;

  /// No description provided for @keyMenu.
  ///
  /// In en, this message translates to:
  /// **'Menu'**
  String get keyMenu;

  /// No description provided for @keyExit.
  ///
  /// In en, this message translates to:
  /// **'Exit'**
  String get keyExit;

  /// No description provided for @keyGuide.
  ///
  /// In en, this message translates to:
  /// **'Guide'**
  String get keyGuide;

  /// No description provided for @keyInfo.
  ///
  /// In en, this message translates to:
  /// **'Info'**
  String get keyInfo;

  /// No description provided for @keyRed.
  ///
  /// In en, this message translates to:
  /// **'Red'**
  String get keyRed;

  /// No description provided for @keyGreen.
  ///
  /// In en, this message translates to:
  /// **'Green'**
  String get keyGreen;

  /// No description provided for @keyYellow.
  ///
  /// In en, this message translates to:
  /// **'Yellow'**
  String get keyYellow;

  /// No description provided for @keyBlue.
  ///
  /// In en, this message translates to:
  /// **'Blue'**
  String get keyBlue;

  /// No description provided for @keyPlay.
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get keyPlay;

  /// No description provided for @keyPause.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get keyPause;

  /// No description provided for @keyStop.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get keyStop;

  /// No description provided for @keyRewind.
  ///
  /// In en, this message translates to:
  /// **'Rewind'**
  String get keyRewind;

  /// No description provided for @keyFastForward.
  ///
  /// In en, this message translates to:
  /// **'Fast forward'**
  String get keyFastForward;

  /// No description provided for @keyPrevious.
  ///
  /// In en, this message translates to:
  /// **'Previous'**
  String get keyPrevious;

  /// No description provided for @keyNext.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get keyNext;

  /// No description provided for @keyRecord.
  ///
  /// In en, this message translates to:
  /// **'Record'**
  String get keyRecord;

  /// No description provided for @keySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Subtitles'**
  String get keySubtitle;

  /// No description provided for @keyAudio.
  ///
  /// In en, this message translates to:
  /// **'Audio'**
  String get keyAudio;

  /// No description provided for @keyLastChannel.
  ///
  /// In en, this message translates to:
  /// **'Last channel'**
  String get keyLastChannel;

  /// No description provided for @keySpeedUp.
  ///
  /// In en, this message translates to:
  /// **'Speed up'**
  String get keySpeedUp;

  /// No description provided for @keySpeedDown.
  ///
  /// In en, this message translates to:
  /// **'Speed down'**
  String get keySpeedDown;

  /// No description provided for @keySpeed.
  ///
  /// In en, this message translates to:
  /// **'Speed'**
  String get keySpeed;

  /// No description provided for @keyTimer.
  ///
  /// In en, this message translates to:
  /// **'Timer'**
  String get keyTimer;

  /// No description provided for @keySleep.
  ///
  /// In en, this message translates to:
  /// **'Sleep'**
  String get keySleep;

  /// No description provided for @keyLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get keyLight;

  /// No description provided for @keySwing.
  ///
  /// In en, this message translates to:
  /// **'Swing'**
  String get keySwing;

  /// No description provided for @keyOscillate.
  ///
  /// In en, this message translates to:
  /// **'Oscillate'**
  String get keyOscillate;

  /// No description provided for @keyMode.
  ///
  /// In en, this message translates to:
  /// **'Mode'**
  String get keyMode;

  /// No description provided for @keyFocusIn.
  ///
  /// In en, this message translates to:
  /// **'Focus in'**
  String get keyFocusIn;

  /// No description provided for @keyFocusOut.
  ///
  /// In en, this message translates to:
  /// **'Focus out'**
  String get keyFocusOut;

  /// No description provided for @keyKeystoneUp.
  ///
  /// In en, this message translates to:
  /// **'Keystone up'**
  String get keyKeystoneUp;

  /// No description provided for @keyKeystoneDown.
  ///
  /// In en, this message translates to:
  /// **'Keystone down'**
  String get keyKeystoneDown;

  /// No description provided for @keySoundMode.
  ///
  /// In en, this message translates to:
  /// **'Sound mode'**
  String get keySoundMode;

  /// No description provided for @keyTempUp.
  ///
  /// In en, this message translates to:
  /// **'Temperature up'**
  String get keyTempUp;

  /// No description provided for @keyTempDown.
  ///
  /// In en, this message translates to:
  /// **'Temperature down'**
  String get keyTempDown;

  /// No description provided for @keyDigit.
  ///
  /// In en, this message translates to:
  /// **'Digit {digit}'**
  String keyDigit(int digit);

  /// No description provided for @keyVolumeShort.
  ///
  /// In en, this message translates to:
  /// **'Vol'**
  String get keyVolumeShort;

  /// No description provided for @keyChannelShort.
  ///
  /// In en, this message translates to:
  /// **'Ch'**
  String get keyChannelShort;

  /// No description provided for @remoteMissingKey.
  ///
  /// In en, this message translates to:
  /// **'{key} (no code)'**
  String remoteMissingKey(String key);

  /// No description provided for @remoteMoreKeys.
  ///
  /// In en, this message translates to:
  /// **'More keys'**
  String get remoteMoreKeys;

  /// No description provided for @remoteNumbers.
  ///
  /// In en, this message translates to:
  /// **'Numbers'**
  String get remoteNumbers;

  /// No description provided for @remoteNoKeys.
  ///
  /// In en, this message translates to:
  /// **'This remote has no buttons yet.'**
  String get remoteNoKeys;

  /// No description provided for @deviceMenuRename.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get deviceMenuRename;

  /// No description provided for @deviceMenuDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get deviceMenuDelete;

  /// No description provided for @deviceMenuFavourite.
  ///
  /// In en, this message translates to:
  /// **'Add to favourites'**
  String get deviceMenuFavourite;

  /// No description provided for @deviceMenuUnfavourite.
  ///
  /// In en, this message translates to:
  /// **'Remove from favourites'**
  String get deviceMenuUnfavourite;

  /// No description provided for @deviceMenuTransport.
  ///
  /// In en, this message translates to:
  /// **'Send through'**
  String get deviceMenuTransport;

  /// No description provided for @deviceMenuLearn.
  ///
  /// In en, this message translates to:
  /// **'Learn a button'**
  String get deviceMenuLearn;

  /// No description provided for @deviceMenuPronto.
  ///
  /// In en, this message translates to:
  /// **'Add a Pronto Hex button'**
  String get deviceMenuPronto;

  /// No description provided for @deviceDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete {name}?'**
  String deviceDeleteConfirm(String name);

  /// No description provided for @deviceDeleteBody.
  ///
  /// In en, this message translates to:
  /// **'This removes the remote and its codes from this phone.'**
  String get deviceDeleteBody;

  /// No description provided for @transportAuto.
  ///
  /// In en, this message translates to:
  /// **'Automatic'**
  String get transportAuto;

  /// No description provided for @resultNoTransport.
  ///
  /// In en, this message translates to:
  /// **'Nothing can send IR. Connect a hub, or use a phone with an IR blaster.'**
  String get resultNoTransport;

  /// No description provided for @resultUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t reach {transport}: {detail}'**
  String resultUnavailable(String transport, String detail);

  /// No description provided for @resultTimeout.
  ///
  /// In en, this message translates to:
  /// **'{transport} didn\'t respond in time. Check it is powered on and on the same Wi-Fi.'**
  String resultTimeout(String transport);

  /// No description provided for @resultCarrier.
  ///
  /// In en, this message translates to:
  /// **'{transport} can\'t send this code\'s carrier frequency.'**
  String resultCarrier(String transport);

  /// No description provided for @resultTooLong.
  ///
  /// In en, this message translates to:
  /// **'This code is too long for {transport}.'**
  String resultTooLong(String transport);

  /// No description provided for @resultInvalid.
  ///
  /// In en, this message translates to:
  /// **'This code is damaged and can\'t be sent.'**
  String get resultInvalid;

  /// No description provided for @resultRefused.
  ///
  /// In en, this message translates to:
  /// **'{transport} refused the code: {detail}'**
  String resultRefused(String transport, String detail);

  /// No description provided for @resultHardware.
  ///
  /// In en, this message translates to:
  /// **'{transport} reported an error: {detail}'**
  String resultHardware(String transport, String detail);

  /// No description provided for @resultSentTo.
  ///
  /// In en, this message translates to:
  /// **'Sent through {transport}'**
  String resultSentTo(String transport);

  /// No description provided for @hubsTitle.
  ///
  /// In en, this message translates to:
  /// **'Hubs'**
  String get hubsTitle;

  /// No description provided for @hubsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No hubs yet.'**
  String get hubsEmpty;

  /// No description provided for @hubAdd.
  ///
  /// In en, this message translates to:
  /// **'Add hub'**
  String get hubAdd;

  /// No description provided for @hubDiscovering.
  ///
  /// In en, this message translates to:
  /// **'Looking for IR Bridges on this Wi-Fi…'**
  String get hubDiscovering;

  /// No description provided for @hubFound.
  ///
  /// In en, this message translates to:
  /// **'Found on your network'**
  String get hubFound;

  /// No description provided for @hubNoneFound.
  ///
  /// In en, this message translates to:
  /// **'No bridges found yet. You can enter an address instead.'**
  String get hubNoneFound;

  /// No description provided for @hubManual.
  ///
  /// In en, this message translates to:
  /// **'Enter an address'**
  String get hubManual;

  /// No description provided for @hubAddressLabel.
  ///
  /// In en, this message translates to:
  /// **'IP address'**
  String get hubAddressLabel;

  /// No description provided for @hubAddressError.
  ///
  /// In en, this message translates to:
  /// **'Enter an IPv4 address such as 192.168.1.40.'**
  String get hubAddressError;

  /// No description provided for @hubTypeLabel.
  ///
  /// In en, this message translates to:
  /// **'Hub type'**
  String get hubTypeLabel;

  /// No description provided for @hubPairTitle.
  ///
  /// In en, this message translates to:
  /// **'Pair with {name}'**
  String hubPairTitle(String name);

  /// No description provided for @hubPairBody.
  ///
  /// In en, this message translates to:
  /// **'Press the button on the bridge, then tap Pair within 60 seconds.'**
  String get hubPairBody;

  /// No description provided for @hubPair.
  ///
  /// In en, this message translates to:
  /// **'Pair'**
  String get hubPair;

  /// No description provided for @hubPaired.
  ///
  /// In en, this message translates to:
  /// **'{name} is connected.'**
  String hubPaired(String name);

  /// No description provided for @hubPairFailed.
  ///
  /// In en, this message translates to:
  /// **'Pairing failed: {detail}'**
  String hubPairFailed(String detail);

  /// No description provided for @hubPairWindowClosed.
  ///
  /// In en, this message translates to:
  /// **'The bridge\'s pairing window is closed. Press its button and try again.'**
  String get hubPairWindowClosed;

  /// No description provided for @hubHealthy.
  ///
  /// In en, this message translates to:
  /// **'Online'**
  String get hubHealthy;

  /// No description provided for @hubDegraded.
  ///
  /// In en, this message translates to:
  /// **'Needs attention: {reason}'**
  String hubDegraded(String reason);

  /// No description provided for @hubUnreachable.
  ///
  /// In en, this message translates to:
  /// **'Offline: {reason}'**
  String hubUnreachable(String reason);

  /// No description provided for @hubChecking.
  ///
  /// In en, this message translates to:
  /// **'Checking…'**
  String get hubChecking;

  /// No description provided for @hubRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove hub'**
  String get hubRemove;

  /// No description provided for @hubRemoveConfirm.
  ///
  /// In en, this message translates to:
  /// **'Remove {name}? Remotes that use it switch to automatic.'**
  String hubRemoveConfirm(String name);

  /// No description provided for @hubCheckNow.
  ///
  /// In en, this message translates to:
  /// **'Check now'**
  String get hubCheckNow;

  /// No description provided for @localNetworkDeniedTitle.
  ///
  /// In en, this message translates to:
  /// **'Allow local network access'**
  String get localNetworkDeniedTitle;

  /// No description provided for @localNetworkDeniedBody.
  ///
  /// In en, this message translates to:
  /// **'The app couldn\'t see devices on your Wi-Fi. On iPhone, open Settings, find this app and turn on Local Network.'**
  String get localNetworkDeniedBody;

  /// No description provided for @broadlinkNote.
  ///
  /// In en, this message translates to:
  /// **'Broadlink support is best effort. Keep the hub connected to your Wi-Fi as usual.'**
  String get broadlinkNote;

  /// No description provided for @broadlinkAddFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t connect to the Broadlink hub: {detail}'**
  String broadlinkAddFailed(String detail);

  /// No description provided for @builtInEmitter.
  ///
  /// In en, this message translates to:
  /// **'This phone\'s IR blaster'**
  String get builtInEmitter;

  /// No description provided for @simulatorName.
  ///
  /// In en, this message translates to:
  /// **'Simulator'**
  String get simulatorName;

  /// No description provided for @hubKindEsp.
  ///
  /// In en, this message translates to:
  /// **'IR Bridge'**
  String get hubKindEsp;

  /// No description provided for @hubKindBroadlink.
  ///
  /// In en, this message translates to:
  /// **'Broadlink'**
  String get hubKindBroadlink;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @settingsTheme.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get settingsTheme;

  /// No description provided for @themeSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get themeSystem;

  /// No description provided for @themeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get themeLight;

  /// No description provided for @themeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get themeDark;

  /// No description provided for @settingsTemperatureUnit.
  ///
  /// In en, this message translates to:
  /// **'Temperature unit'**
  String get settingsTemperatureUnit;

  /// No description provided for @unitCelsius.
  ///
  /// In en, this message translates to:
  /// **'°C'**
  String get unitCelsius;

  /// No description provided for @unitFahrenheit.
  ///
  /// In en, this message translates to:
  /// **'°F'**
  String get unitFahrenheit;

  /// No description provided for @settingsAbout.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get settingsAbout;

  /// No description provided for @settingsLicenses.
  ///
  /// In en, this message translates to:
  /// **'Licenses'**
  String get settingsLicenses;

  /// No description provided for @settingsPrivacy.
  ///
  /// In en, this message translates to:
  /// **'Privacy'**
  String get settingsPrivacy;

  /// No description provided for @settingsDebug.
  ///
  /// In en, this message translates to:
  /// **'Developer'**
  String get settingsDebug;

  /// No description provided for @settingsSignalInspector.
  ///
  /// In en, this message translates to:
  /// **'Signal Inspector'**
  String get settingsSignalInspector;

  /// No description provided for @settingsSimulator.
  ///
  /// In en, this message translates to:
  /// **'Use the simulator transport'**
  String get settingsSimulator;

  /// No description provided for @settingsUnverifiedAc.
  ///
  /// In en, this message translates to:
  /// **'Show unverified AC encoders'**
  String get settingsUnverifiedAc;

  /// No description provided for @settingsBackup.
  ///
  /// In en, this message translates to:
  /// **'Backup and restore'**
  String get settingsBackup;

  /// No description provided for @aboutBody.
  ///
  /// In en, this message translates to:
  /// **'An IR universal remote. Works offline; nothing leaves this phone.'**
  String get aboutBody;

  /// No description provided for @aboutNoAffiliation.
  ///
  /// In en, this message translates to:
  /// **'Brand names are used only to describe compatibility. This app is not affiliated with, or endorsed by, any appliance manufacturer.'**
  String get aboutNoAffiliation;

  /// No description provided for @aboutVersion.
  ///
  /// In en, this message translates to:
  /// **'Version {version}'**
  String aboutVersion(String version);

  /// No description provided for @privacyBody.
  ///
  /// In en, this message translates to:
  /// **'This app has no account, no ads and no analytics. Your remotes, AC settings and learned codes stay on this phone unless you export them yourself.'**
  String get privacyBody;

  /// No description provided for @licensesDataSources.
  ///
  /// In en, this message translates to:
  /// **'IR code sources'**
  String get licensesDataSources;

  /// No description provided for @licensesPackages.
  ///
  /// In en, this message translates to:
  /// **'Open-source packages'**
  String get licensesPackages;

  /// No description provided for @licensesNoDataSources.
  ///
  /// In en, this message translates to:
  /// **'No IR code database is bundled in this build.'**
  String get licensesNoDataSources;

  /// No description provided for @inspectorTitle.
  ///
  /// In en, this message translates to:
  /// **'Signal Inspector'**
  String get inspectorTitle;

  /// No description provided for @inspectorEmpty.
  ///
  /// In en, this message translates to:
  /// **'No signals sent yet.'**
  String get inspectorEmpty;

  /// No description provided for @inspectorTip.
  ///
  /// In en, this message translates to:
  /// **'Tip: many phone front cameras show an IR LED flashing.'**
  String get inspectorTip;

  /// No description provided for @inspectorExport.
  ///
  /// In en, this message translates to:
  /// **'Copy as JSON'**
  String get inspectorExport;

  /// No description provided for @inspectorCopied.
  ///
  /// In en, this message translates to:
  /// **'Copied {count} signals.'**
  String inspectorCopied(int count);

  /// No description provided for @inspectorEntry.
  ///
  /// In en, this message translates to:
  /// **'{carrier} Hz · {count} durations · {total} µs'**
  String inspectorEntry(int carrier, int count, int total);

  /// No description provided for @acLastSent.
  ///
  /// In en, this message translates to:
  /// **'Last sent {time}, as sent from this phone'**
  String acLastSent(String time);

  /// No description provided for @acNeverSent.
  ///
  /// In en, this message translates to:
  /// **'Not sent yet. The app can\'t read the AC; it shows what it last sent.'**
  String get acNeverSent;

  /// No description provided for @acResync.
  ///
  /// In en, this message translates to:
  /// **'Re-sync'**
  String get acResync;

  /// No description provided for @acResyncHint.
  ///
  /// In en, this message translates to:
  /// **'Sends the whole state again'**
  String get acResyncHint;

  /// No description provided for @acPowerOn.
  ///
  /// In en, this message translates to:
  /// **'On'**
  String get acPowerOn;

  /// No description provided for @acPowerOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get acPowerOff;

  /// No description provided for @acPowerToggle.
  ///
  /// In en, this message translates to:
  /// **'Power'**
  String get acPowerToggle;

  /// No description provided for @acPowerToggleWarning.
  ///
  /// In en, this message translates to:
  /// **'This AC uses a power toggle. If it is already on, this turns it off.'**
  String get acPowerToggleWarning;

  /// No description provided for @acModeAuto.
  ///
  /// In en, this message translates to:
  /// **'Auto'**
  String get acModeAuto;

  /// No description provided for @acModeCool.
  ///
  /// In en, this message translates to:
  /// **'Cool'**
  String get acModeCool;

  /// No description provided for @acModeDry.
  ///
  /// In en, this message translates to:
  /// **'Dry'**
  String get acModeDry;

  /// No description provided for @acModeFan.
  ///
  /// In en, this message translates to:
  /// **'Fan'**
  String get acModeFan;

  /// No description provided for @acModeHeat.
  ///
  /// In en, this message translates to:
  /// **'Heat'**
  String get acModeHeat;

  /// No description provided for @acMode.
  ///
  /// In en, this message translates to:
  /// **'Mode'**
  String get acMode;

  /// No description provided for @acFan.
  ///
  /// In en, this message translates to:
  /// **'Fan'**
  String get acFan;

  /// No description provided for @acFanAuto.
  ///
  /// In en, this message translates to:
  /// **'Auto'**
  String get acFanAuto;

  /// No description provided for @acFanLevel.
  ///
  /// In en, this message translates to:
  /// **'Level {level}'**
  String acFanLevel(int level);

  /// No description provided for @acTemperature.
  ///
  /// In en, this message translates to:
  /// **'Target temperature'**
  String get acTemperature;

  /// No description provided for @acTempUp.
  ///
  /// In en, this message translates to:
  /// **'Raise temperature'**
  String get acTempUp;

  /// No description provided for @acTempDown.
  ///
  /// In en, this message translates to:
  /// **'Lower temperature'**
  String get acTempDown;

  /// No description provided for @acSwingV.
  ///
  /// In en, this message translates to:
  /// **'Swing'**
  String get acSwingV;

  /// No description provided for @acSwingH.
  ///
  /// In en, this message translates to:
  /// **'Horizontal swing'**
  String get acSwingH;

  /// No description provided for @acTurbo.
  ///
  /// In en, this message translates to:
  /// **'Turbo'**
  String get acTurbo;

  /// No description provided for @acEco.
  ///
  /// In en, this message translates to:
  /// **'Eco'**
  String get acEco;

  /// No description provided for @acSleep.
  ///
  /// In en, this message translates to:
  /// **'Sleep'**
  String get acSleep;

  /// No description provided for @acQuiet.
  ///
  /// In en, this message translates to:
  /// **'Quiet'**
  String get acQuiet;

  /// No description provided for @acLight.
  ///
  /// In en, this message translates to:
  /// **'Display light'**
  String get acLight;

  /// No description provided for @acClean.
  ///
  /// In en, this message translates to:
  /// **'Clean'**
  String get acClean;

  /// No description provided for @acPressToToggle.
  ///
  /// In en, this message translates to:
  /// **'press to toggle'**
  String get acPressToToggle;

  /// No description provided for @acUnverifiedTitle.
  ///
  /// In en, this message translates to:
  /// **'Your AC\'s codes aren\'t verified yet'**
  String get acUnverifiedTitle;

  /// No description provided for @acUnverifiedBody.
  ///
  /// In en, this message translates to:
  /// **'AC protocols are verified brand by brand against real remotes. Until yours is, learn its buttons from the original remote.'**
  String get acUnverifiedBody;

  /// No description provided for @acUnverifiedBadge.
  ///
  /// In en, this message translates to:
  /// **'Unverified encoder'**
  String get acUnverifiedBadge;

  /// No description provided for @acVariantProgress.
  ///
  /// In en, this message translates to:
  /// **'Variant {current} of {total}'**
  String acVariantProgress(int current, int total);

  /// No description provided for @acVariantPrompt.
  ///
  /// In en, this message translates to:
  /// **'We\'ll send: on, cool, 24 °C, auto fan. Did the AC beep or change?'**
  String get acVariantPrompt;

  /// No description provided for @acTemperatureValue.
  ///
  /// In en, this message translates to:
  /// **'{value}°'**
  String acTemperatureValue(String value);

  /// No description provided for @learnTitle.
  ///
  /// In en, this message translates to:
  /// **'Learn a button'**
  String get learnTitle;

  /// No description provided for @learnPrompt.
  ///
  /// In en, this message translates to:
  /// **'Point your original remote at the hub and press the button.'**
  String get learnPrompt;

  /// No description provided for @learnWaiting.
  ///
  /// In en, this message translates to:
  /// **'Waiting for a signal…'**
  String get learnWaiting;

  /// No description provided for @learnTimeout.
  ///
  /// In en, this message translates to:
  /// **'No signal arrived. Point the remote at the hub and try again.'**
  String get learnTimeout;

  /// No description provided for @learnError.
  ///
  /// In en, this message translates to:
  /// **'Learning stopped: {detail}'**
  String learnError(String detail);

  /// No description provided for @learnRetry.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get learnRetry;

  /// No description provided for @learnCaptured.
  ///
  /// In en, this message translates to:
  /// **'Got it.'**
  String get learnCaptured;

  /// No description provided for @learnDecoded.
  ///
  /// In en, this message translates to:
  /// **'Recognised as {protocol}'**
  String learnDecoded(String protocol);

  /// No description provided for @learnRaw.
  ///
  /// In en, this message translates to:
  /// **'Saved as a raw signal'**
  String get learnRaw;

  /// No description provided for @learnNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Button name'**
  String get learnNameLabel;

  /// No description provided for @learnTest.
  ///
  /// In en, this message translates to:
  /// **'Test'**
  String get learnTest;

  /// No description provided for @learnNoHub.
  ///
  /// In en, this message translates to:
  /// **'Learning needs a hub with an IR receiver, such as the IR Bridge.'**
  String get learnNoHub;

  /// No description provided for @learnStart.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get learnStart;

  /// No description provided for @prontoTitle.
  ///
  /// In en, this message translates to:
  /// **'Paste Pronto Hex'**
  String get prontoTitle;

  /// No description provided for @prontoHint.
  ///
  /// In en, this message translates to:
  /// **'0000 006D 0022 0002 …'**
  String get prontoHint;

  /// No description provided for @prontoInvalid.
  ///
  /// In en, this message translates to:
  /// **'That isn\'t a valid Pronto code: {detail}'**
  String prontoInvalid(String detail);

  /// No description provided for @prontoKeyLabel.
  ///
  /// In en, this message translates to:
  /// **'Button'**
  String get prontoKeyLabel;

  /// No description provided for @importFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t import the file: {detail}'**
  String importFailed(String detail);

  /// No description provided for @importedKeys.
  ///
  /// In en, this message translates to:
  /// **'Imported {count} buttons.'**
  String importedKeys(int count);

  /// No description provided for @genericDeviceName.
  ///
  /// In en, this message translates to:
  /// **'My remote'**
  String get genericDeviceName;

  /// No description provided for @menuMacros.
  ///
  /// In en, this message translates to:
  /// **'Macros'**
  String get menuMacros;

  /// No description provided for @macrosTitle.
  ///
  /// In en, this message translates to:
  /// **'Macros'**
  String get macrosTitle;

  /// No description provided for @macrosEmpty.
  ///
  /// In en, this message translates to:
  /// **'No macros yet. A macro sends several buttons in order, for example \"TV on, then set-top box on\".'**
  String get macrosEmpty;

  /// No description provided for @macroNew.
  ///
  /// In en, this message translates to:
  /// **'New macro'**
  String get macroNew;

  /// No description provided for @macroEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit macro'**
  String get macroEdit;

  /// No description provided for @macroName.
  ///
  /// In en, this message translates to:
  /// **'Macro name'**
  String get macroName;

  /// No description provided for @macroStepCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 step} other{{count} steps}}'**
  String macroStepCount(int count);

  /// No description provided for @macroRun.
  ///
  /// In en, this message translates to:
  /// **'Run'**
  String get macroRun;

  /// No description provided for @macroAddStep.
  ///
  /// In en, this message translates to:
  /// **'Add step'**
  String get macroAddStep;

  /// No description provided for @macroDevice.
  ///
  /// In en, this message translates to:
  /// **'Remote'**
  String get macroDevice;

  /// No description provided for @macroKey.
  ///
  /// In en, this message translates to:
  /// **'Button'**
  String get macroKey;

  /// No description provided for @macroDelay.
  ///
  /// In en, this message translates to:
  /// **'Then wait'**
  String get macroDelay;

  /// No description provided for @macroDelaySeconds.
  ///
  /// In en, this message translates to:
  /// **'{seconds} s'**
  String macroDelaySeconds(String seconds);

  /// No description provided for @macroStarting.
  ///
  /// In en, this message translates to:
  /// **'Starting…'**
  String get macroStarting;

  /// No description provided for @macroProgress.
  ///
  /// In en, this message translates to:
  /// **'Step {current} of {total}'**
  String macroProgress(int current, int total);

  /// No description provided for @macroDone.
  ///
  /// In en, this message translates to:
  /// **'Done.'**
  String get macroDone;

  /// No description provided for @macroCancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled. Later steps were not sent.'**
  String get macroCancelled;

  /// No description provided for @macroMissingDevice.
  ///
  /// In en, this message translates to:
  /// **'Stopped at step {step}: its remote was deleted.'**
  String macroMissingDevice(int step);

  /// No description provided for @macroFailed.
  ///
  /// In en, this message translates to:
  /// **'Stopped at step {step}: {detail}'**
  String macroFailed(int step, String detail);

  /// No description provided for @backupBody.
  ///
  /// In en, this message translates to:
  /// **'A backup file holds your remotes, rooms, hubs, macros and settings. Hub pairings are not included; pair hubs again after restoring.'**
  String get backupBody;

  /// No description provided for @backupExport.
  ///
  /// In en, this message translates to:
  /// **'Export a backup'**
  String get backupExport;

  /// No description provided for @backupExported.
  ///
  /// In en, this message translates to:
  /// **'Backup ready to save or share.'**
  String get backupExported;

  /// No description provided for @backupRestore.
  ///
  /// In en, this message translates to:
  /// **'Restore from a backup'**
  String get backupRestore;

  /// No description provided for @backupRestoreConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Replace everything?'**
  String get backupRestoreConfirmTitle;

  /// No description provided for @backupRestoreConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'Restoring replaces all remotes, rooms, hubs, macros and settings on this phone with the backup.'**
  String get backupRestoreConfirmBody;

  /// No description provided for @backupRestored.
  ///
  /// In en, this message translates to:
  /// **'Restored.'**
  String get backupRestored;

  /// No description provided for @editButtonsTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit buttons'**
  String get editButtonsTitle;

  /// No description provided for @editButtonsHint.
  ///
  /// In en, this message translates to:
  /// **'Drag to reorder. Rename or delete buttons, or add new ones below.'**
  String get editButtonsHint;

  /// No description provided for @deviceMenuEditButtons.
  ///
  /// In en, this message translates to:
  /// **'Edit buttons'**
  String get deviceMenuEditButtons;

  /// No description provided for @keySourceDatabase.
  ///
  /// In en, this message translates to:
  /// **'From the code database'**
  String get keySourceDatabase;

  /// No description provided for @keySourceLearned.
  ///
  /// In en, this message translates to:
  /// **'Learned from your remote'**
  String get keySourceLearned;

  /// No description provided for @keySourceImported.
  ///
  /// In en, this message translates to:
  /// **'Imported'**
  String get keySourceImported;

  /// No description provided for @nameTooLong.
  ///
  /// In en, this message translates to:
  /// **'Too long: use at most {max} characters (emoji count as two or more).'**
  String nameTooLong(int max);

  /// No description provided for @nameSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'That name couldn\'t be saved. Try a shorter one.'**
  String get nameSaveFailed;

  /// No description provided for @learnEnded.
  ///
  /// In en, this message translates to:
  /// **'The hub stopped listening before a signal arrived. Try again.'**
  String get learnEnded;

  /// No description provided for @transportThisPhone.
  ///
  /// In en, this message translates to:
  /// **'This phone'**
  String get transportThisPhone;

  /// No description provided for @resultBuiltInNoEmitter.
  ///
  /// In en, this message translates to:
  /// **'This phone has no IR blaster.'**
  String get resultBuiltInNoEmitter;

  /// No description provided for @resultBuiltInPermission.
  ///
  /// In en, this message translates to:
  /// **'This phone didn\'t allow the app to use its IR blaster.'**
  String get resultBuiltInPermission;

  /// No description provided for @resultBuiltInUnavailable.
  ///
  /// In en, this message translates to:
  /// **'This phone\'s IR blaster isn\'t available in this version of the app.'**
  String get resultBuiltInUnavailable;

  /// No description provided for @importNotText.
  ///
  /// In en, this message translates to:
  /// **'it isn\'t a text file (UTF-8).'**
  String get importNotText;

  /// No description provided for @importTooLarge.
  ///
  /// In en, this message translates to:
  /// **'the file is larger than 5 MB.'**
  String get importTooLarge;

  /// No description provided for @importUnreadable.
  ///
  /// In en, this message translates to:
  /// **'the file couldn\'t be read.'**
  String get importUnreadable;

  /// No description provided for @hubAlreadyAdded.
  ///
  /// In en, this message translates to:
  /// **'{host} · Already added'**
  String hubAlreadyAdded(String host);

  /// No description provided for @hubUpdated.
  ///
  /// In en, this message translates to:
  /// **'{name}\'s address is updated.'**
  String hubUpdated(String name);

  /// No description provided for @backupExportFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t create the backup file. Try again.'**
  String get backupExportFailed;

  /// No description provided for @backupRestoreFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t restore the backup. Nothing was changed.'**
  String get backupRestoreFailed;
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
    'that was used.',
  );
}

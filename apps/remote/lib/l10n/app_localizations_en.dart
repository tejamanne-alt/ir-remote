// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'IR Remote';

  @override
  String get onboardingDetecting => 'Checking what this phone can do…';

  @override
  String get pathEmitterTitle => 'Your phone can send IR';

  @override
  String get pathEmitterBody =>
      'This phone has a built-in IR blaster, so it can control TVs, set-top boxes, ACs and more directly.';

  @override
  String get pathHubTitle => 'Connect a hub';

  @override
  String get pathHubBodyIos =>
      'iPhones have no IR blaster. To control appliances, this app needs a compatible Wi-Fi IR hub on your home network.';

  @override
  String get pathNoEmitterTitle =>
      'This phone can\'t send IR. Here\'s what works';

  @override
  String get pathNoEmitterBody =>
      'This phone has no IR blaster. You can still use the app with a compatible Wi-Fi IR hub on your home network.';

  @override
  String get supportedHubsTitle => 'Supported hubs';

  @override
  String get hubEspBridge => 'IR Bridge (ESP32, build it yourself)';

  @override
  String get hubBroadlink => 'Broadlink RM4 mini (best effort)';

  @override
  String get irBasics =>
      'Tip: point the phone or hub at the appliance, with a clear line of sight.';

  @override
  String get actionAddFirstDevice => 'Add your first device';

  @override
  String get actionConnectHub => 'Connect a hub';

  @override
  String get actionUseSimulator => 'Use the simulator (debug builds only)';

  @override
  String get actionContinue => 'Continue';

  @override
  String get actionLater => 'Later';

  @override
  String get homeTitle => 'Remotes';

  @override
  String get homeEmptyTitle => 'No remotes yet';

  @override
  String get homeEmptyBody =>
      'Add a TV, set-top box, AC or other appliance to get started.';

  @override
  String get actionAddDevice => 'Add device';

  @override
  String get sectionFavourites => 'Favourites';

  @override
  String get sectionRecents => 'Recent';

  @override
  String get sectionNoRoom => 'Other devices';

  @override
  String get noTransportBanner =>
      'Nothing can send IR yet. Connect a hub to control your devices.';

  @override
  String get menuHubs => 'Hubs';

  @override
  String get menuSettings => 'Settings';

  @override
  String deviceSubtitle(String category, String brand) {
    return '$category · $brand';
  }

  @override
  String get categoryTv => 'TV';

  @override
  String get categorySetTopBox => 'Set-top box';

  @override
  String get categoryAirConditioner => 'Air conditioner';

  @override
  String get categoryFan => 'Fan';

  @override
  String get categoryProjector => 'Projector';

  @override
  String get categorySoundbar => 'Soundbar or AV receiver';

  @override
  String get categoryAirPurifier => 'Air purifier or cooler';

  @override
  String get categoryGeneric => 'Custom remote';

  @override
  String get addDeviceTitle => 'Add device';

  @override
  String get chooseCategory => 'What do you want to control?';

  @override
  String get chooseBrand => 'Choose the brand';

  @override
  String get searchBrands => 'Search brands';

  @override
  String get brandNotListed => 'Not listed';

  @override
  String get brandNotListedHint => 'Try common codes for this kind of device';

  @override
  String noBrandsMatch(String query) {
    return 'No brands match \"$query\".';
  }

  @override
  String get matchingTitle => 'Find the right code';

  @override
  String matchingProgress(int current, int total) {
    return 'Set $current of $total';
  }

  @override
  String get matchingPointAt => 'Point at the appliance and tap Send.';

  @override
  String matchingSend(String key) {
    return 'Send $key';
  }

  @override
  String get matchingDidItRespond => 'Did it respond?';

  @override
  String get matchingPowerNote =>
      'Power is often a toggle, so \"it turned off\" counts as a response.';

  @override
  String get matchingConfirmTitle => 'One more check';

  @override
  String matchingConfirmBody(String key) {
    return 'Now try $key. Did it respond too?';
  }

  @override
  String get answerYes => 'Yes';

  @override
  String get answerNo => 'No';

  @override
  String get answerSendAgain => 'Send again';

  @override
  String get matchingAllFailedTitle => 'None of the codes worked';

  @override
  String get matchingAllFailedBody => 'You can still set up this device:';

  @override
  String get noCodeSets => 'There are no codes for this choice yet.';

  @override
  String get optionLearn => 'Learn from your original remote (hub required)';

  @override
  String get optionImportFlipper => 'Import a Flipper .ir file';

  @override
  String get optionPastePronto => 'Paste a Pronto Hex code';

  @override
  String get saveDeviceTitle => 'Name your device';

  @override
  String get deviceNameLabel => 'Name';

  @override
  String get deviceNameError => 'Enter a name (up to 40 characters).';

  @override
  String get roomLabel => 'Room';

  @override
  String get roomNone => 'No room';

  @override
  String get roomNew => 'New room…';

  @override
  String get roomNewTitle => 'New room';

  @override
  String get actionSave => 'Save';

  @override
  String get actionCancel => 'Cancel';

  @override
  String get actionDelete => 'Delete';

  @override
  String get actionDone => 'Done';

  @override
  String get actionAdd => 'Add';

  @override
  String deviceSaved(String name) {
    return '$name is ready.';
  }

  @override
  String get keyPower => 'Power';

  @override
  String get keyPowerOn => 'On';

  @override
  String get keyPowerOff => 'Off';

  @override
  String get keyInput => 'Input';

  @override
  String get keyVolUp => 'Volume up';

  @override
  String get keyVolDown => 'Volume down';

  @override
  String get keyMute => 'Mute';

  @override
  String get keyChUp => 'Channel up';

  @override
  String get keyChDown => 'Channel down';

  @override
  String get keyUp => 'Up';

  @override
  String get keyDown => 'Down';

  @override
  String get keyLeft => 'Left';

  @override
  String get keyRight => 'Right';

  @override
  String get keyOk => 'OK';

  @override
  String get keyBack => 'Back';

  @override
  String get keyHome => 'Home';

  @override
  String get keyMenu => 'Menu';

  @override
  String get keyExit => 'Exit';

  @override
  String get keyGuide => 'Guide';

  @override
  String get keyInfo => 'Info';

  @override
  String get keyRed => 'Red';

  @override
  String get keyGreen => 'Green';

  @override
  String get keyYellow => 'Yellow';

  @override
  String get keyBlue => 'Blue';

  @override
  String get keyPlay => 'Play';

  @override
  String get keyPause => 'Pause';

  @override
  String get keyStop => 'Stop';

  @override
  String get keyRewind => 'Rewind';

  @override
  String get keyFastForward => 'Fast forward';

  @override
  String get keyPrevious => 'Previous';

  @override
  String get keyNext => 'Next';

  @override
  String get keyRecord => 'Record';

  @override
  String get keySubtitle => 'Subtitles';

  @override
  String get keyAudio => 'Audio';

  @override
  String get keyLastChannel => 'Last channel';

  @override
  String get keySpeedUp => 'Speed up';

  @override
  String get keySpeedDown => 'Speed down';

  @override
  String get keySpeed => 'Speed';

  @override
  String get keyTimer => 'Timer';

  @override
  String get keySleep => 'Sleep';

  @override
  String get keyLight => 'Light';

  @override
  String get keySwing => 'Swing';

  @override
  String get keyOscillate => 'Oscillate';

  @override
  String get keyMode => 'Mode';

  @override
  String get keyFocusIn => 'Focus in';

  @override
  String get keyFocusOut => 'Focus out';

  @override
  String get keyKeystoneUp => 'Keystone up';

  @override
  String get keyKeystoneDown => 'Keystone down';

  @override
  String get keySoundMode => 'Sound mode';

  @override
  String get keyTempUp => 'Temperature up';

  @override
  String get keyTempDown => 'Temperature down';

  @override
  String keyDigit(int digit) {
    return 'Digit $digit';
  }

  @override
  String get keyVolumeShort => 'Vol';

  @override
  String get keyChannelShort => 'Ch';

  @override
  String remoteMissingKey(String key) {
    return '$key (no code)';
  }

  @override
  String get remoteMoreKeys => 'More keys';

  @override
  String get remoteNumbers => 'Numbers';

  @override
  String get remoteNoKeys => 'This remote has no buttons yet.';

  @override
  String get deviceMenuRename => 'Rename';

  @override
  String get deviceMenuDelete => 'Delete';

  @override
  String get deviceMenuFavourite => 'Add to favourites';

  @override
  String get deviceMenuUnfavourite => 'Remove from favourites';

  @override
  String get deviceMenuTransport => 'Send through';

  @override
  String get deviceMenuLearn => 'Learn a button';

  @override
  String get deviceMenuPronto => 'Add a Pronto Hex button';

  @override
  String deviceDeleteConfirm(String name) {
    return 'Delete $name?';
  }

  @override
  String get deviceDeleteBody =>
      'This removes the remote and its codes from this phone.';

  @override
  String get transportAuto => 'Automatic';

  @override
  String get resultNoTransport =>
      'Nothing can send IR. Connect a hub, or use a phone with an IR blaster.';

  @override
  String resultUnavailable(String transport, String detail) {
    return 'Couldn\'t reach $transport: $detail';
  }

  @override
  String resultTimeout(String transport) {
    return '$transport didn\'t respond in time. Check it is powered on and on the same Wi-Fi.';
  }

  @override
  String resultCarrier(String transport) {
    return '$transport can\'t send this code\'s carrier frequency.';
  }

  @override
  String resultTooLong(String transport) {
    return 'This code is too long for $transport.';
  }

  @override
  String get resultInvalid => 'This code is damaged and can\'t be sent.';

  @override
  String resultRefused(String transport, String detail) {
    return '$transport refused the code: $detail';
  }

  @override
  String resultHardware(String transport, String detail) {
    return '$transport reported an error: $detail';
  }

  @override
  String resultSentTo(String transport) {
    return 'Sent through $transport';
  }

  @override
  String get hubsTitle => 'Hubs';

  @override
  String get hubsEmpty => 'No hubs yet.';

  @override
  String get hubAdd => 'Add hub';

  @override
  String get hubDiscovering => 'Looking for IR Bridges on this Wi-Fi…';

  @override
  String get hubFound => 'Found on your network';

  @override
  String get hubNoneFound =>
      'No bridges found yet. You can enter an address instead.';

  @override
  String get hubManual => 'Enter an address';

  @override
  String get hubAddressLabel => 'IP address';

  @override
  String get hubAddressError => 'Enter an IPv4 address such as 192.168.1.40.';

  @override
  String get hubTypeLabel => 'Hub type';

  @override
  String hubPairTitle(String name) {
    return 'Pair with $name';
  }

  @override
  String get hubPairBody =>
      'Press the button on the bridge, then tap Pair within 60 seconds.';

  @override
  String get hubPair => 'Pair';

  @override
  String hubPaired(String name) {
    return '$name is connected.';
  }

  @override
  String hubPairFailed(String detail) {
    return 'Pairing failed: $detail';
  }

  @override
  String get hubPairWindowClosed =>
      'The bridge\'s pairing window is closed. Press its button and try again.';

  @override
  String get hubHealthy => 'Online';

  @override
  String hubDegraded(String reason) {
    return 'Needs attention: $reason';
  }

  @override
  String hubUnreachable(String reason) {
    return 'Offline: $reason';
  }

  @override
  String get hubChecking => 'Checking…';

  @override
  String get hubRemove => 'Remove hub';

  @override
  String hubRemoveConfirm(String name) {
    return 'Remove $name? Remotes that use it switch to automatic.';
  }

  @override
  String get hubCheckNow => 'Check now';

  @override
  String get localNetworkDeniedTitle => 'Allow local network access';

  @override
  String get localNetworkDeniedBody =>
      'The app couldn\'t see devices on your Wi-Fi. On iPhone, open Settings, find this app and turn on Local Network.';

  @override
  String get broadlinkNote =>
      'Broadlink support is best effort. Keep the hub connected to your Wi-Fi as usual.';

  @override
  String broadlinkAddFailed(String detail) {
    return 'Couldn\'t connect to the Broadlink hub: $detail';
  }

  @override
  String get builtInEmitter => 'This phone\'s IR blaster';

  @override
  String get simulatorName => 'Simulator';

  @override
  String get hubKindEsp => 'IR Bridge';

  @override
  String get hubKindBroadlink => 'Broadlink';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsTheme => 'Theme';

  @override
  String get themeSystem => 'System';

  @override
  String get themeLight => 'Light';

  @override
  String get themeDark => 'Dark';

  @override
  String get settingsTemperatureUnit => 'Temperature unit';

  @override
  String get unitCelsius => '°C';

  @override
  String get unitFahrenheit => '°F';

  @override
  String get settingsAbout => 'About';

  @override
  String get settingsLicenses => 'Licenses';

  @override
  String get settingsPrivacy => 'Privacy';

  @override
  String get settingsDebug => 'Developer';

  @override
  String get settingsSignalInspector => 'Signal Inspector';

  @override
  String get settingsSimulator => 'Use the simulator transport';

  @override
  String get settingsUnverifiedAc => 'Show unverified AC encoders';

  @override
  String get settingsBackup => 'Backup and restore';

  @override
  String get aboutBody =>
      'An IR universal remote. Works offline; nothing leaves this phone.';

  @override
  String get aboutNoAffiliation =>
      'Brand names are used only to describe compatibility. This app is not affiliated with, or endorsed by, any appliance manufacturer.';

  @override
  String aboutVersion(String version) {
    return 'Version $version';
  }

  @override
  String get privacyBody =>
      'This app has no account, no ads and no analytics. Your remotes, AC settings and learned codes stay on this phone unless you export them yourself.';

  @override
  String get licensesDataSources => 'IR code sources';

  @override
  String get licensesPackages => 'Open-source packages';

  @override
  String get licensesNoDataSources =>
      'No IR code database is bundled in this build.';

  @override
  String get inspectorTitle => 'Signal Inspector';

  @override
  String get inspectorEmpty => 'No signals sent yet.';

  @override
  String get inspectorTip =>
      'Tip: many phone front cameras show an IR LED flashing.';

  @override
  String get inspectorExport => 'Copy as JSON';

  @override
  String inspectorCopied(int count) {
    return 'Copied $count signals.';
  }

  @override
  String inspectorEntry(int carrier, int count, int total) {
    return '$carrier Hz · $count durations · $total µs';
  }

  @override
  String acLastSent(String time) {
    return 'Last sent $time, as sent from this phone';
  }

  @override
  String get acNeverSent =>
      'Not sent yet. The app can\'t read the AC; it shows what it last sent.';

  @override
  String get acResync => 'Re-sync';

  @override
  String get acResyncHint => 'Sends the whole state again';

  @override
  String get acPowerOn => 'On';

  @override
  String get acPowerOff => 'Off';

  @override
  String get acPowerToggle => 'Power';

  @override
  String get acPowerToggleWarning =>
      'This AC uses a power toggle. If it is already on, this turns it off.';

  @override
  String get acModeAuto => 'Auto';

  @override
  String get acModeCool => 'Cool';

  @override
  String get acModeDry => 'Dry';

  @override
  String get acModeFan => 'Fan';

  @override
  String get acModeHeat => 'Heat';

  @override
  String get acMode => 'Mode';

  @override
  String get acFan => 'Fan';

  @override
  String get acFanAuto => 'Auto';

  @override
  String acFanLevel(int level) {
    return 'Level $level';
  }

  @override
  String get acTemperature => 'Target temperature';

  @override
  String get acTempUp => 'Raise temperature';

  @override
  String get acTempDown => 'Lower temperature';

  @override
  String get acSwingV => 'Swing';

  @override
  String get acSwingH => 'Horizontal swing';

  @override
  String get acTurbo => 'Turbo';

  @override
  String get acEco => 'Eco';

  @override
  String get acSleep => 'Sleep';

  @override
  String get acQuiet => 'Quiet';

  @override
  String get acLight => 'Display light';

  @override
  String get acClean => 'Clean';

  @override
  String get acPressToToggle => 'press to toggle';

  @override
  String get acUnverifiedTitle => 'Your AC\'s codes aren\'t verified yet';

  @override
  String get acUnverifiedBody =>
      'AC protocols are verified brand by brand against real remotes. Until yours is, learn its buttons from the original remote.';

  @override
  String get acUnverifiedBadge => 'Unverified encoder';

  @override
  String acVariantProgress(int current, int total) {
    return 'Variant $current of $total';
  }

  @override
  String get acVariantPrompt =>
      'We\'ll send: on, cool, 24 °C, auto fan. Did the AC beep or change?';

  @override
  String acTemperatureValue(String value) {
    return '$value°';
  }

  @override
  String get learnTitle => 'Learn a button';

  @override
  String get learnPrompt =>
      'Point your original remote at the hub and press the button.';

  @override
  String get learnWaiting => 'Waiting for a signal…';

  @override
  String get learnTimeout =>
      'No signal arrived. Point the remote at the hub and try again.';

  @override
  String learnError(String detail) {
    return 'Learning stopped: $detail';
  }

  @override
  String get learnRetry => 'Try again';

  @override
  String get learnCaptured => 'Got it.';

  @override
  String learnDecoded(String protocol) {
    return 'Recognised as $protocol';
  }

  @override
  String get learnRaw => 'Saved as a raw signal';

  @override
  String get learnNameLabel => 'Button name';

  @override
  String get learnTest => 'Test';

  @override
  String get learnNoHub =>
      'Learning needs a hub with an IR receiver, such as the IR Bridge.';

  @override
  String get learnStart => 'Start';

  @override
  String get prontoTitle => 'Paste Pronto Hex';

  @override
  String get prontoHint => '0000 006D 0022 0002 …';

  @override
  String prontoInvalid(String detail) {
    return 'That isn\'t a valid Pronto code: $detail';
  }

  @override
  String get prontoKeyLabel => 'Button';

  @override
  String importFailed(String detail) {
    return 'Couldn\'t import the file: $detail';
  }

  @override
  String importedKeys(int count) {
    return 'Imported $count buttons.';
  }

  @override
  String get genericDeviceName => 'My remote';

  @override
  String get menuMacros => 'Macros';

  @override
  String get macrosTitle => 'Macros';

  @override
  String get macrosEmpty =>
      'No macros yet. A macro sends several buttons in order, for example \"TV on, then set-top box on\".';

  @override
  String get macroNew => 'New macro';

  @override
  String get macroEdit => 'Edit macro';

  @override
  String get macroName => 'Macro name';

  @override
  String macroStepCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count steps',
      one: '1 step',
    );
    return '$_temp0';
  }

  @override
  String get macroRun => 'Run';

  @override
  String get macroAddStep => 'Add step';

  @override
  String get macroDevice => 'Remote';

  @override
  String get macroKey => 'Button';

  @override
  String get macroDelay => 'Then wait';

  @override
  String macroDelaySeconds(String seconds) {
    return '$seconds s';
  }

  @override
  String get macroStarting => 'Starting…';

  @override
  String macroProgress(int current, int total) {
    return 'Step $current of $total';
  }

  @override
  String get macroDone => 'Done.';

  @override
  String get macroCancelled => 'Cancelled. Later steps were not sent.';

  @override
  String macroMissingDevice(int step) {
    return 'Stopped at step $step: its remote was deleted.';
  }

  @override
  String macroFailed(int step, String detail) {
    return 'Stopped at step $step: $detail';
  }

  @override
  String get backupBody =>
      'A backup file holds your remotes, rooms, hubs, macros and settings. Hub pairings are not included; pair hubs again after restoring.';

  @override
  String get backupExport => 'Export a backup';

  @override
  String get backupExported => 'Backup ready to save or share.';

  @override
  String get backupRestore => 'Restore from a backup';

  @override
  String get backupRestoreConfirmTitle => 'Replace everything?';

  @override
  String get backupRestoreConfirmBody =>
      'Restoring replaces all remotes, rooms, hubs, macros and settings on this phone with the backup.';

  @override
  String get backupRestored => 'Restored.';
}

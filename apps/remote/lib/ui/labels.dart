/// Localized labels and icons for categories, keys and transmit results.
library;

import 'package:flutter/material.dart';
import 'package:ir_core/ir_core.dart';

import '../l10n/app_localizations.dart';
import '../services/file_io.dart';
import '../services/send_service.dart';
import '../transports/android_consumer_ir.dart';

/// Category name.
String categoryLabel(AppLocalizations l, DeviceCategory c) => switch (c) {
  DeviceCategory.tv => l.categoryTv,
  DeviceCategory.setTopBox => l.categorySetTopBox,
  DeviceCategory.airConditioner => l.categoryAirConditioner,
  DeviceCategory.fan => l.categoryFan,
  DeviceCategory.projector => l.categoryProjector,
  DeviceCategory.soundbar => l.categorySoundbar,
  DeviceCategory.airPurifier => l.categoryAirPurifier,
  DeviceCategory.generic => l.categoryGeneric,
};

/// Category icon.
IconData categoryIcon(DeviceCategory c) => switch (c) {
  DeviceCategory.tv => Icons.tv,
  DeviceCategory.setTopBox => Icons.settings_input_antenna,
  DeviceCategory.airConditioner => Icons.ac_unit,
  DeviceCategory.fan => Icons.mode_fan_off_outlined,
  DeviceCategory.projector => Icons.videocam_outlined,
  DeviceCategory.soundbar => Icons.speaker,
  DeviceCategory.airPurifier => Icons.air,
  DeviceCategory.generic => Icons.settings_remote,
};

/// Key label for screen readers and text buttons: the user's own label if
/// there is one, else the vocabulary name (or the name after `custom:`).
String keyLabel(AppLocalizations l, String key, {String? customLabel}) {
  // A label the user typed (learning, renaming) always wins.
  if (customLabel != null && customLabel.trim().isNotEmpty) return customLabel;
  if (key.startsWith(Keys.customPrefix)) {
    return customLabel ?? key.substring(Keys.customPrefix.length);
  }
  final digit = Keys.digits.indexOf(key);
  if (digit >= 0) return l.keyDigit(digit);
  return switch (key) {
    Keys.power => l.keyPower,
    Keys.powerOn => l.keyPowerOn,
    Keys.powerOff => l.keyPowerOff,
    Keys.input => l.keyInput,
    Keys.volUp => l.keyVolUp,
    Keys.volDown => l.keyVolDown,
    Keys.mute => l.keyMute,
    Keys.chUp => l.keyChUp,
    Keys.chDown => l.keyChDown,
    Keys.up => l.keyUp,
    Keys.down => l.keyDown,
    Keys.left => l.keyLeft,
    Keys.right => l.keyRight,
    Keys.ok => l.keyOk,
    Keys.back => l.keyBack,
    Keys.home => l.keyHome,
    Keys.menu => l.keyMenu,
    Keys.exit => l.keyExit,
    Keys.guide => l.keyGuide,
    Keys.info => l.keyInfo,
    Keys.red => l.keyRed,
    Keys.green => l.keyGreen,
    Keys.yellow => l.keyYellow,
    Keys.blue => l.keyBlue,
    Keys.play => l.keyPlay,
    Keys.pause => l.keyPause,
    Keys.stop => l.keyStop,
    Keys.rewind => l.keyRewind,
    Keys.fastForward => l.keyFastForward,
    Keys.previous => l.keyPrevious,
    Keys.next => l.keyNext,
    Keys.record => l.keyRecord,
    Keys.subtitle => l.keySubtitle,
    Keys.audio => l.keyAudio,
    Keys.lastChannel => l.keyLastChannel,
    Keys.speedUp => l.keySpeedUp,
    Keys.speedDown => l.keySpeedDown,
    Keys.speed => l.keySpeed,
    Keys.timer => l.keyTimer,
    Keys.sleep => l.keySleep,
    Keys.light => l.keyLight,
    Keys.swing => l.keySwing,
    Keys.oscillate => l.keyOscillate,
    Keys.mode => l.keyMode,
    Keys.focusIn => l.keyFocusIn,
    Keys.focusOut => l.keyFocusOut,
    Keys.keystoneUp => l.keyKeystoneUp,
    Keys.keystoneDown => l.keyKeystoneDown,
    Keys.soundMode => l.keySoundMode,
    Keys.tempUp => l.keyTempUp,
    Keys.tempDown => l.keyTempDown,
    _ => key,
  };
}

/// Icon for keys that have a conventional symbol; `null` means show text.
IconData? keyIcon(String key) => switch (key) {
  Keys.power || Keys.powerOn || Keys.powerOff => Icons.power_settings_new,
  Keys.input => Icons.input,
  Keys.volUp => Icons.volume_up,
  Keys.volDown => Icons.volume_down,
  Keys.mute => Icons.volume_off,
  Keys.chUp => Icons.keyboard_arrow_up,
  Keys.chDown => Icons.keyboard_arrow_down,
  Keys.up => Icons.arrow_drop_up,
  Keys.down => Icons.arrow_drop_down,
  Keys.left => Icons.arrow_left,
  Keys.right => Icons.arrow_right,
  Keys.back => Icons.arrow_back,
  Keys.home => Icons.home_outlined,
  Keys.menu => Icons.menu,
  Keys.exit => Icons.close,
  Keys.guide => Icons.view_list_outlined,
  Keys.info => Icons.info_outline,
  Keys.play => Icons.play_arrow,
  Keys.pause => Icons.pause,
  Keys.stop => Icons.stop,
  Keys.rewind => Icons.fast_rewind,
  Keys.fastForward => Icons.fast_forward,
  Keys.previous => Icons.skip_previous,
  Keys.next => Icons.skip_next,
  Keys.record => Icons.fiber_manual_record,
  Keys.subtitle => Icons.subtitles_outlined,
  Keys.speedUp => Icons.add,
  Keys.speedDown => Icons.remove,
  Keys.timer => Icons.timer_outlined,
  Keys.sleep => Icons.bedtime_outlined,
  Keys.light => Icons.lightbulb_outline,
  Keys.swing || Keys.oscillate => Icons.swap_horiz,
  Keys.tempUp => Icons.add,
  Keys.tempDown => Icons.remove,
  _ => null,
};

/// The name shown for a transport: the phone's own emitter and the
/// simulator in the user's language, hubs by their own (user-given) name.
String transportLabel(
  AppLocalizations l,
  TransportKind? kind,
  String? displayName,
) => switch (kind) {
  TransportKind.builtIn => l.transportThisPhone,
  TransportKind.simulated => l.simulatorName,
  _ => displayName ?? '',
};

/// The message shown for a send outcome; `null` for success.
String? outcomeMessage(AppLocalizations l, SendOutcome o) {
  if (o.ok) return null;
  if (o.missingKey) return l.remoteMissingKey('');
  if (o.isNoTransport) return l.resultNoTransport;
  final t = transportLabel(l, o.transportKind, o.transportName);
  return switch (o.result) {
    TransmitSent() => null,
    TransmitTransportUnavailable(:final detail) =>
      o.transportKind == TransportKind.builtIn
          ? switch (detail) {
              ConsumerIrDetail.noEmitter => l.resultBuiltInNoEmitter,
              ConsumerIrDetail.permission => l.resultBuiltInPermission,
              ConsumerIrDetail.channelMissing => l.resultBuiltInUnavailable,
              _ => l.resultUnavailable(t, detail),
            }
          : l.resultUnavailable(t, detail),
    TransmitTimeout() => l.resultTimeout(t),
    TransmitRejected(:final reason, :final detail) => switch (reason) {
      RejectReason.carrierOutOfRange => l.resultCarrier(t),
      RejectReason.patternTooLong ||
      RejectReason.tooManyDurations => l.resultTooLong(t),
      RejectReason.invalidDurations => l.resultInvalid,
      RejectReason.refusedByHub => l.resultRefused(t, detail),
      RejectReason.hardwareError => l.resultHardware(t, detail),
    },
  };
}

/// The message shown when a picked file cannot be imported.
String importErrorMessage(AppLocalizations l, Object error) => switch (error) {
  NotTextFileException() => l.importFailed(l.importNotText),
  FileTooLargeException() => l.importFailed(l.importTooLarge),
  FormatException(:final message) => l.importFailed(message),
  _ => l.importFailed(l.importUnreadable),
};

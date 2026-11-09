/// The fixed key vocabulary every code set is normalized to.
///
/// Database importers map source names onto these; unmapped names are kept as
/// `custom:<original>`.
library;

/// Normalized key names.
abstract final class Keys {
  static const power = 'POWER';
  static const powerOn = 'POWER_ON';
  static const powerOff = 'POWER_OFF';
  static const input = 'INPUT';
  static const volUp = 'VOL_UP';
  static const volDown = 'VOL_DOWN';
  static const mute = 'MUTE';
  static const chUp = 'CH_UP';
  static const chDown = 'CH_DOWN';
  static const up = 'UP';
  static const down = 'DOWN';
  static const left = 'LEFT';
  static const right = 'RIGHT';
  static const ok = 'OK';
  static const back = 'BACK';
  static const home = 'HOME';
  static const menu = 'MENU';
  static const exit = 'EXIT';
  static const guide = 'GUIDE';
  static const info = 'INFO';
  static const red = 'RED';
  static const green = 'GREEN';
  static const yellow = 'YELLOW';
  static const blue = 'BLUE';
  static const play = 'PLAY';
  static const pause = 'PAUSE';
  static const stop = 'STOP';
  static const rewind = 'REWIND';
  static const fastForward = 'FAST_FORWARD';
  static const previous = 'PREVIOUS';
  static const next = 'NEXT';
  static const record = 'RECORD';
  static const subtitle = 'SUBTITLE';
  static const audio = 'AUDIO';
  static const lastChannel = 'LAST_CHANNEL';
  static const speedUp = 'SPEED_UP';
  static const speedDown = 'SPEED_DOWN';
  static const speed = 'SPEED';
  static const timer = 'TIMER';
  static const sleep = 'SLEEP';
  static const light = 'LIGHT';
  static const swing = 'SWING';
  static const oscillate = 'OSCILLATE';
  static const mode = 'MODE';
  static const focusIn = 'FOCUS_IN';
  static const focusOut = 'FOCUS_OUT';
  static const keystoneUp = 'KEYSTONE_UP';
  static const keystoneDown = 'KEYSTONE_DOWN';
  static const soundMode = 'SOUND_MODE';
  static const tempUp = 'TEMP_UP';
  static const tempDown = 'TEMP_DOWN';
  static const digit0 = 'DIGIT_0';
  static const digit1 = 'DIGIT_1';
  static const digit2 = 'DIGIT_2';
  static const digit3 = 'DIGIT_3';
  static const digit4 = 'DIGIT_4';
  static const digit5 = 'DIGIT_5';
  static const digit6 = 'DIGIT_6';
  static const digit7 = 'DIGIT_7';
  static const digit8 = 'DIGIT_8';
  static const digit9 = 'DIGIT_9';

  /// Digit keys in order 0-9.
  static const digits = [
    digit0, digit1, digit2, digit3, digit4, //
    digit5, digit6, digit7, digit8, digit9,
  ];

  /// Every normalized key name.
  static const Set<String> all = {
    power, powerOn, powerOff, input, volUp, volDown, mute, chUp, chDown, //
    up, down, left, right, ok, back, home, menu, exit, guide, info, //
    red, green, yellow, blue, play, pause, stop, rewind, fastForward, //
    previous, next, record, subtitle, audio, lastChannel, speedUp, //
    speedDown, speed, timer, sleep, light, swing, oscillate, mode, //
    focusIn, focusOut, keystoneUp, keystoneDown, soundMode, tempUp, //
    tempDown, ...digits,
  };

  /// Prefix for names outside the vocabulary.
  static const customPrefix = 'custom:';

  /// Whether [key] is a normalized or custom key name.
  static bool isValid(String key) =>
      all.contains(key) ||
      (key.startsWith(customPrefix) && key.length > customPrefix.length);

  static final Map<String, String> _synonyms = _buildSynonyms();

  static Map<String, String> _buildSynonyms() {
    final m = <String, String>{};
    void add(String key, List<String> names) {
      for (final n in names) {
        m[_squash(n)] = key;
      }
    }

    add(power, [
      'power',
      'pwr',
      'power toggle',
      'onoff',
      'on off',
      'standby',
      'power on/off',
      'on/off',
    ]);
    add(powerOn, ['power on', 'poweron', 'on', 'discrete on', 'pwr on']);
    add(powerOff, ['power off', 'poweroff', 'off', 'discrete off', 'pwr off']);
    add(input, [
      'input',
      'source',
      'src',
      'av',
      'tv/av',
      'input select',
      'inputs',
      'av/tv',
      'external input',
    ]);
    add(volUp, [
      'vol+',
      'vol_up',
      'volup',
      'volume up',
      'volume+',
      'v+',
      'vol up',
    ]);
    add(volDown, [
      'vol-',
      'vol_dn',
      'voldown',
      'voldn',
      'volume down',
      'volume-',
      'v-',
      'vol down',
      'vol_down',
    ]);
    add(mute, ['mute', 'muting', 'mute toggle']);
    add(chUp, [
      'ch+',
      'ch_next',
      'chup',
      'channel up',
      'channel+',
      'p+',
      'ch up',
      'prog+',
      'program up',
      'ch_up',
    ]);
    add(chDown, [
      'ch-',
      'ch_prev',
      'chdown',
      'chdn',
      'channel down',
      'channel-',
      'p-',
      'ch down',
      'prog-',
      'program down',
      'ch_down',
    ]);
    add(up, ['up', 'cursor up', 'arrow up', 'nav up', 'menu up']);
    add(down, ['down', 'cursor down', 'arrow down', 'nav down', 'menu down']);
    add(left, ['left', 'cursor left', 'arrow left', 'nav left', 'menu left']);
    add(right, [
      'right',
      'cursor right',
      'arrow right',
      'nav right',
      'menu right',
    ]);
    add(ok, ['ok', 'enter', 'select', 'confirm', 'center']);
    add(back, ['back', 'return', 'ret']);
    add(home, ['home', 'smart', 'smart hub', 'smarthub']);
    add(menu, ['menu', 'setup', 'settings']);
    add(exit, ['exit', 'quit']);
    add(guide, ['guide', 'epg', 'tv guide']);
    add(info, ['info', 'display', 'information', 'disp']);
    add(red, ['red', 'f1']);
    add(green, ['green', 'f2']);
    add(yellow, ['yellow', 'f3']);
    add(blue, ['blue', 'f4']);
    add(play, ['play']);
    add(pause, ['pause', 'play/pause', 'playpause']);
    add(stop, ['stop']);
    add(rewind, ['rewind', 'rew', 'fast rewind']);
    add(fastForward, [
      'fast forward',
      'ff',
      'fwd',
      'forward',
      'fast_fo',
      'fastforward',
    ]);
    add(previous, ['previous', 'prev', 'skip back', 'skip-']);
    add(next, ['next', 'skip', 'skip forward', 'skip+']);
    add(record, ['record', 'rec']);
    add(subtitle, ['subtitle', 'subtitles', 'sub', 'cc']);
    add(audio, ['audio', 'language', 'mts']);
    add(lastChannel, [
      'last',
      'prev ch',
      'pre-ch',
      'prech',
      'recall',
      'flashback',
      'last channel',
    ]);
    add(speedUp, ['speed+', 'speed up', 'fan+', 'fan up', 'fan_up']);
    add(speedDown, ['speed-', 'speed down', 'fan-', 'fan down', 'fan_down']);
    add(speed, ['speed', 'fan speed', 'fan']);
    add(timer, ['timer']);
    add(sleep, ['sleep']);
    add(light, ['light', 'lamp']);
    add(swing, ['swing']);
    add(oscillate, ['oscillate', 'osc', 'rotate', 'rotation']);
    add(mode, ['mode']);
    add(focusIn, ['focus+', 'focus in']);
    add(focusOut, ['focus-', 'focus out']);
    add(keystoneUp, ['keystone+', 'keystone up']);
    add(keystoneDown, ['keystone-', 'keystone down']);
    add(soundMode, ['sound mode', 'sound', 'surround', 'eq']);
    add(tempUp, ['temp+', 'temp up', 'temperature up']);
    add(tempDown, ['temp-', 'temp down', 'temperature down']);
    for (var i = 0; i < 10; i++) {
      add(digits[i], [
        '$i',
        'digit $i',
        'num $i',
        'key $i',
        'number $i',
        'num_$i',
      ]);
    }
    return m;
  }

  static String _squash(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[\s_\.]+'), ' ').trim();

  /// Maps a source key name to the vocabulary, or to `custom:<original>`.
  static String normalize(String sourceName) {
    final trimmed = sourceName.trim();
    if (all.contains(trimmed)) return trimmed;
    final hit = _synonyms[_squash(trimmed)];
    if (hit != null) return hit;
    return '$customPrefix$trimmed';
  }
}

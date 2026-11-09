/// User preferences, persisted in the settings table.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../data/repositories.dart';

/// Temperature display unit. Encoders always take °C; this converts at the
/// UI edge only.
enum TemperatureUnit {
  /// Celsius.
  celsius,

  /// Fahrenheit.
  fahrenheit,
}

/// Observable app settings.
final class AppSettings extends ChangeNotifier {
  AppSettings._(this._repo, Map<String, String> values) {
    _themeMode = ThemeMode.values.firstWhere(
      (m) => m.name == values[_kTheme],
      orElse: () => ThemeMode.system,
    );
    _unit = TemperatureUnit.values.firstWhere(
      (u) => u.name == values[_kUnit],
      orElse: () => TemperatureUnit.celsius,
    );
    _onboardingDone = values[_kOnboarding] == 'true';
    _useSimulator = values[_kSimulator] == 'true';
    _showUnverifiedAc = values[_kUnverifiedAc] == 'true';
  }

  /// Loads settings from [repo].
  static Future<AppSettings> load(SettingsRepository repo) async =>
      AppSettings._(repo, await repo.all());

  static const _kTheme = 'themeMode';
  static const _kUnit = 'temperatureUnit';
  static const _kOnboarding = 'onboardingDone';
  static const _kSimulator = 'useSimulator';
  static const _kUnverifiedAc = 'showUnverifiedAc';

  final SettingsRepository _repo;
  late ThemeMode _themeMode;
  late TemperatureUnit _unit;
  late bool _onboardingDone;
  late bool _useSimulator;
  late bool _showUnverifiedAc;

  /// The backing repository (tests reload settings through it).
  @visibleForTesting
  SettingsRepository get repoForTest => _repo;

  /// Light, dark or system theme.
  ThemeMode get themeMode => _themeMode;

  /// °C or °F display.
  TemperatureUnit get unit => _unit;

  /// Whether onboarding has been completed.
  bool get onboardingDone => _onboardingDone;

  /// Debug builds only: register the simulator transport.
  bool get useSimulator => kDebugMode && _useSimulator;

  /// Debug builds only: offer AC encoders that have no human-captured
  /// fixtures. Always off in release builds.
  bool get showUnverifiedAc => kDebugMode && _showUnverifiedAc;

  Future<void> _set(String key, String value) async {
    await _repo.set(key, value);
    notifyListeners();
  }

  /// Sets the theme.
  Future<void> setThemeMode(ThemeMode m) {
    _themeMode = m;
    return _set(_kTheme, m.name);
  }

  /// Sets the temperature unit.
  Future<void> setUnit(TemperatureUnit u) {
    _unit = u;
    return _set(_kUnit, u.name);
  }

  /// Marks onboarding as done.
  Future<void> completeOnboarding() {
    _onboardingDone = true;
    return _set(_kOnboarding, 'true');
  }

  /// Enables or disables the simulator transport (debug builds).
  Future<void> setUseSimulator({required bool value}) {
    _useSimulator = value;
    return _set(_kSimulator, '$value');
  }

  /// Shows or hides unverified AC encoders (debug builds).
  Future<void> setShowUnverifiedAc({required bool value}) {
    _showUnverifiedAc = value;
    return _set(_kUnverifiedAc, '$value');
  }
}

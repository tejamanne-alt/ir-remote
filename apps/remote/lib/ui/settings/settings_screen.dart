/// Settings, About, Privacy, Licenses and the debug Signal Inspector.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ir_transports/ir_transports.dart';

import '../../l10n/app_localizations.dart';
import '../../services/app_services.dart';
import '../../services/app_settings.dart';

/// App version shown on About (kept in sync with pubspec by the release
/// checklist).
const String appVersion = '0.1.0';

/// Settings.
class SettingsScreen extends StatelessWidget {
  /// Creates the screen.
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final services = AppScope.of(context);
    final settings = services.settings;
    return Scaffold(
      appBar: AppBar(title: Text(l.settingsTitle)),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: settings,
          builder: (context, _) => ListView(
            children: [
              ListTile(title: Text(l.settingsTheme)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SegmentedButton<ThemeMode>(
                  segments: [
                    ButtonSegment(
                      value: ThemeMode.system,
                      label: Text(l.themeSystem),
                    ),
                    ButtonSegment(
                      value: ThemeMode.light,
                      label: Text(l.themeLight),
                    ),
                    ButtonSegment(
                      value: ThemeMode.dark,
                      label: Text(l.themeDark),
                    ),
                  ],
                  selected: {settings.themeMode},
                  onSelectionChanged: (v) => settings.setThemeMode(v.first),
                ),
              ),
              ListTile(title: Text(l.settingsTemperatureUnit)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SegmentedButton<TemperatureUnit>(
                  segments: [
                    ButtonSegment(
                      value: TemperatureUnit.celsius,
                      label: Text(l.unitCelsius),
                    ),
                    ButtonSegment(
                      value: TemperatureUnit.fahrenheit,
                      label: Text(l.unitFahrenheit),
                    ),
                  ],
                  selected: {settings.unit},
                  onSelectionChanged: (v) => settings.setUnit(v.first),
                ),
              ),
              const Divider(height: 32),
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: Text(l.settingsAbout),
                onTap: () => _push(context, const AboutScreen()),
              ),
              ListTile(
                leading: const Icon(Icons.privacy_tip_outlined),
                title: Text(l.settingsPrivacy),
                onTap: () => _push(context, const PrivacyScreen()),
              ),
              ListTile(
                leading: const Icon(Icons.description_outlined),
                title: Text(l.settingsLicenses),
                onTap: () => _push(context, const LicensesScreen()),
              ),
              if (kDebugMode) ...[
                const Divider(height: 32),
                ListTile(title: Text(l.settingsDebug)),
                ListTile(
                  leading: const Icon(Icons.graphic_eq),
                  title: Text(l.settingsSignalInspector),
                  onTap: () => _push(context, const SignalInspectorScreen()),
                ),
                SwitchListTile(
                  title: Text(l.settingsSimulator),
                  value: settings.useSimulator,
                  onChanged: (v) => services.setSimulator(enabled: v),
                ),
                SwitchListTile(
                  title: Text(l.settingsUnverifiedAc),
                  value: settings.showUnverifiedAc,
                  onChanged: (v) => settings.setShowUnverifiedAc(value: v),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

void _push(BuildContext context, Widget w) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => w));

/// About: version, offline statement and the no-affiliation line (gate L6).
class AboutScreen extends StatelessWidget {
  /// Creates the screen.
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text(l.settingsAbout)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(l.appTitle, style: t.headlineSmall),
            Text(l.aboutVersion(appVersion)),
            const SizedBox(height: 16),
            Text(l.aboutBody),
            const SizedBox(height: 16),
            Text(l.aboutNoAffiliation),
          ],
        ),
      ),
    );
  }
}

/// Privacy statement.
class PrivacyScreen extends StatelessWidget {
  /// Creates the screen.
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.settingsPrivacy)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(l.privacyBody),
        ),
      ),
    );
  }
}

/// Licenses: every IR data source with its required notice verbatim
/// (gate L3), then Flutter's package licence page.
class LicensesScreen extends StatelessWidget {
  /// Creates the screen.
  const LicensesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final notices = AppScope.of(context).codes.notices;
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text(l.settingsLicenses)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(l.licensesDataSources, style: t.titleMedium),
            if (notices.isEmpty) Text(l.licensesNoDataSources),
            for (final n in notices)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(n.source, style: t.titleSmall),
                      Text('${n.license} · ${n.url}', style: t.bodySmall),
                      const SizedBox(height: 8),
                      SelectableText(n.notice),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.code),
              title: Text(l.licensesPackages),
              onTap: () => showLicensePage(
                context: context,
                applicationName: l.appTitle,
                applicationVersion: appVersion,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Debug only: the last 20 signals with JSON export.
class SignalInspectorScreen extends StatelessWidget {
  /// Creates the screen.
  const SignalInspectorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final log = AppScope.of(context).log;
    return Scaffold(
      appBar: AppBar(
        title: Text(l.inspectorTitle),
        actions: [
          IconButton(
            tooltip: l.inspectorExport,
            icon: const Icon(Icons.copy_all),
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              await Clipboard.setData(ClipboardData(text: log.exportJson()));
              messenger.showSnackBar(
                SnackBar(content: Text(l.inspectorCopied(log.records.length))),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: log,
          builder: (context, _) {
            final records = log.records;
            return ListView(
              children: [
                ListTile(
                  leading: const Icon(Icons.photo_camera_front),
                  title: Text(l.inspectorTip),
                ),
                if (records.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(l.inspectorEmpty),
                  ),
                for (final TransmitRecord r in records)
                  ListTile(
                    title: Text(
                      l.inspectorEntry(
                        r.signal.carrierHz,
                        r.signal.durationsUs.length,
                        r.signal.frameLengthUs,
                      ),
                    ),
                    subtitle: Text(
                      '${r.transportId} · ${r.result} · ${r.at.toIso8601String()}',
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

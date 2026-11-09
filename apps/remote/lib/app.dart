/// The root widget: theme, localization and first-run routing.
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'l10n/app_localizations.dart';
import 'services/app_services.dart';
import 'ui/home/home_screen.dart';
import 'ui/onboarding/onboarding_screen.dart';

/// Builds a theme for [brightness]. Material 3 colour schemes meet WCAG AA
/// contrast for text on their surface roles.
ThemeData buildTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF00696E),
    brightness: brightness,
  );
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    visualDensity: VisualDensity.standard,
    materialTapTargetSize: MaterialTapTargetSize.padded,
  );
}

/// The app.
class IrRemoteApp extends StatefulWidget {
  /// Creates the app over [services].
  const IrRemoteApp({super.key, required this.services});

  /// Long-lived services.
  final AppServices services;

  @override
  State<IrRemoteApp> createState() => _IrRemoteAppState();
}

class _IrRemoteAppState extends State<IrRemoteApp> {
  late bool _onboarding = !widget.services.settings.onboardingDone;

  @override
  Widget build(BuildContext context) => AppScope(
    services: widget.services,
    child: ListenableBuilder(
      listenable: widget.services.settings,
      builder: (context, _) => MaterialApp(
        onGenerateTitle: (c) => AppLocalizations.of(c).appTitle,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        themeMode: widget.services.settings.themeMode,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: _onboarding
            ? OnboardingScreen(
                onDone: () => setState(() => _onboarding = false),
              )
            : const HomeScreen(),
      ),
    ),
  );
}

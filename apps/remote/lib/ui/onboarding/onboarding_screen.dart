/// Capability onboarding: detect the emitter and hubs, then route to a path
/// that works. No dead ends.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../services/app_services.dart';
import '../add_device/add_device_flow.dart';
import '../hubs/hubs_screen.dart';

/// The three onboarding paths.
enum OnboardingPath {
  /// The phone has an emitter.
  emitter,

  /// iPhone: hubs only.
  hubIos,

  /// Android without an emitter.
  noEmitter,
}

/// Picks the path from detected capabilities.
OnboardingPath pathFor(AppServices s) {
  if (s.emitter.canTransmit) return OnboardingPath.emitter;
  if (s.isIos) return OnboardingPath.hubIos;
  return OnboardingPath.noEmitter;
}

/// First-run screen.
class OnboardingScreen extends StatelessWidget {
  /// Creates the screen.
  const OnboardingScreen({super.key, required this.onDone});

  /// Called when the user leaves onboarding.
  final VoidCallback onDone;

  Future<void> _finish(BuildContext context, Widget? next) async {
    final services = AppScope.of(context);
    final nav = Navigator.of(context);
    await services.settings.completeOnboarding();
    onDone();
    if (next != null) {
      await nav.push(MaterialPageRoute<void>(builder: (_) => next));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final s = AppScope.of(context);
    final theme = Theme.of(context);
    final path = pathFor(s);
    final (title, body, icon) = switch (path) {
      OnboardingPath.emitter => (
        l.pathEmitterTitle,
        l.pathEmitterBody,
        Icons.settings_remote,
      ),
      OnboardingPath.hubIos => (
        l.pathHubTitle,
        l.pathHubBodyIos,
        Icons.router_outlined,
      ),
      OnboardingPath.noEmitter => (
        l.pathNoEmitterTitle,
        l.pathNoEmitterBody,
        Icons.router_outlined,
      ),
    };
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 24),
            Icon(icon, size: 72, color: theme.colorScheme.primary),
            const SizedBox(height: 24),
            Semantics(
              header: true,
              child: Text(title, style: theme.textTheme.headlineSmall),
            ),
            const SizedBox(height: 12),
            Text(body, style: theme.textTheme.bodyLarge),
            if (path != OnboardingPath.emitter) ...[
              const SizedBox(height: 24),
              Text(l.supportedHubsTitle, style: theme.textTheme.titleMedium),
              ListTile(
                leading: const Icon(Icons.memory),
                title: Text(l.hubEspBridge),
              ),
              ListTile(
                leading: const Icon(Icons.router),
                title: Text(l.hubBroadlink),
              ),
            ],
            const SizedBox(height: 16),
            Card(
              child: ListTile(
                leading: const Icon(Icons.lightbulb_outline),
                title: Text(l.irBasics),
              ),
            ),
            const SizedBox(height: 24),
            if (path == OnboardingPath.emitter)
              FilledButton(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                ),
                onPressed: () => _finish(context, const CategoryScreen()),
                child: Text(l.actionAddFirstDevice),
              )
            else
              FilledButton(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                ),
                onPressed: () =>
                    _finish(context, const HubsScreen(startAdding: true)),
                child: Text(l.actionConnectHub),
              ),
            const SizedBox(height: 8),
            if (kDebugMode && path != OnboardingPath.emitter)
              OutlinedButton(
                onPressed: () async {
                  await s.setSimulator(enabled: true);
                  if (context.mounted) {
                    await _finish(context, const CategoryScreen());
                  }
                },
                child: Text(l.actionUseSimulator),
              ),
            TextButton(
              onPressed: () => _finish(context, null),
              child: Text(l.actionLater),
            ),
          ],
        ),
      ),
    );
  }
}

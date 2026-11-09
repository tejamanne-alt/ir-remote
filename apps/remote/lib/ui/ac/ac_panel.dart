/// The stateful AC panel. Renders only what the protocol's capabilities
/// declare, and never claims to know the AC's real state.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:ir_core/ir_core.dart';

import '../../data/models.dart';
import '../../l10n/app_localizations.dart';
import '../../services/app_services.dart';
import '../../services/app_settings.dart';
import '../labels.dart';
import '../remote/remote_screen.dart';
import '../widgets/remote_button.dart';

/// Converts °C to the display unit (UI edge only).
double displayTemp(double c, TemperatureUnit u) =>
    u == TemperatureUnit.celsius ? c : c * 9 / 5 + 32;

/// Formats a temperature for display.
String formatTemp(double c, TemperatureUnit u) {
  final v = displayTemp(c, u);
  return v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
}

/// The AC panel for [device], or its learned-button fallback.
class AcPanel extends StatefulWidget {
  /// Creates the panel.
  const AcPanel({super.key, required this.device, this.encoders});

  /// The AC remote.
  final SavedDevice device;

  /// Encoder registry (tests inject one).
  final AcEncoderRegistry? encoders;

  @override
  State<AcPanel> createState() => _AcPanelState();
}

class _AcPanelState extends State<AcPanel> {
  late AcState _state;
  bool _sending = false;

  AcEncoder? get _encoder {
    final reg = widget.encoders ?? AcEncoderRegistry.standard;
    final e = reg.lookup(widget.device.ac!.protocolId);
    if (e == null) return null;
    final settings = AppScope.of(context).settings;
    return e.verified || settings.showUnverifiedAc ? e : null;
  }

  @override
  void initState() {
    super.initState();
    _state = widget.device.ac?.lastState ?? AcState.matchingProbe;
  }

  Future<void> _send(AcState next, {AcToggle? toggle}) async {
    final e = _encoder;
    if (e == null || _sending) return;
    final services = AppScope.of(context);
    final l = AppLocalizations.of(context);
    final clamped = e.capabilities.clamp(next);
    setState(() => _sending = true);
    unawaited(HapticFeedback.lightImpact());
    final o = await services.send.sendSignal(
      widget.device,
      e.encode(clamped, toggle: toggle),
    );
    // "Last sent" is recorded even if the user left the panel meanwhile:
    // the frame went out, so the assumption must follow it.
    if (o.ok) {
      try {
        await services.devices.saveAcState(
          widget.device.id,
          clamped,
          DateTime.now(),
        );
      } on Object {
        // the remote was deleted meanwhile; nothing to record
      }
    }
    if (!mounted) return;
    setState(() {
      _sending = false;
      if (o.ok) _state = clamped;
    });
    if (!o.ok) showSendError(context, outcomeMessage(l, o) ?? '');
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final e = _encoder;
    if (e == null) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.info_outline),
              title: Text(l.acUnverifiedTitle),
              subtitle: Text(l.acUnverifiedBody),
            ),
          ),
          SizedBox(height: 520, child: RemoteLayout(device: widget.device)),
        ],
      );
    }
    final caps = e.capabilities;
    final unit = AppScope.of(context).settings.unit;
    final theme = Theme.of(context);
    final sentAt = widget.device.ac?.lastSentAt;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (!e.verified)
          Align(
            alignment: Alignment.centerLeft,
            child: Chip(label: Text(l.acUnverifiedBadge)),
          ),
        Semantics(
          liveRegion: true,
          child: Text(
            sentAt == null
                ? l.acNeverSent
                : l.acLastSent(DateFormat.Hm().format(sentAt)),
            style: theme.textTheme.bodySmall,
          ),
        ),
        const SizedBox(height: 12),
        if (caps.power == PowerControl.discrete)
          SegmentedButton<bool>(
            segments: [
              ButtonSegment(
                value: true,
                label: Text(l.acPowerOn),
                icon: const Icon(Icons.power_settings_new),
              ),
              ButtonSegment(value: false, label: Text(l.acPowerOff)),
            ],
            selected: {_state.power},
            onSelectionChanged: (v) => _send(_state.copyWith(power: v.first)),
          )
        else ...[
          FilledButton.icon(
            icon: const Icon(Icons.power_settings_new),
            label: Text(l.acPowerToggle),
            onPressed: () => _send(
              _state.copyWith(power: !_state.power),
              toggle: const PowerToggle(),
            ),
          ),
          Text(l.acPowerToggleWarning, style: theme.textTheme.bodySmall),
        ],
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton.filledTonal(
              iconSize: 32,
              tooltip: l.acTempDown,
              onPressed: _state.targetTempC <= caps.minTempC
                  ? null
                  : () => _send(
                      _state.copyWith(
                        targetTempC: _state.targetTempC - caps.tempStepC,
                      ),
                    ),
              icon: const Icon(Icons.remove),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Semantics(
                label: l.acTemperature,
                value: l.acTemperatureValue(
                  formatTemp(_state.targetTempC, unit),
                ),
                child: ExcludeSemantics(
                  child: Text(
                    '${formatTemp(_state.targetTempC, unit)}${unit == TemperatureUnit.celsius ? l.unitCelsius : l.unitFahrenheit}',
                    style: theme.textTheme.displayLarge,
                  ),
                ),
              ),
            ),
            IconButton.filledTonal(
              iconSize: 32,
              tooltip: l.acTempUp,
              onPressed: _state.targetTempC >= caps.maxTempC
                  ? null
                  : () => _send(
                      _state.copyWith(
                        targetTempC: _state.targetTempC + caps.tempStepC,
                      ),
                    ),
              icon: const Icon(Icons.add),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Text(l.acMode, style: theme.textTheme.titleSmall),
        Wrap(
          spacing: 8,
          children: [
            for (final m in AcMode.values)
              if (caps.modes.contains(m))
                ChoiceChip(
                  label: Text(_modeLabel(l, m)),
                  selected: _state.mode == m,
                  onSelected: (_) => _send(_state.copyWith(mode: m)),
                ),
          ],
        ),
        const SizedBox(height: 16),
        Text(l.acFan, style: theme.textTheme.titleSmall),
        Wrap(
          spacing: 8,
          children: [
            if (caps.fanAuto)
              ChoiceChip(
                label: Text(l.acFanAuto),
                selected: _state.fan == 0,
                onSelected: (_) => _send(_state.copyWith(fan: 0)),
              ),
            for (var i = 1; i <= caps.fanLevels; i++)
              ChoiceChip(
                label: Text(l.acFanLevel(i)),
                selected: _state.fan == i,
                onSelected: (_) => _send(_state.copyWith(fan: i)),
              ),
          ],
        ),
        const SizedBox(height: 16),
        for (final entry in caps.features.entries)
          entry.value == FeatureControl.state
              ? SwitchListTile(
                  title: Text(_featureLabel(l, entry.key)),
                  value: _state.has(entry.key),
                  onChanged: (v) => _send(_state.withFeature(entry.key, on: v)),
                )
              : ListTile(
                  title: Text(_featureLabel(l, entry.key)),
                  subtitle: Text(l.acPressToToggle),
                  trailing: OutlinedButton(
                    onPressed: () =>
                        _send(_state, toggle: FeatureToggle(entry.key)),
                    child: Text(l.acPressToToggle),
                  ),
                ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          icon: const Icon(Icons.sync),
          label: Text(l.acResync),
          onPressed: () => _send(_state),
        ),
        Text(l.acResyncHint, style: theme.textTheme.bodySmall),
      ],
    );
  }
}

String _modeLabel(AppLocalizations l, AcMode m) => switch (m) {
  AcMode.auto => l.acModeAuto,
  AcMode.cool => l.acModeCool,
  AcMode.dry => l.acModeDry,
  AcMode.fan => l.acModeFan,
  AcMode.heat => l.acModeHeat,
};

String _featureLabel(AppLocalizations l, AcFeature f) => switch (f) {
  AcFeature.swingV => l.acSwingV,
  AcFeature.swingH => l.acSwingH,
  AcFeature.turbo => l.acTurbo,
  AcFeature.eco => l.acEco,
  AcFeature.sleep => l.acSleep,
  AcFeature.quiet => l.acQuiet,
  AcFeature.light => l.acLight,
  AcFeature.clean => l.acClean,
};

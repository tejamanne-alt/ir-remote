/// A saved remote: per-category layout, device menu, and "more keys".
library;

import 'package:flutter/material.dart';
import 'package:ir_core/ir_core.dart';

import '../../data/models.dart';
import '../../l10n/app_localizations.dart';
import '../../services/app_services.dart';
import '../ac/ac_panel.dart';
import '../labels.dart';
import '../learn/learn_screen.dart';
import '../learn/pronto_dialog.dart';
import '../widgets/remote_button.dart';

/// Opens the remote for the device with [deviceId].
class RemoteScreen extends StatelessWidget {
  /// Creates the screen.
  const RemoteScreen({super.key, required this.deviceId});

  /// Device to show.
  final String deviceId;

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return StreamBuilder<SavedDevice?>(
      stream: services.devices.watch(deviceId),
      builder: (context, snap) {
        final device = snap.data;
        if (device == null) {
          return Scaffold(
            appBar: AppBar(),
            body: snap.connectionState == ConnectionState.waiting
                ? const Center(child: CircularProgressIndicator())
                : const SizedBox.shrink(),
          );
        }
        return Scaffold(
          appBar: AppBar(
            title: Text(device.name),
            actions: [_DeviceMenu(device: device)],
          ),
          body: SafeArea(
            child: device.ac != null
                ? AcPanel(device: device)
                : RemoteLayout(device: device),
          ),
        );
      },
    );
  }
}

/// Lays out a key-code remote for its category.
class RemoteLayout extends StatelessWidget {
  /// Creates the layout.
  const RemoteLayout({super.key, required this.device});

  /// The remote.
  final SavedDevice device;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    if (device.keys.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(l.remoteNoKeys, textAlign: TextAlign.center),
        ),
      );
    }
    final shown = <String>{};
    final sections = <Widget>[];
    Widget row(List<String> keys) {
      shown.addAll(keys);
      return _KeyRow(device: device, keys: keys);
    }

    final c = device.category;
    final hasDigits = Keys.digits.any(device.keys.containsKey);
    switch (c) {
      case DeviceCategory.tv ||
          DeviceCategory.setTopBox ||
          DeviceCategory.projector:
        sections
          ..add(
            row([
              Keys.power,
              Keys.input,
              if (c != DeviceCategory.projector) Keys.mute,
            ]),
          )
          ..add(
            _VolumeChannel(
              device: device,
              shown: shown,
              channel: c != DeviceCategory.projector,
            ),
          )
          ..add(_DPad(device: device, shown: shown))
          ..add(row([Keys.back, Keys.home, Keys.menu]));
        if (c == DeviceCategory.setTopBox) {
          sections
            ..add(row([Keys.guide, Keys.info, Keys.exit]))
            ..add(_ColourKeys(device: device, shown: shown));
        }
        if (c == DeviceCategory.projector) {
          sections
            ..add(row([Keys.focusOut, Keys.focusIn]))
            ..add(row([Keys.keystoneDown, Keys.keystoneUp]));
        }
        if (hasDigits && c != DeviceCategory.projector) {
          sections.add(_NumberPad(device: device, shown: shown));
        }
      case DeviceCategory.soundbar:
        sections
          ..add(row([Keys.power, Keys.input, Keys.mute]))
          ..add(row([Keys.volDown, Keys.volUp]))
          ..add(row([Keys.soundMode]));
      case DeviceCategory.fan || DeviceCategory.airPurifier:
        sections
          ..add(row([Keys.power, Keys.powerOn, Keys.powerOff]))
          ..add(row([Keys.speedDown, Keys.speed, Keys.speedUp]))
          ..add(row([Keys.mode, Keys.timer, Keys.sleep]))
          ..add(row([Keys.oscillate, Keys.swing, Keys.light]));
      case DeviceCategory.airConditioner || DeviceCategory.generic:
        break;
    }
    final rest = [
      for (final k
          in device.keys.values.toList()
            ..sort((a, b) => a.position.compareTo(b.position)))
        if (!shown.contains(k.key)) k.key,
    ];
    if (rest.isNotEmpty) {
      if (sections.isNotEmpty) {
        sections.add(
          Padding(
            padding: const EdgeInsets.only(top: 16, bottom: 8),
            child: Text(
              l.remoteMoreKeys,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
        );
      }
      sections.add(
        Wrap(
          spacing: 12,
          runSpacing: 12,
          alignment: WrapAlignment.center,
          children: [
            for (final k in rest)
              RemoteButton(device: device, keyName: k, wide: true, size: 52),
          ],
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final s in sections)
          Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: s),
      ],
    );
  }
}

class _KeyRow extends StatelessWidget {
  const _KeyRow({required this.device, required this.keys});

  final SavedDevice device;
  final List<String> keys;

  @override
  Widget build(BuildContext context) {
    final present = [
      for (final k in keys)
        if (device.keys.containsKey(k)) k,
    ];
    if (present.isEmpty) return const SizedBox.shrink();
    return Wrap(
      alignment: WrapAlignment.spaceEvenly,
      spacing: 16,
      runSpacing: 12,
      children: [
        for (final k in present)
          RemoteButton(device: device, keyName: k, size: 60),
      ],
    );
  }
}

class _VolumeChannel extends StatelessWidget {
  const _VolumeChannel({
    required this.device,
    required this.shown,
    required this.channel,
  });

  final SavedDevice device;
  final Set<String> shown;
  final bool channel;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    Widget rocker(String up, String down, String label) {
      shown.addAll([up, down]);
      if (!device.keys.containsKey(up) && !device.keys.containsKey(down)) {
        return const SizedBox.shrink();
      }
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          RemoteButton(device: device, keyName: up, size: 60),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: ExcludeSemantics(child: Text(label)),
          ),
          RemoteButton(device: device, keyName: down, size: 60),
        ],
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        rocker(Keys.volUp, Keys.volDown, l.keyVolumeShort),
        if (channel) rocker(Keys.chUp, Keys.chDown, l.keyChannelShort),
      ],
    );
  }
}

class _DPad extends StatelessWidget {
  const _DPad({required this.device, required this.shown});

  final SavedDevice device;
  final Set<String> shown;

  @override
  Widget build(BuildContext context) {
    const keys = [Keys.up, Keys.down, Keys.left, Keys.right, Keys.ok];
    shown.addAll(keys);
    if (!keys.any(device.keys.containsKey)) return const SizedBox.shrink();
    Widget b(String k) => RemoteButton(device: device, keyName: k, size: 60);
    return Center(
      child: SizedBox(
        width: 216,
        height: 216,
        child: Stack(
          children: [
            Align(alignment: Alignment.topCenter, child: b(Keys.up)),
            Align(alignment: Alignment.bottomCenter, child: b(Keys.down)),
            Align(alignment: Alignment.centerLeft, child: b(Keys.left)),
            Align(alignment: Alignment.centerRight, child: b(Keys.right)),
            Align(child: b(Keys.ok)),
          ],
        ),
      ),
    );
  }
}

class _ColourKeys extends StatelessWidget {
  const _ColourKeys({required this.device, required this.shown});

  final SavedDevice device;
  final Set<String> shown;

  @override
  Widget build(BuildContext context) {
    const colours = {
      Keys.red: Color(0xFFC62828),
      Keys.green: Color(0xFF2E7D32),
      Keys.yellow: Color(0xFFF9A825),
      Keys.blue: Color(0xFF1565C0),
    };
    shown.addAll(colours.keys);
    final l = AppLocalizations.of(context);
    final present = [
      for (final k in colours.keys)
        if (device.keys.containsKey(k)) k,
    ];
    if (present.isEmpty) return const SizedBox.shrink();
    return Wrap(
      alignment: WrapAlignment.spaceEvenly,
      spacing: 8,
      children: [
        for (final k in present)
          RemoteButton(
            device: device,
            keyName: k,
            color: colours[k],
            label: keyLabel(l, k),
            size: 48,
            wide: true,
          ),
      ],
    );
  }
}

class _NumberPad extends StatelessWidget {
  const _NumberPad({required this.device, required this.shown});

  final SavedDevice device;
  final Set<String> shown;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    shown
      ..addAll(Keys.digits)
      ..add(Keys.lastChannel);
    Widget d(int i) => RemoteButton(
      device: device,
      keyName: Keys.digits[i],
      label: '$i',
      size: 56,
    );
    return ExpansionTile(
      title: Text(l.remoteNumbers),
      children: [
        for (final r in const [
          [1, 2, 3],
          [4, 5, 6],
          [7, 8, 9],
        ])
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [for (final i in r) d(i)],
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              RemoteButton(device: device, keyName: Keys.lastChannel, size: 56),
              d(0),
              const SizedBox(width: 56),
            ],
          ),
        ),
      ],
    );
  }
}

enum _MenuAction { favourite, rename, transport, learn, pronto, delete }

class _DeviceMenu extends StatelessWidget {
  const _DeviceMenu({required this.device});

  final SavedDevice device;

  Future<void> _rename(BuildContext context) async {
    final l = AppLocalizations.of(context);
    final controller = TextEditingController(text: device.name);
    final name = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(l.deviceMenuRename),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 40,
          decoration: InputDecoration(labelText: l.deviceNameLabel),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: Text(l.actionCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, controller.text.trim()),
            child: Text(l.actionSave),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty || !context.mounted) return;
    await AppScope.of(context).devices.rename(device.id, name);
  }

  Future<void> _chooseTransport(BuildContext context) async {
    final l = AppLocalizations.of(context);
    final services = AppScope.of(context);
    final transports = services.registry.all;
    final picked = await showDialog<String>(
      context: context,
      builder: (c) => SimpleDialog(
        title: Text(l.deviceMenuTransport),
        children: [
          RadioGroup<String>(
            groupValue: device.transportId ?? '',
            onChanged: (v) => Navigator.pop(c, v),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                RadioListTile<String>(value: '', title: Text(l.transportAuto)),
                for (final t in transports)
                  RadioListTile<String>(
                    value: t.id,
                    title: Text(t.displayName),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    if (picked == null || !context.mounted) return;
    await services.devices.setTransport(
      device.id,
      picked.isEmpty ? null : picked,
    );
  }

  Future<void> _delete(BuildContext context) async {
    final l = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(l.deviceDeleteConfirm(device.name)),
        content: Text(l.deviceDeleteBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(l.actionCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(l.actionDelete),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final services = AppScope.of(context);
    Navigator.of(context).pop();
    await services.devices.delete(device.id);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return PopupMenuButton<_MenuAction>(
      onSelected: (a) async {
        final services = AppScope.of(context);
        switch (a) {
          case _MenuAction.favourite:
            await services.devices.setFavourite(
              device.id,
              favourite: !device.favourite,
            );
          case _MenuAction.rename:
            await _rename(context);
          case _MenuAction.transport:
            await _chooseTransport(context);
          case _MenuAction.learn:
            await Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => LearnScreen(deviceId: device.id),
              ),
            );
          case _MenuAction.pronto:
            await addProntoKey(context, device);
          case _MenuAction.delete:
            await _delete(context);
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          value: _MenuAction.favourite,
          child: Text(
            device.favourite ? l.deviceMenuUnfavourite : l.deviceMenuFavourite,
          ),
        ),
        PopupMenuItem(
          value: _MenuAction.rename,
          child: Text(l.deviceMenuRename),
        ),
        PopupMenuItem(
          value: _MenuAction.transport,
          child: Text(l.deviceMenuTransport),
        ),
        PopupMenuItem(value: _MenuAction.learn, child: Text(l.deviceMenuLearn)),
        PopupMenuItem(
          value: _MenuAction.pronto,
          child: Text(l.deviceMenuPronto),
        ),
        PopupMenuItem(
          value: _MenuAction.delete,
          child: Text(l.deviceMenuDelete),
        ),
      ],
    );
  }
}

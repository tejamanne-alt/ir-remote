/// Home: favourites, recents and remotes grouped by room.
library;

import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../l10n/app_localizations.dart';
import '../../services/app_services.dart';
import '../add_device/add_device_flow.dart';
import '../hubs/hubs_screen.dart';
import '../labels.dart';
import '../macros/macros_screen.dart';
import '../remote/remote_screen.dart';
import '../settings/settings_screen.dart';

/// The home screen.
class HomeScreen extends StatelessWidget {
  /// Creates the screen.
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final services = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.homeTitle),
        actions: [
          IconButton(
            tooltip: l.menuMacros,
            icon: const Icon(Icons.playlist_play),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const MacrosScreen()),
            ),
          ),
          IconButton(
            tooltip: l.menuHubs,
            icon: const Icon(Icons.router_outlined),
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute<void>(builder: (_) => const HubsScreen())),
          ),
          IconButton(
            tooltip: l.menuSettings,
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: Text(l.actionAddDevice),
        onPressed: () => Navigator.of(
          context,
        ).push(MaterialPageRoute<void>(builder: (_) => const CategoryScreen())),
      ),
      body: SafeArea(
        child: StreamBuilder<void>(
          stream: services.registry.changes,
          builder: (context, _) => StreamBuilder<List<Room>>(
            stream: services.devices.watchRooms(),
            builder: (context, roomSnap) => StreamBuilder<List<SavedDevice>>(
              stream: services.devices.watchDevices(),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                return _HomeBody(
                  devices: snap.data!,
                  rooms: roomSnap.data ?? const [],
                  canSend: services.canSend,
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _HomeBody extends StatelessWidget {
  const _HomeBody({
    required this.devices,
    required this.rooms,
    required this.canSend,
  });

  final List<SavedDevice> devices;
  final List<Room> rooms;
  final bool canSend;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final banner = canSend
        ? null
        : MaterialBanner(
            content: Text(l.noTransportBanner),
            leading: const Icon(Icons.portable_wifi_off),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const HubsScreen(startAdding: true),
                  ),
                ),
                child: Text(l.actionConnectHub),
              ),
            ],
          );
    if (devices.isEmpty) {
      return ListView(
        children: [
          ?banner,
          Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              children: [
                Icon(
                  Icons.settings_remote,
                  size: 72,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(l.homeEmptyTitle, style: theme.textTheme.titleLarge),
                const SizedBox(height: 8),
                Text(l.homeEmptyBody, textAlign: TextAlign.center),
              ],
            ),
          ),
        ],
      );
    }
    final favourites = [
      for (final d in devices)
        if (d.favourite) d,
    ];
    final recents = [
      for (final d in devices)
        if (d.lastUsedAt != null) d,
    ]..sort((a, b) => b.lastUsedAt!.compareTo(a.lastUsedAt!));
    final byRoom = <int?, List<SavedDevice>>{};
    for (final d in devices) {
      final roomKnown = rooms.any((r) => r.id == d.roomId);
      (byRoom[roomKnown ? d.roomId : null] ??= []).add(d);
    }
    Widget section(
      String title,
      List<SavedDevice> list, {
      bool chips = false,
    }) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Semantics(
            header: true,
            child: Text(title, style: theme.textTheme.titleSmall),
          ),
        ),
        if (chips)
          SizedBox(
            height: 56,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (final d in list.take(6))
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ActionChip(
                      avatar: Icon(categoryIcon(d.category), size: 18),
                      label: Text(d.name),
                      onPressed: () => _open(context, d),
                    ),
                  ),
              ],
            ),
          )
        else
          for (final d in list) _DeviceTile(device: d),
      ],
    );
    return ListView(
      padding: const EdgeInsets.only(bottom: 96),
      children: [
        ?banner,
        if (favourites.isNotEmpty) section(l.sectionFavourites, favourites),
        if (recents.isNotEmpty) section(l.sectionRecents, recents, chips: true),
        for (final r in rooms)
          if (byRoom[r.id] != null) section(r.name, byRoom[r.id]!),
        if (byRoom[null] != null)
          section(rooms.isEmpty ? l.homeTitle : l.sectionNoRoom, byRoom[null]!),
      ],
    );
  }
}

void _open(BuildContext context, SavedDevice d) => Navigator.of(
  context,
).push(MaterialPageRoute<void>(builder: (_) => RemoteScreen(deviceId: d.id)));

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({required this.device});

  final SavedDevice device;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final category = categoryLabel(l, device.category);
    return ListTile(
      minTileHeight: 64,
      leading: Icon(categoryIcon(device.category)),
      title: Text(device.name),
      subtitle: Text(
        device.brand == null
            ? category
            : l.deviceSubtitle(category, device.brand!),
      ),
      trailing: device.favourite
          ? const Icon(Icons.star, semanticLabel: '')
          : null,
      onTap: () => _open(context, device),
    );
  }
}

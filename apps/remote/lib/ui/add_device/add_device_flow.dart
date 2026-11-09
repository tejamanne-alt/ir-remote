/// Add device: category → brand → guided code matching → name and room.
library;

import 'package:flutter/material.dart';
import 'package:ir_core/ir_core.dart';

import '../../data/models.dart';
import '../../data/names.dart';
import '../../l10n/app_localizations.dart';
import '../../services/app_services.dart';
import '../../services/code_library.dart';
import '../labels.dart';
import '../learn/flipper_import.dart';
import '../learn/learn_screen.dart';
import '../learn/pronto_dialog.dart';
import '../remote/remote_screen.dart';
import '../widgets/remote_button.dart';
import '../widgets/text_input_dialog.dart';

/// Categories offered when adding a device, in display order.
const List<DeviceCategory> addableCategories = [
  DeviceCategory.tv,
  DeviceCategory.setTopBox,
  DeviceCategory.airConditioner,
  DeviceCategory.fan,
  DeviceCategory.projector,
  DeviceCategory.soundbar,
  DeviceCategory.airPurifier,
  DeviceCategory.generic,
];

/// Step 1: pick a category.
class CategoryScreen extends StatelessWidget {
  /// Creates the screen.
  const CategoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.addDeviceTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              l.chooseCategory,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            for (final c in addableCategories)
              Card(
                child: ListTile(
                  minTileHeight: 64,
                  leading: Icon(categoryIcon(c)),
                  title: Text(categoryLabel(l, c)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => c == DeviceCategory.generic
                          ? const SaveDeviceScreen(
                              category: DeviceCategory.generic,
                            )
                          : BrandScreen(category: c),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Step 2: pick a brand (search, primary market first, "Not listed").
class BrandScreen extends StatefulWidget {
  /// Creates the screen.
  const BrandScreen({super.key, required this.category});

  /// Chosen category.
  final DeviceCategory category;

  @override
  State<BrandScreen> createState() => _BrandScreenState();
}

class _BrandScreenState extends State<BrandScreen> {
  String _query = '';

  void _open(String? brand) {
    final codes = AppScope.of(context).codes;
    final sets = codes.codeSets(widget.category, brand: brand);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MatchingScreen(
          category: widget.category,
          brand: brand,
          codeSets: sets,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final brands = AppScope.of(context).codes
        .brands(widget.category, query: _query);
    return Scaffold(
      appBar: AppBar(title: Text(l.chooseBrand)),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  labelText: l.searchBrands,
                  border: const OutlineInputBorder(),
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            Expanded(
              child: ListView(
                children: [
                  if (brands.isEmpty && _query.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(l.noBrandsMatch(_query)),
                    ),
                  for (final b in brands)
                    ListTile(
                      minTileHeight: 56,
                      title: Text(b.name),
                      onTap: () => _open(b.name),
                    ),
                  const Divider(),
                  ListTile(
                    minTileHeight: 56,
                    leading: const Icon(Icons.help_outline),
                    title: Text(l.brandNotListed),
                    subtitle: Text(l.brandNotListedHint),
                    onTap: () => _open(null),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _Phase { power, confirm }

/// Step 3: try code sets one by one until the appliance responds twice.
class MatchingScreen extends StatefulWidget {
  /// Creates the screen.
  const MatchingScreen({
    super.key,
    required this.category,
    required this.brand,
    required this.codeSets,
  });

  /// Category.
  final DeviceCategory category;

  /// Brand, or `null` when not listed.
  final String? brand;

  /// Candidates in matching order.
  final List<CodeSet> codeSets;

  @override
  State<MatchingScreen> createState() => _MatchingScreenState();
}

class _MatchingScreenState extends State<MatchingScreen> {
  int _index = 0;
  _Phase _phase = _Phase.power;
  bool _sent = false;
  bool _sending = false;

  /// Toggle state of the appliance being matched (RC5/RC6), handed to the
  /// saved remote so its first press flips the bit again.
  final String _toggleScope = 'matching:${newId()}';

  CodeSet? get _set =>
      _index < widget.codeSets.length ? widget.codeSets[_index] : null;

  String? _testKey(CodeSet s) =>
      s.powerTestKey ?? (s.keys.isEmpty ? null : s.keys.keys.first);

  /// A second, different key to rule out sets that share a power code.
  String? _confirmKey(CodeSet s) {
    final preferred = confirmKeyFor(widget.category);
    final power = _testKey(s);
    if (preferred != power && s.keys.containsKey(preferred)) return preferred;
    const fallbacks = [
      Keys.volUp,
      Keys.chUp,
      Keys.mute,
      Keys.menu,
      Keys.input,
      Keys.mode,
      Keys.speedUp,
    ];
    for (final k in fallbacks) {
      if (k != power && s.keys.containsKey(k)) return k;
    }
    for (final k in s.keys.keys) {
      if (k != power && k != Keys.powerOn && k != Keys.powerOff) return k;
    }
    return null;
  }

  Future<void> _send(String key) async {
    final s = _set;
    if (s == null) return;
    final services = AppScope.of(context);
    final l = AppLocalizations.of(context);
    // The result belongs to this set and step only; an answer or skip that
    // happened meanwhile makes it stale.
    final index = _index;
    final phase = _phase;
    final SavedKey k;
    try {
      k = _snapshot(s, key);
    } on CommandResolutionException {
      _next(); // a broken set is skipped, never shown as a dead end
      return;
    }
    setState(() => _sending = true);
    try {
      final o = await services.send.sendUnsavedKey(
        k,
        toggleScope: _toggleScope,
      );
      if (!mounted || index != _index || phase != _phase) return;
      final msg = outcomeMessage(l, o);
      if (msg != null) showSendError(context, msg);
      setState(() => _sent = o.ok || _sent);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  static SavedKey _snapshot(CodeSet s, String key) {
    final code = s.keys[key];
    if (code == null) {
      throw CommandResolutionException('code set ${s.id} has no key $key');
    }
    try {
      return snapshotKey(key, code);
    } on Object catch (e) {
      throw CommandResolutionException('code set ${s.id} key $key: $e');
    }
  }

  void _next() => setState(() {
    _index++;
    _phase = _Phase.power;
    _sent = false;
  });

  void _yes() {
    final s = _set!;
    if (_phase == _Phase.power && _confirmKey(s) != null) {
      setState(() {
        _phase = _Phase.confirm;
        _sent = false;
      });
      return;
    }
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => SaveDeviceScreen(
          category: widget.category,
          brand: widget.brand,
          codeSet: s,
          toggleScope: _toggleScope,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final s = _set;
    return Scaffold(
      appBar: AppBar(title: Text(l.matchingTitle)),
      body: SafeArea(
        child: s == null
            ? _AllFailed(
                category: widget.category,
                brand: widget.brand,
                empty: widget.codeSets.isEmpty,
              )
            : _buildStep(context, l, s),
      ),
    );
  }

  Widget _buildStep(BuildContext context, AppLocalizations l, CodeSet s) {
    final theme = Theme.of(context);
    final key = _phase == _Phase.power ? _testKey(s) : _confirmKey(s);
    if (key == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _next());
      return const SizedBox.shrink();
    }
    final keyText = keyLabel(l, key);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Semantics(
          liveRegion: true,
          child: Text(
            l.matchingProgress(_index + 1, widget.codeSets.length),
            style: theme.textTheme.labelLarge,
          ),
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(value: (_index + 1) / widget.codeSets.length),
        const SizedBox(height: 24),
        Text(
          _phase == _Phase.power ? l.matchingPointAt : l.matchingConfirmTitle,
          style: theme.textTheme.titleLarge,
        ),
        if (_phase == _Phase.confirm) Text(l.matchingConfirmBody(keyText)),
        const SizedBox(height: 16),
        FilledButton.icon(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
          icon: Icon(keyIcon(key) ?? Icons.send),
          label: Text(l.matchingSend(keyText)),
          onPressed: _sending ? null : () => _send(key),
        ),
        const SizedBox(height: 8),
        Text(l.irBasics, style: theme.textTheme.bodySmall),
        if (_sent) ...[
          const SizedBox(height: 24),
          Text(l.matchingDidItRespond, style: theme.textTheme.titleMedium),
          if (_phase == _Phase.power)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                l.matchingPowerNote,
                style: theme.textTheme.bodySmall,
              ),
            ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              // An answer waits for "Send again" to finish, so it is never
              // given for a code that has not gone out yet.
              FilledButton(
                onPressed: _sending ? null : _yes,
                child: Text(l.answerYes),
              ),
              OutlinedButton(
                onPressed: _sending ? null : _next,
                child: Text(l.answerNo),
              ),
              TextButton(
                onPressed: _sending ? null : () => _send(key),
                child: Text(l.answerSendAgain),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _AllFailed extends StatelessWidget {
  const _AllFailed({
    required this.category,
    required this.brand,
    required this.empty,
  });

  final DeviceCategory category;
  final String? brand;
  final bool empty;

  Future<SavedDevice> _createEmpty(BuildContext context) async {
    final l = AppLocalizations.of(context);
    final services = AppScope.of(context);
    final device = SavedDevice(
      id: newId(),
      name: _defaultName(l, category, brand),
      category: category,
      brand: brand,
      createdAt: DateTime.now(),
    );
    await services.devices.save(device);
    return device;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          empty ? l.noCodeSets : l.matchingAllFailedTitle,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(l.matchingAllFailedBody),
        const SizedBox(height: 16),
        Card(
          child: ListTile(
            leading: const Icon(Icons.school_outlined),
            title: Text(l.optionLearn),
            onTap: () async {
              final nav = Navigator.of(context);
              final d = await _createEmpty(context);
              nav.pushReplacement(
                MaterialPageRoute<void>(
                  builder: (_) => RemoteScreen(deviceId: d.id),
                ),
              );
              await nav.push(
                MaterialPageRoute<void>(
                  builder: (_) => LearnScreen(deviceId: d.id),
                ),
              );
            },
          ),
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.file_open_outlined),
            title: Text(l.optionImportFlipper),
            onTap: () async {
              final nav = Navigator.of(context);
              final devices = AppScope.of(context).devices;
              final d = await _createEmpty(context);
              int? n;
              try {
                if (context.mounted) n = await importFlipperInto(context, d.id);
              } finally {
                // Nothing imported (cancelled, unreadable file, or an error):
                // never leave an empty remote behind.
                if (n == null || n == 0) await devices.delete(d.id);
              }
              if (n == null || n == 0) return;
              nav.pushReplacement(
                MaterialPageRoute<void>(
                  builder: (_) => RemoteScreen(deviceId: d.id),
                ),
              );
            },
          ),
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.content_paste),
            title: Text(l.optionPastePronto),
            onTap: () async {
              final nav = Navigator.of(context);
              final devices = AppScope.of(context).devices;
              final entry = await showProntoDialog(
                context,
                initialLabel: l.keyPower,
              );
              if (entry == null || !context.mounted) return;
              final d = await _createEmpty(context);
              final k = keyFromCapture(
                customKeyName(entry.label),
                entry.label,
                entry.signal,
              );
              await devices.upsertKey(
                d.id,
                SavedKey(
                  key: k.key,
                  label: k.label,
                  signal: k.signal,
                  toggled: k.toggled,
                  source: KeySource.imported,
                  protocol: k.protocol,
                  params: k.params,
                ),
              );
              nav.pushReplacement(
                MaterialPageRoute<void>(
                  builder: (_) => RemoteScreen(deviceId: d.id),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

String _defaultName(AppLocalizations l, DeviceCategory c, String? brand) {
  final base = brand == null
      ? categoryLabel(l, c)
      : '$brand ${categoryLabel(l, c)}';
  return base.length > 40 ? base.substring(0, 40) : base;
}

/// Step 4: name the device, pick a room, save the code-set reference and a
/// snapshot of every resolved signal.
class SaveDeviceScreen extends StatefulWidget {
  /// Creates the screen.
  const SaveDeviceScreen({
    super.key,
    required this.category,
    this.brand,
    this.codeSet,
    this.toggleScope,
  });

  /// Category.
  final DeviceCategory category;

  /// Brand, if chosen.
  final String? brand;

  /// The matched code set (`null` for a custom remote).
  final CodeSet? codeSet;

  /// Toggle scope of the matching that found [codeSet], if any.
  final String? toggleScope;

  @override
  State<SaveDeviceScreen> createState() => _SaveDeviceScreenState();
}

class _SaveDeviceScreenState extends State<SaveDeviceScreen> {
  late final TextEditingController _name;
  int? _roomId;
  bool _saving = false;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final l = AppLocalizations.of(context);
    if (!_initialized) {
      _initialized = true;
      _name = TextEditingController(
        text: widget.category == DeviceCategory.generic
            ? l.genericDeviceName
            : _defaultName(l, widget.category, widget.brand),
      );
    }
  }

  bool _initialized = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _newRoom() async {
    final l = AppLocalizations.of(context);
    final services = AppScope.of(context);
    final name = await showTextInputDialog(
      context,
      title: l.roomNewTitle,
      confirmLabel: l.actionAdd,
    );
    if (name == null) return;
    final int id;
    try {
      id = await services.devices.addRoom(name);
    } on Object {
      if (mounted) showSendError(context, l.nameSaveFailed);
      return;
    }
    if (mounted) setState(() => _roomId = id);
  }

  Future<void> _save() async {
    final l = AppLocalizations.of(context);
    final name = _name.text.trim();
    if (name.isEmpty || name.length > 40) {
      setState(() => _error = l.deviceNameError);
      return;
    }
    setState(() => _saving = true);
    final services = AppScope.of(context);
    final keys = <String, SavedKey>{};
    var position = 0;
    final set = widget.codeSet;
    if (set != null) {
      for (final e in set.keys.entries) {
        try {
          keys[e.key] = snapshotKey(e.key, e.value, position: position++);
        } on Object {
          continue; // a key the codecs cannot render is left out
        }
      }
    }
    final device = SavedDevice(
      id: newId(),
      name: name,
      category: widget.category,
      brand: widget.brand ?? set?.brand,
      codeSetId: set?.id,
      roomId: _roomId,
      createdAt: DateTime.now(),
      keys: keys,
    );
    await services.devices.save(device);
    final scope = widget.toggleScope;
    if (scope != null) {
      services.send.adoptToggleState(scope: scope, deviceId: device.id);
    }
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    nav.popUntil((r) => r.isFirst);
    messenger.showSnackBar(SnackBar(content: Text(l.deviceSaved(name))));
    await nav.push(
      MaterialPageRoute<void>(
        builder: (_) => RemoteScreen(deviceId: device.id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final services = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.saveDeviceTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            TextField(
              controller: _name,
              maxLength: 40,
              decoration: InputDecoration(
                labelText: l.deviceNameLabel,
                errorText: _error,
              ),
            ),
            const SizedBox(height: 16),
            StreamBuilder<List<Room>>(
              stream: services.devices.watchRooms(),
              builder: (context, snap) {
                final rooms = snap.data ?? const <Room>[];
                return DropdownButtonFormField<int?>(
                  key: ValueKey(Object.hash(_roomId, rooms.length)),
                  initialValue: _roomId,
                  decoration: InputDecoration(labelText: l.roomLabel),
                  items: [
                    DropdownMenuItem<int?>(child: Text(l.roomNone)),
                    for (final r in rooms)
                      DropdownMenuItem<int?>(value: r.id, child: Text(r.name)),
                    DropdownMenuItem<int?>(value: -1, child: Text(l.roomNew)),
                  ],
                  onChanged: (v) {
                    if (v == -1) {
                      _newRoom();
                    } else {
                      setState(() => _roomId = v);
                    }
                  },
                );
              },
            ),
            const SizedBox(height: 32),
            FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
              ),
              onPressed: _saving ? null : _save,
              child: Text(l.actionSave),
            ),
          ],
        ),
      ),
    );
  }
}

/// Brand entries helper exposed for tests.
List<BrandEntry> brandsFor(CodeLibrary codes, DeviceCategory c) =>
    codes.brands(c);

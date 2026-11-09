/// Deduplication by signal equivalence and ranking within a brand.
library;

import 'package:ir_core/ir_core.dart';

import 'candidate.dart';

/// Decides whether two key codes send the same signal.
///
/// Protocol codes are equivalent when protocol and parameters are equal.
/// Otherwise both are rendered and their main frames compared: the same
/// number of durations, each pair within [tolerance] of each other in both
/// directions (default ±25%), and carriers within 10% (a raw capture's
/// measured carrier rarely equals the nominal one).
final class SignalEquivalence {
  /// Creates a comparer.
  SignalEquivalence({this.tolerance = const TimingTolerance()});

  /// Per-duration tolerance.
  final TimingTolerance tolerance;

  final Map<KeyCode, IrSignal> _rendered = Map.identity();

  IrSignal _render(KeyCode c) =>
      _rendered[c] ??= c.toSignal(ProtocolRegistry.standard);

  /// Whether [a] and [b] are equivalent.
  bool equivalent(KeyCode a, KeyCode b) {
    if (a is ProtocolKeyCode && b is ProtocolKeyCode) return sameCode(a, b);
    final sa = _render(a);
    final sb = _render(b);
    final hi = sa.carrierHz > sb.carrierHz ? sa.carrierHz : sb.carrierHz;
    if ((sa.carrierHz - sb.carrierHz).abs() > hi * 0.1) return false;
    final da = sa.durationsUs;
    final db = sb.durationsUs;
    if (da.length != db.length) return false;
    for (var i = 0; i < da.length; i++) {
      if (!tolerance.matches(da[i], db[i]) ||
          !tolerance.matches(db[i], da[i])) {
        return false;
      }
    }
    return true;
  }

  /// Whether every key of [small] exists in [big] with an equivalent code.
  bool covers(Candidate big, Candidate small) {
    if (small.keys.length > big.keys.length) return false;
    for (final e in small.keys.entries) {
      final other = big.keys[e.key];
      if (other == null || !equivalent(other, e.value)) return false;
    }
    return true;
  }
}

/// Keys each category's remote must have (the contract's coverage table),
/// used to prefer complete code sets.
const Map<DeviceCategory, Set<String>> coreKeys = {
  DeviceCategory.tv: _tvKeys,
  DeviceCategory.setTopBox: {
    ..._tvKeys,
    Keys.guide,
    Keys.info,
    Keys.red,
    Keys.green,
    Keys.yellow,
    Keys.blue,
  },
  DeviceCategory.airConditioner: {
    Keys.power,
    Keys.mode,
    Keys.tempUp,
    Keys.tempDown,
    Keys.speed,
  },
  DeviceCategory.fan: {
    Keys.power,
    Keys.speed,
    Keys.speedUp,
    Keys.speedDown,
    Keys.timer,
    Keys.sleep,
    Keys.light,
  },
  DeviceCategory.projector: {
    Keys.power,
    Keys.input,
    Keys.up,
    Keys.down,
    Keys.left,
    Keys.right,
    Keys.ok,
    Keys.focusIn,
    Keys.focusOut,
    Keys.keystoneUp,
    Keys.keystoneDown,
  },
  DeviceCategory.soundbar: {
    Keys.power,
    Keys.input,
    Keys.volUp,
    Keys.volDown,
    Keys.mute,
    Keys.soundMode,
  },
  DeviceCategory.airPurifier: {Keys.power, Keys.speed, Keys.mode, Keys.timer},
  DeviceCategory.generic: {},
};

const Set<String> _tvKeys = {
  Keys.power,
  Keys.input,
  Keys.volUp,
  Keys.volDown,
  Keys.mute,
  Keys.chUp,
  Keys.chDown,
  Keys.up,
  Keys.down,
  Keys.left,
  Keys.right,
  Keys.ok,
  Keys.back,
  Keys.home,
  Keys.menu,
  ...Keys.digits,
};

int _mapped(Candidate c) =>
    c.keys.keys.where((k) => !k.startsWith(Keys.customPrefix)).length;

/// Merges candidates whose keys are all present, with equivalent codes, in
/// a kept candidate of the same brand and category, and returns the kept
/// ones.
///
/// Within a group, larger sets are visited first (more mapped keys, then
/// more keys), then the preferred source, then the path, so an exact
/// duplicate is merged into the best-provenance copy and a subset into its
/// superset. Merged candidates are recorded in [Candidate.merged].
List<Candidate> deduplicate(
  List<Candidate> candidates, {
  SignalEquivalence? equivalence,
}) {
  final eq = equivalence ?? SignalEquivalence();
  final groups = <String, List<Candidate>>{};
  for (final c in candidates) {
    groups.putIfAbsent('${c.category.name}\u0000${c.brand}', () => []).add(c);
  }
  final kept = <Candidate>[];
  for (final key in groups.keys.toList()..sort()) {
    final group = groups[key]!
      ..sort((a, b) {
        var r = _mapped(b).compareTo(_mapped(a));
        if (r != 0) return r;
        r = b.keys.length.compareTo(a.keys.length);
        if (r != 0) return r;
        r = a.source.priority.compareTo(b.source.priority);
        if (r != 0) return r;
        return (a.provenance.path ?? a.id).compareTo(b.provenance.path ?? b.id);
      });
    final groupKept = <Candidate>[];
    for (final c in group) {
      final home = groupKept.where((k) => eq.covers(k, c)).firstOrNull;
      if (home != null) {
        home.merged.add(c);
      } else {
        groupKept.add(c);
      }
    }
    kept.addAll(groupKept);
  }
  return kept;
}

/// Orders the code sets of one brand and category for matching, best
/// first: a power key; then how many source files the set stands for
/// (merged duplicates, a popularity signal); then core keys of the
/// category; then mapped keys; then all-protocol before raw; then source
/// preference; then ID. Returns rank per candidate ID.
Map<String, int> rankWithinBrand(List<Candidate> sets) {
  int hasPower(Candidate c) =>
      c.keys.containsKey(Keys.power) || c.keys.containsKey(Keys.powerOn)
      ? 0
      : 1;
  int core(Candidate c) =>
      c.keys.keys.where((k) => coreKeys[c.category]!.contains(k)).length;
  int raw(Candidate c) => c.keys.values.any((k) => k is RawKeyCode) ? 1 : 0;
  final sorted = [...sets]
    ..sort((a, b) {
      var r = hasPower(a).compareTo(hasPower(b));
      if (r != 0) return r;
      r = b.weight.compareTo(a.weight);
      if (r != 0) return r;
      r = core(b).compareTo(core(a));
      if (r != 0) return r;
      r = _mapped(b).compareTo(_mapped(a));
      if (r != 0) return r;
      r = raw(a).compareTo(raw(b));
      if (r != 0) return r;
      r = a.source.priority.compareTo(b.source.priority);
      if (r != 0) return r;
      return a.id.compareTo(b.id);
    });
  return {for (var i = 0; i < sorted.length; i++) sorted[i].id: i};
}

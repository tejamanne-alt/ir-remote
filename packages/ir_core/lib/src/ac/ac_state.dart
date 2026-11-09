/// The stateful air-conditioner model: full state, per-protocol capabilities
/// and the encoder contract.
///
/// AC remotes send the whole state in every frame. The app never knows the
/// unit's real state; it only knows what it last sent.
library;

import '../signal/ir_signal.dart';

/// Operating modes.
enum AcMode {
  /// Unit chooses.
  auto,

  /// Cooling.
  cool,

  /// Dehumidify.
  dry,

  /// Fan only.
  fan,

  /// Heating.
  heat,
}

/// Optional features a protocol may carry.
enum AcFeature {
  /// Vertical swing (louvre).
  swingV,

  /// Horizontal swing.
  swingH,

  /// Turbo / powerful.
  turbo,

  /// Eco / energy saving.
  eco,

  /// Sleep curve.
  sleep,

  /// Quiet / silent fan.
  quiet,

  /// Display light.
  light,

  /// Self-clean.
  clean,
}

/// How a feature is controlled by the protocol.
enum FeatureControl {
  /// The frame carries the feature's on/off state.
  state,

  /// The frame carries a "press" event that toggles the feature on the unit.
  /// The UI labels these "press to toggle".
  toggle,
}

/// How power is encoded.
enum PowerControl {
  /// A discrete on/off bit: explicit On and Off buttons.
  discrete,

  /// A toggle event: one Power button with a warning.
  toggle,
}

/// The complete state the app sends to an AC.
final class AcState {
  /// Creates a state. [fan] is 0 for auto, or a level from 1.
  const AcState({
    required this.power,
    required this.mode,
    required this.targetTempC,
    this.fan = 0,
    this.features = const {},
  });

  /// The safe test state used for variant matching: on, cool, 24 °C, auto fan.
  static const AcState matchingProbe = AcState(
    power: true,
    mode: AcMode.cool,
    targetTempC: 24,
  );

  /// Power on (for discrete-power protocols) or the state assumed after the
  /// last toggle.
  final bool power;

  /// Operating mode.
  final AcMode mode;

  /// Target temperature in °C. Encoders take °C only; °F is a UI concern.
  final double targetTempC;

  /// Fan: 0 = auto, otherwise level 1..N.
  final int fan;

  /// State of each stateful feature that is on. Features absent here are off.
  final Set<AcFeature> features;

  /// Whether [feature] is on.
  bool has(AcFeature feature) => features.contains(feature);

  /// Returns a copy with the given fields replaced.
  AcState copyWith({
    bool? power,
    AcMode? mode,
    double? targetTempC,
    int? fan,
    Set<AcFeature>? features,
  }) => AcState(
    power: power ?? this.power,
    mode: mode ?? this.mode,
    targetTempC: targetTempC ?? this.targetTempC,
    fan: fan ?? this.fan,
    features: features ?? this.features,
  );

  /// Returns a copy with [feature] switched on or off.
  AcState withFeature(AcFeature feature, {required bool on}) => copyWith(
    features: on ? {...features, feature} : ({...features}..remove(feature)),
  );

  /// JSON form.
  Map<String, Object?> toJson() => {
    'power': power,
    'mode': mode.name,
    'targetTempC': targetTempC,
    'fan': fan,
    'features': [
      for (final f in AcFeature.values)
        if (features.contains(f)) f.name,
    ],
  };

  /// Parses [toJson] output; throws [FormatException].
  static AcState fromJson(Object? json) {
    if (json is! Map) throw const FormatException('AC state must be an object');
    final power = json['power'];
    final mode = json['mode'];
    final temp = json['targetTempC'];
    final fan = json['fan'] ?? 0;
    final features = json['features'] ?? const <Object?>[];
    if (power is! bool ||
        mode is! String ||
        temp is! num ||
        fan is! int ||
        features is! List) {
      throw const FormatException('AC state has missing or mistyped fields');
    }
    AcMode parseMode(String n) => AcMode.values.firstWhere(
      (m) => m.name == n,
      orElse: () => throw FormatException('unknown AC mode "$n"'),
    );
    AcFeature parseFeature(Object? n) => AcFeature.values.firstWhere(
      (f) => f.name == n,
      orElse: () => throw FormatException('unknown AC feature "$n"'),
    );
    return AcState(
      power: power,
      mode: parseMode(mode),
      targetTempC: temp.toDouble(),
      fan: fan,
      features: {for (final f in features) parseFeature(f)},
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AcState &&
      other.power == power &&
      other.mode == mode &&
      other.targetTempC == targetTempC &&
      other.fan == fan &&
      other.features.length == features.length &&
      other.features.containsAll(features);

  @override
  int get hashCode => Object.hash(
    power,
    mode,
    targetTempC,
    fan,
    Object.hashAllUnordered(features),
  );

  @override
  String toString() =>
      'AcState(${power ? 'on' : 'off'}, ${mode.name}, '
      '$targetTempC °C, fan ${fan == 0 ? 'auto' : fan}, '
      '${features.map((f) => f.name).join(',')})';
}

/// What one protocol variant supports. The UI renders only what is declared.
final class AcCapabilities {
  /// Creates a capability descriptor.
  const AcCapabilities({
    required this.version,
    required this.modes,
    required this.minTempC,
    required this.maxTempC,
    required this.tempStepC,
    required this.fanLevels,
    required this.fanAuto,
    required this.power,
    this.features = const {},
  });

  /// Descriptor version, stored with each saved AC remote.
  final int version;

  /// Supported modes.
  final Set<AcMode> modes;

  /// Lowest target temperature.
  final double minTempC;

  /// Highest target temperature.
  final double maxTempC;

  /// Temperature step (1.0 or 0.5).
  final double tempStepC;

  /// Number of fixed fan levels.
  final int fanLevels;

  /// Whether auto fan exists.
  final bool fanAuto;

  /// How power is encoded.
  final PowerControl power;

  /// Supported features and how each is controlled.
  final Map<AcFeature, FeatureControl> features;

  /// Clamps [s] into this descriptor: temperature to range and step, fan to
  /// the available levels, mode to a supported one, features to stateful
  /// supported ones.
  AcState clamp(AcState s) {
    var t = s.targetTempC.clamp(minTempC, maxTempC).toDouble();
    t = minTempC + ((t - minTempC) / tempStepC).round() * tempStepC;
    var fan = s.fan.clamp(0, fanLevels);
    if (fan == 0 && !fanAuto) fan = 1;
    final mode = modes.contains(s.mode)
        ? s.mode
        : (modes.contains(AcMode.cool) ? AcMode.cool : modes.first);
    return AcState(
      power: s.power,
      mode: mode,
      targetTempC: t,
      fan: fan,
      features: {
        for (final f in s.features)
          if (features[f] == FeatureControl.state) f,
      },
    );
  }
}

/// Encodes full AC state into a frame. Implementations are pure and compute
/// their own checksums.
abstract interface class AcEncoder {
  /// Protocol variant ID, stored with saved AC remotes.
  String get protocolId;

  /// Human label, for example "Brand A (variant 1)".
  String get label;

  /// What the variant supports.
  AcCapabilities get capabilities;

  /// Whether the encoder's output matches human-captured fixtures. Encoders
  /// that are not verified stay behind a flag that is off in release builds.
  bool get verified;

  /// Encodes [state] (clamped to [capabilities] first). [toggle] carries a
  /// press-to-toggle event for a feature whose control is
  /// [FeatureControl.toggle], or the power toggle when power is a toggle.
  IrSignal encode(AcState state, {AcToggle? toggle});
}

/// A press-to-toggle event sent with an AC frame.
sealed class AcToggle {
  const AcToggle();
}

/// Toggle the unit's power (protocols without a discrete power bit).
final class PowerToggle extends AcToggle {
  /// Creates the event.
  const PowerToggle();
}

/// Toggle a feature controlled by events.
final class FeatureToggle extends AcToggle {
  /// Creates the event.
  const FeatureToggle(this.feature);

  /// The feature to toggle.
  final AcFeature feature;
}

/// The Android built-in IR emitter, through a platform channel to
/// `ConsumerIrManager` (see android/.../ConsumerIrChannel.kt).
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:ir_core/ir_core.dart';

/// What the platform reports about IR hardware.
final class EmitterInfo {
  /// Creates an info record.
  const EmitterInfo({
    required this.platformSupported,
    required this.hasFeature,
    required this.hasEmitter,
    this.carrierRanges,
    this.manufacturer = '',
    this.model = '',
    this.sdkInt = 0,
  });

  /// No emitter: iOS, or anything that is not Android.
  static const EmitterInfo none = EmitterInfo(
    platformSupported: false,
    hasFeature: false,
    hasEmitter: false,
  );

  /// Whether the platform has an IR API at all (Android only).
  final bool platformSupported;

  /// `PackageManager.hasSystemFeature(FEATURE_CONSUMER_IR)`.
  final bool hasFeature;

  /// `ConsumerIrManager.hasIrEmitter()`.
  final bool hasEmitter;

  /// `getCarrierFrequencies()`, or `null` when the platform returned null
  /// (treated as unknown and logged).
  final List<CarrierRange>? carrierRanges;

  /// `Build.MANUFACTURER`, for the OEM quirk table.
  final String manufacturer;

  /// `Build.MODEL`.
  final String model;

  /// `Build.VERSION.SDK_INT`.
  final int sdkInt;

  /// Whether the phone can send IR itself. Never inferred from brand or
  /// model: both platform checks must agree.
  bool get canTransmit => platformSupported && hasFeature && hasEmitter;
}

/// Platform channel shared by detection and transmission.
const MethodChannel consumerIrChannel = MethodChannel('irremote/consumer_ir');

/// Detects the phone's emitter at runtime. Never throws.
Future<EmitterInfo> detectEmitter({
  MethodChannel channel = consumerIrChannel,
  TargetPlatform? platform,
}) async {
  final p = platform ?? defaultTargetPlatform;
  if (p != TargetPlatform.android) return EmitterInfo.none;
  try {
    final r = await channel.invokeMapMethod<String, Object?>('getCapabilities');
    if (r == null) return EmitterInfo.none;
    List<CarrierRange>? ranges;
    final raw = r['carrierRanges'];
    if (raw is List) {
      ranges = [
        for (final e in raw)
          if (e is List && e.length == 2 && e[0] is int && e[1] is int)
            CarrierRange(e[0] as int, e[1] as int),
      ];
    } else {
      debugPrint(
        'ConsumerIR: getCarrierFrequencies() returned null; '
        'treating carrier ranges as unknown',
      );
    }
    return EmitterInfo(
      platformSupported: true,
      hasFeature: r['hasFeature'] == true,
      hasEmitter: r['hasEmitter'] == true,
      carrierRanges: ranges,
      manufacturer: r['manufacturer'] is String
          ? r['manufacturer']! as String
          : '',
      model: r['model'] is String ? r['model']! as String : '',
      sdkInt: r['sdkInt'] is int ? r['sdkInt']! as int : 0,
    );
  } on PlatformException catch (e) {
    debugPrint('ConsumerIR detection failed: ${e.code} ${e.message}');
    return EmitterInfo.none;
  } on MissingPluginException {
    return EmitterInfo.none;
  }
}

/// One row of the OEM quirk table. Rows come only from recorded human test
/// results (docs/HARDWARE_TEST_PLAN.md); there are none yet.
final class OemQuirk {
  /// Creates a quirk row.
  const OemQuirk({
    required this.manufacturer,
    required this.model,
    this.maxPatternUs,
    this.carrierRanges,
    this.evidence = '',
  });

  /// Parses `assets/oem_quirks.json` rows; malformed rows are skipped.
  static List<OemQuirk> parseTable(String json) {
    final out = <OemQuirk>[];
    final Object? data;
    try {
      data = jsonDecode(json);
    } on FormatException {
      return out;
    }
    if (data is! List) return out;
    for (final row in data) {
      if (row is! Map) continue;
      final m = row['manufacturer'];
      final model = row['model'];
      if (m is! String || model is! String) continue;
      final ranges = row['carrierRanges'];
      out.add(
        OemQuirk(
          manufacturer: m,
          model: model,
          maxPatternUs: row['maxPatternUs'] is int
              ? row['maxPatternUs'] as int
              : null,
          carrierRanges: ranges is List
              ? [
                  for (final r in ranges)
                    if (r is List &&
                        r.length == 2 &&
                        r[0] is int &&
                        r[1] is int)
                      CarrierRange(r[0] as int, r[1] as int),
                ]
              : null,
          evidence: row['evidence'] is String ? row['evidence'] as String : '',
        ),
      );
    }
    return out;
  }

  /// `Build.MANUFACTURER` (case-insensitive).
  final String manufacturer;

  /// `Build.MODEL`, or `*` for every model of the manufacturer.
  final String model;

  /// Override for the maximum pattern length.
  final int? maxPatternUs;

  /// Override for carrier ranges.
  final List<CarrierRange>? carrierRanges;

  /// Reference to the test result that justified the row.
  final String evidence;

  /// Whether the row applies to [info].
  bool matches(EmitterInfo info) =>
      manufacturer.toLowerCase() == info.manufacturer.toLowerCase() &&
      (model == '*' || model.toLowerCase() == info.model.toLowerCase());
}

/// Sends through Android's `ConsumerIrManager.transmit()`.
///
/// `transmit()` is synchronous on the platform side and only accepts patterns
/// shorter than 2 s; the Kotlin side runs it on a single background executor,
/// and this class splits longer holds at frame boundaries.
final class AndroidConsumerIrTransport implements IrTransport {
  /// Creates the transport for a phone described by [info].
  AndroidConsumerIrTransport(
    this.info, {
    List<OemQuirk> quirks = const [],
    this.channel = consumerIrChannel,
    this.validator = const SignalValidator(),
  }) : caps = _capsFor(info, quirks);

  static TransportCapabilities _capsFor(
    EmitterInfo info,
    List<OemQuirk> quirks,
  ) {
    OemQuirk? q;
    for (final row in quirks) {
      if (row.matches(info)) q = row;
    }
    return TransportCapabilities(
      carrierRangesHz: q?.carrierRanges ?? info.carrierRanges,
      maxPatternUs: q?.maxPatternUs ?? 2000000,
      canLearn: false,
      latencyClass: LatencyClass.local,
    );
  }

  /// Phone description.
  final EmitterInfo info;

  /// The platform channel.
  final MethodChannel channel;

  /// Validator applied before any platform call.
  final SignalValidator validator;

  @override
  final TransportCapabilities caps;

  @override
  String get id => 'android-builtin';

  @override
  String get displayName => 'This phone';

  @override
  TransportKind get kind => TransportKind.builtIn;

  DateTime _quietUntil = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  Future<TransmitResult> transmit(IrSignal signal, {int repeats = 0}) async {
    final sw = Stopwatch()..start();
    if (!info.canTransmit) {
      return const TransmitTransportUnavailable('this phone has no IR emitter');
    }
    final issues = validator.validate(signal, caps);
    if (issues.isNotEmpty) {
      return TransmitRejected(issues.first.reason, issues.first.detail);
    }
    for (final chunk in validator.plan(signal, caps, repeats: repeats)) {
      final wait = _quietUntil.difference(DateTime.now());
      if (wait > Duration.zero) await Future<void>.delayed(wait);
      try {
        await channel.invokeMethod<Object?>('transmit', {
          'carrierHz': chunk.carrierHz,
          'pattern': Int32List.fromList(chunk.durationsUs),
        });
      } on PlatformException catch (e) {
        return switch (e.code) {
          'NO_EMITTER' => TransmitTransportUnavailable(
            e.message ?? 'no emitter',
          ),
          'PERMISSION' => TransmitTransportUnavailable(
            e.message ?? 'permission denied',
          ),
          'INVALID' => TransmitRejected(
            RejectReason.hardwareError,
            e.message ?? 'rejected',
          ),
          _ => TransmitRejected(
            RejectReason.hardwareError,
            '${e.code}: ${e.message}',
          ),
        };
      } on MissingPluginException {
        return const TransmitTransportUnavailable('IR channel not available');
      }
      _quietUntil = DateTime.now().add(
        Duration(microseconds: chunk.gapAfterUs),
      );
    }
    return TransmitSent(elapsed: sw.elapsed);
  }

  @override
  Stream<LearnedSignal>? learn() => null; // the Android IR API is transmit-only

  @override
  Future<HealthStatus> health() async => info.canTransmit
      ? Healthy(checkedAt: DateTime.now(), detail: 'built-in emitter')
      : Unreachable(checkedAt: DateTime.now(), reason: 'no IR emitter');

  @override
  Future<void> dispose() async {}
}

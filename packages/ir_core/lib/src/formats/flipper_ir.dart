/// Flipper Zero infrared files (`.ir`, format version 1).
///
/// Written from the published format description; no code copied.
///
/// Sources:
/// - Flipper Devices, "Infrared Flipper File Formats",
///   https://github.com/flipperdevices/flipperzero-firmware/blob/dev/documentation/file_formats/InfraredFileFormats.md
///   (read 2026-11-09) — header `Filetype: IR signals file` (or
///   `IR library file`, otherwise identical) and `Version: 1`; `#` comment
///   lines separating signals; per signal `name`, `type` (`parsed` or
///   `raw`); for parsed signals `protocol`, `address` and `command` as
///   4 hex bytes; for raw signals `frequency` in Hz, `duty_cycle` and
///   `data`, space-separated microsecond timings (at most 1024).
///
/// The format description does not say how each protocol packs its fields
/// into the 4 hex bytes. The mapping below was established from data, not
/// from Flipper's (GPL-3) firmware source. The bytes are little-endian, and
/// each row was cross-checked in flipperdevices/irdb at commit
/// f7b15366521cc81ba11b341538f0097bddbb748b, either by decoding that
/// database's raw captures with ir_core's own decoders and matching them by
/// brand and button name against parsed entries ("raw"), or by matching
/// parsed addresses against device/subdevice pairs recorded for the same
/// brands in probonopd/irdb at 11aa5eb3ad9fec9e5c03f170c29c1467733d9f3e,
/// which uses DecodeIR notation ("irdb"):
///
/// | Flipper   | ir_core                                         | Evidence |
/// | --------- | ----------------------------------------------- | -------- |
/// | NEC       | NEC1 D=addr, S=255-D, F=cmd (8 bit each)        | 1011 raw |
/// | NECext    | NEC1 D=addr bits 0-7, S=bits 8-15, F=cmd bits 0-7 when bits 8-15 = 255-F; otherwise NEC1-f16 with F=cmd (16 bit) | 229 irdb vs 9 byte-swapped |
/// | Samsung32 | NECx2 D=S=addr, F=cmd                           | 2017 raw |
/// | SIRC      | Sony12 D=addr (5 bit), F=cmd (7 bit)            | 816 irdb |
/// | SIRC15    | Sony15 D=addr (8 bit), F=cmd                    | 236 irdb |
/// | SIRC20    | Sony20 D=addr bits 0-4, S=bits 5-12, F=cmd      | 24 irdb vs 0 other split |
/// | RC5       | RC5 D=addr, F=cmd (0-63)                        | 4742 raw |
/// | RC5X      | RC5 D=addr, F=cmd+64 (field bit clear)          | 3 raw vs 0 |
/// | RC6       | RC6 mode 0 D=addr, F=cmd                        | 255 raw |
/// | Kaseikyo  | Panasonic, vendor 0x2002 only (see [FlipperIr.mapParsed]) | 314 raw vs 0 nibble-swapped |
///
/// The well-known codes agree: a Samsung TV's power key is stored as
/// Samsung32 07/02 (NECx2 D=7 F=2) and an LG TV's as NEC 04/08 (NEC1 D=4
/// F=8). NEC42, NEC42ext, RCA and Pioneer have no ir_core codec, Kaseikyo
/// with other vendor codes has none either, and unknown names are not
/// guessed: all of these are reported in [FlipperParseResult.skipped].
library;

import 'dart:convert';

import '../codecs/protocol.dart';
import '../codecs/registry.dart';
import '../codeset/code_set.dart';
import '../signal/ir_signal.dart';

/// Why a signal block of a Flipper file was not imported.
enum FlipperSkipReason {
  /// The protocol has no verified mapping to an ir_core codec.
  unsupportedProtocol,

  /// The `type` is neither `parsed` nor `raw`.
  unknownType,

  /// A required field is missing, duplicated or malformed.
  malformedField,

  /// A value is outside what the protocol or the format allows.
  outOfRange,
}

/// A signal block that was not imported, with the reason.
final class FlipperSkipped {
  /// Creates a skip record.
  const FlipperSkipped({
    required this.line,
    required this.name,
    required this.reason,
    required this.detail,
    this.protocol,
  });

  /// 1-based line of the block's `name` field.
  final int line;

  /// The signal name as written in the file.
  final String name;

  /// Why it was skipped.
  final FlipperSkipReason reason;

  /// The Flipper protocol name, for parsed signals that named one.
  final String? protocol;

  /// Human-readable detail.
  final String detail;

  @override
  String toString() =>
      'line $line "$name": ${reason.name}'
      '${protocol == null ? '' : ' ($protocol)'}: $detail';
}

/// One imported signal.
final class FlipperSignal {
  /// Creates an imported signal.
  const FlipperSignal({
    required this.line,
    required this.name,
    required this.code,
    required this.source,
  });

  /// 1-based line of the block's `name` field.
  final int line;

  /// The signal (button) name as written in the file, trimmed. Not
  /// normalized; callers map it with `Keys.normalize`.
  final String name;

  /// The key code: a [ProtocolKeyCode] with canonical protocol ID and
  /// normalized parameters (without the toggle bit `T`, which is session
  /// state), or a [RawKeyCode].
  final KeyCode code;

  /// `raw`, or the Flipper protocol name the code was mapped from.
  final String source;
}

/// The outcome of parsing one Flipper file.
final class FlipperParseResult {
  /// Creates a result.
  FlipperParseResult({
    required this.filetype,
    required List<FlipperSignal> signals,
    required List<FlipperSkipped> skipped,
  }) : signals = List.unmodifiable(signals),
       skipped = List.unmodifiable(skipped);

  /// The `Filetype` header value.
  final String filetype;

  /// Signals that were imported, in file order.
  final List<FlipperSignal> signals;

  /// Signal blocks that were not imported, in file order.
  final List<FlipperSkipped> skipped;
}

final class _Skip implements Exception {
  const _Skip(this.reason, this.detail);
  final FlipperSkipReason reason;
  final String detail;
}

typedef _Field = ({String key, String value, int line});

/// Parsing of Flipper `.ir` files and the protocol mapping.
abstract final class FlipperIr {
  /// Largest input accepted, in characters (5 MiB, the import limit).
  static const int maxInputLength = 5 * 1024 * 1024;

  /// Most signal blocks accepted in one file.
  static const int maxSignals = 10000;

  /// Most timings in one raw signal, per the format description.
  static const int maxRawTimings = 1024;

  /// Longest line accepted, in characters.
  static const int maxLineLength = 16 * 1024;

  /// Accepted `Filetype` values.
  static const Set<String> fileTypes = {'IR signals file', 'IR library file'};

  /// Lowest and highest raw carrier accepted, in Hz.
  static const int minFrequencyHz = 1000;

  /// See [minFrequencyHz].
  static const int maxFrequencyHz = 1000000;

  /// Largest raw timing accepted, in microseconds (a uint32 in the format).
  static const int maxTimingUs = 0xFFFFFFFF;

  /// Flipper protocol names with a verified mapping.
  static const Set<String> supportedProtocols = {
    'NEC',
    'NECext',
    'Samsung32',
    'SIRC',
    'SIRC15',
    'SIRC20',
    'RC5',
    'RC5X',
    'RC6',
    'Kaseikyo',
  };

  static final RegExp _key = RegExp(r'^[A-Za-z_]+$');
  static final RegExp _hexByte = RegExp(r'^[0-9A-Fa-f]{2}$');
  static final RegExp _digits = RegExp(r'^[0-9]{1,10}$');
  static final RegExp _decimal = RegExp(r'^[0-9]{1,3}(\.[0-9]{1,9})?$');
  static final RegExp _control = RegExp(r'[\x00-\x1F\x7F]');
  static final RegExp _ws = RegExp(r'[ \t]+');

  /// Parses a Flipper `.ir` file.
  ///
  /// Throws [FormatException] (and nothing else) when the file as a whole is
  /// unusable: too large, a missing or unsupported header, a line that is
  /// not `key: value`, a field before the first `name`, or more than
  /// [maxSignals] signal blocks. Problems confined to one signal block skip
  /// that block and are reported in [FlipperParseResult.skipped]. Fields
  /// the format does not define are ignored.
  static FlipperParseResult parse(String text) {
    if (text.length > maxInputLength) {
      throw const FormatException('Flipper file is larger than 5 MiB');
    }
    final fields = <_Field>[];
    var lineNo = 0;
    for (final raw in const LineSplitter().convert(text)) {
      lineNo++;
      if (raw.length > maxLineLength) {
        throw FormatException('line $lineNo is too long');
      }
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final colon = line.indexOf(':');
      if (colon <= 0) {
        throw FormatException('line $lineNo: expected "key: value"');
      }
      final key = line.substring(0, colon).trim();
      if (!_key.hasMatch(key)) {
        throw FormatException('line $lineNo: invalid field name');
      }
      fields.add((
        key: key,
        value: line.substring(colon + 1).trim(),
        line: lineNo,
      ));
    }
    if (fields.length < 2 ||
        fields[0].key != 'Filetype' ||
        fields[1].key != 'Version') {
      throw const FormatException(
        'missing "Filetype" and "Version" header lines',
      );
    }
    final filetype = fields[0].value;
    if (!fileTypes.contains(filetype)) {
      throw FormatException('unsupported Filetype "$filetype"');
    }
    if (fields[1].value != '1') {
      throw FormatException('unsupported Version "${fields[1].value}"');
    }

    final blocks = <List<_Field>>[];
    for (var i = 2; i < fields.length; i++) {
      final f = fields[i];
      if (f.key == 'name') {
        if (blocks.length >= maxSignals) {
          throw const FormatException('more than 10000 signals in one file');
        }
        blocks.add([f]);
      } else if (blocks.isEmpty) {
        throw FormatException('line ${f.line}: field before the first name');
      } else {
        blocks.last.add(f);
      }
    }

    final signals = <FlipperSignal>[];
    final skipped = <FlipperSkipped>[];
    for (final block in blocks) {
      final head = block.first;
      final name = head.value;
      String? protocol;
      try {
        if (name.isEmpty || _control.hasMatch(name)) {
          throw const _Skip(FlipperSkipReason.malformedField, 'invalid name');
        }
        final byKey = <String, String>{};
        for (final f in block.skip(1)) {
          if (byKey.containsKey(f.key)) {
            throw _Skip(
              FlipperSkipReason.malformedField,
              'duplicate field "${f.key}"',
            );
          }
          byKey[f.key] = f.value;
        }
        String req(String k) =>
            byKey[k] ??
            (throw _Skip(
              FlipperSkipReason.malformedField,
              'missing field "$k"',
            ));
        final type = req('type');
        final KeyCode code;
        switch (type) {
          case 'parsed':
            protocol = req('protocol');
            code = _mapOrSkip(
              protocol,
              _hexBytes(req('address'), 'address'),
              _hexBytes(req('command'), 'command'),
            );
          case 'raw':
            code = _raw(req('frequency'), byKey['duty_cycle'], req('data'));
          default:
            throw _Skip(FlipperSkipReason.unknownType, 'type "$type"');
        }
        signals.add(
          FlipperSignal(
            line: head.line,
            name: name,
            code: code,
            source: type == 'raw' ? 'raw' : protocol!,
          ),
        );
      } on _Skip catch (e) {
        skipped.add(
          FlipperSkipped(
            line: head.line,
            name: name,
            reason: e.reason,
            protocol: protocol,
            detail: e.detail,
          ),
        );
      }
    }
    return FlipperParseResult(
      filetype: filetype,
      signals: signals,
      skipped: skipped,
    );
  }

  /// Maps one parsed Flipper signal, given its little-endian [address] and
  /// [command] values, to an ir_core protocol key code.
  ///
  /// Returns `null` when [protocol] has no verified mapping (see the table
  /// at the top of this file) and throws [FormatException] when a value is
  /// out of range for the protocol. Kaseikyo is mapped only for the
  /// Panasonic vendor code 0x2002 (address bytes 1-2 are `02 20`): address
  /// byte 0 bits 4-7 become Panasonic D bits 4-7 (D bits 0-3 are the vendor
  /// parity, 0 for this vendor), byte 0 bits 0-3 become S bits 0-3, byte 3
  /// bits 0-1 become F bits 6-7; the 10-bit command's bits 0-3 become S
  /// bits 4-7 and bits 4-9 become F bits 0-5.
  static ProtocolKeyCode? mapParsed(String protocol, int address, int command) {
    try {
      return _mapOrSkip(protocol, address, command);
    } on _Skip catch (e) {
      if (e.reason == FlipperSkipReason.unsupportedProtocol) return null;
      throw FormatException(e.detail);
    }
  }

  static ProtocolKeyCode _mapOrSkip(String protocol, int a, int c) {
    void fit(int value, int bits, String what) {
      if (value < 0 || value >= (1 << bits)) {
        throw _Skip(
          FlipperSkipReason.outOfRange,
          '$what 0x${value.toRadixString(16)} does not fit $bits bits '
          'for $protocol',
        );
      }
    }

    final String id;
    final Map<String, int> params;
    switch (protocol) {
      case 'NEC':
        fit(a, 8, 'address');
        fit(c, 8, 'command');
        id = 'NEC1';
        params = {'D': a, 'F': c};
      case 'NECext':
        fit(a, 16, 'address');
        fit(c, 16, 'command');
        final lo = c & 0xFF;
        final hi = c >> 8;
        if (hi == 255 - lo) {
          id = 'NEC1';
          params = {'D': a & 0xFF, 'S': a >> 8, 'F': lo};
        } else {
          id = 'NEC1-f16';
          params = {'D': a & 0xFF, 'S': a >> 8, 'F': c};
        }
      case 'Samsung32':
        fit(a, 8, 'address');
        fit(c, 8, 'command');
        id = 'NECx2';
        params = {'D': a, 'S': a, 'F': c};
      case 'SIRC':
        fit(a, 5, 'address');
        fit(c, 7, 'command');
        id = 'Sony12';
        params = {'D': a, 'F': c};
      case 'SIRC15':
        fit(a, 8, 'address');
        fit(c, 7, 'command');
        id = 'Sony15';
        params = {'D': a, 'F': c};
      case 'SIRC20':
        fit(a, 13, 'address');
        fit(c, 7, 'command');
        id = 'Sony20';
        params = {'D': a & 0x1F, 'S': a >> 5, 'F': c};
      case 'RC5':
        fit(a, 5, 'address');
        fit(c, 6, 'command');
        id = 'RC5';
        params = {'D': a, 'F': c};
      case 'RC5X':
        fit(a, 5, 'address');
        fit(c, 6, 'command');
        id = 'RC5';
        params = {'D': a, 'F': c | 0x40};
      case 'RC6':
        fit(a, 8, 'address');
        fit(c, 8, 'command');
        id = 'RC6';
        params = {'D': a, 'F': c};
      case 'Kaseikyo':
        final vendor = (a >> 8) & 0xFFFF;
        if (vendor != 0x2002) {
          throw _Skip(
            FlipperSkipReason.unsupportedProtocol,
            'Kaseikyo vendor 0x${vendor.toRadixString(16).padLeft(4, '0')} '
            'is not Panasonic (0x2002)',
          );
        }
        fit(a >> 24, 2, 'address byte 3');
        fit(c, 10, 'command');
        final b0 = a & 0xFF;
        id = 'Panasonic';
        params = {
          'D': b0 & 0xF0,
          'S': (b0 & 0x0F) | ((c & 0x0F) << 4),
          'F': ((c >> 4) & 0x3F) | ((a >> 24) << 6),
        };
      default:
        throw _Skip(
          FlipperSkipReason.unsupportedProtocol,
          'no verified mapping for protocol "$protocol"',
        );
    }
    return ProtocolKeyCode(id, _normalize(id, params));
  }

  /// Fills defaults through the codec, drops the session toggle bit and
  /// orders the parameters as the codec declares them.
  static Map<String, int> _normalize(String id, Map<String, int> params) {
    final codec = ProtocolRegistry.standard.require(id);
    try {
      final n = codec.normalize(params);
      return Map.unmodifiable({
        for (final p in codec.params)
          if (p.name != 'T') p.name: n[p.name]!,
      });
    } on ProtocolParamException catch (e) {
      throw _Skip(FlipperSkipReason.outOfRange, e.message);
    }
  }

  static int _hexBytes(String value, String field) {
    final parts = value.split(_ws);
    if (parts.length != 4 || !parts.every(_hexByte.hasMatch)) {
      throw _Skip(
        FlipperSkipReason.malformedField,
        '$field must be 4 hex bytes',
      );
    }
    var v = 0;
    for (var i = 3; i >= 0; i--) {
      v = (v << 8) | int.parse(parts[i], radix: 16);
    }
    return v;
  }

  static RawKeyCode _raw(String frequency, String? dutyCycle, String data) {
    if (!_digits.hasMatch(frequency)) {
      throw const _Skip(
        FlipperSkipReason.malformedField,
        'frequency must be an integer',
      );
    }
    final hz = int.parse(frequency);
    if (hz < minFrequencyHz || hz > maxFrequencyHz) {
      throw _Skip(FlipperSkipReason.outOfRange, 'frequency $hz Hz');
    }
    if (dutyCycle != null) {
      // Validated for well-formedness only: IrSignal has no duty cycle and
      // transports use their own.
      final d = _decimal.hasMatch(dutyCycle) ? double.parse(dutyCycle) : -1.0;
      if (d <= 0 || d > 1) {
        throw const _Skip(
          FlipperSkipReason.malformedField,
          'duty_cycle must be a number in (0, 1]',
        );
      }
    }
    final tokens = data.isEmpty ? const <String>[] : data.split(_ws);
    if (tokens.isEmpty) {
      throw const _Skip(FlipperSkipReason.malformedField, 'data is empty');
    }
    if (tokens.length > maxRawTimings) {
      throw _Skip(
        FlipperSkipReason.outOfRange,
        'data has ${tokens.length} timings; the format allows $maxRawTimings',
      );
    }
    final durations = <int>[];
    for (final t in tokens) {
      if (!_digits.hasMatch(t)) {
        throw const _Skip(
          FlipperSkipReason.malformedField,
          'data must be unsigned integers',
        );
      }
      final v = int.parse(t);
      if (v == 0 || v > maxTimingUs) {
        throw _Skip(FlipperSkipReason.outOfRange, 'timing $v us');
      }
      durations.add(v);
    }
    // An even count ends with a space: silence after the last mark. It is
    // dropped rather than turned into a repeat gap, because captures often
    // end in a short space that would make held repeats run together.
    if (durations.length.isEven) durations.removeLast();
    if (durations.isEmpty) {
      throw const _Skip(FlipperSkipReason.malformedField, 'data has no mark');
    }
    return RawKeyCode(IrSignal(carrierHz: hz, durationsUs: durations));
  }
}

/// probonopd/irdb CSV files (`functionname,protocol,device,subdevice,function`).
///
/// Written from published format and protocol descriptions; no code copied.
///
/// Sources:
/// - probonopd/irdb README, https://github.com/probonopd/irdb (read
///   2026-11-09, commit 11aa5eb3ad9fec9e5c03f170c29c1467733d9f3e) — files
///   named `<manufacturer>/<devicetype>/<device>,<subdevice>.csv`, one row per
///   key in protocol/device/subdevice/function notation, rendered with
///   IrScrutinizer or MakeHex; a subdevice of -1 means the protocol default.
/// - IrpTransmogrifier protocol database, IrpProtocols.xml,
///   https://github.com/bengtmartensson/IrpTransmogrifier/blob/master/src/main/resources/IrpProtocols.xml
///   (read 2026-11-09; data only) — the meaning of the protocol names irdb
///   uses. For every name mapped below, the IRP there has the same bit
///   layout and parameter widths as the ir_core codec of the same name
///   (cited in each codec's header). "NEC" is IrpProtocols' decode-only name
///   for an NEC1 frame learned without its repeat part; its frame is
///   identical to NEC1's, so it maps to NEC1 (NEC1's ditto repeat is then
///   used when a key is held).
///
/// Not mapped, and reported as skipped:
/// - every protocol without an ir_core codec (Pioneer, Mitsubishi, Aiwa, MCE,
///   RC5x, RC6-6-20, RCA, XMP, variants such as `JVC{2}` and so on);
/// - `NEC1-f16` and `NEC2-f16`: IrpProtocols gives them two 8-bit function
///   fields (F, E) while DecodeIR and the ir_core codec use one 16-bit F,
///   and irdb rows carry a single function value, so the meaning is
///   ambiguous.
///
/// A subdevice of -1 takes the codec's default. For every mapped protocol
/// with a defaulted S that default is IrpProtocols' own: 255-D for NEC1,
/// NEC2, NECx1 and NECx2 (nec.dart, DECISIONS.md ADR-021).
library;

import 'dart:convert';

import '../codecs/protocol.dart';
import '../codecs/registry.dart';
import '../codeset/code_set.dart';

/// Why an irdb row was not imported.
enum IrdbSkipReason {
  /// The protocol has no verified mapping to an ir_core codec.
  unsupportedProtocol,

  /// The protocol default for an omitted subdevice is ambiguous. No mapped
  /// protocol produces this today (see the library comment); the value is
  /// kept so that callers matching on reasons keep compiling.
  ambiguousDefault,

  /// The row does not have five fields or a number is malformed.
  malformedRow,

  /// A value is out of range for the protocol.
  outOfRange,
}

/// A row that was not imported, with the reason.
final class IrdbSkipped {
  /// Creates a skip record.
  const IrdbSkipped({
    required this.line,
    required this.reason,
    required this.detail,
    this.functionName,
    this.protocol,
  });

  /// 1-based line number.
  final int line;

  /// Why it was skipped.
  final IrdbSkipReason reason;

  /// The function (key) name, when the row had one.
  final String? functionName;

  /// The irdb protocol name, when the row had one.
  final String? protocol;

  /// Human-readable detail.
  final String detail;

  @override
  String toString() =>
      'line $line: ${reason.name}'
      '${protocol == null ? '' : ' ($protocol)'}: $detail';
}

/// One imported row.
final class IrdbSignal {
  /// Creates an imported row.
  const IrdbSignal({
    required this.line,
    required this.functionName,
    required this.code,
    required this.sourceProtocol,
  });

  /// 1-based line number.
  final int line;

  /// The function (key) name as written, unquoted. Not normalized.
  final String functionName;

  /// Canonical protocol ID with normalized parameters in codec order (no
  /// toggle bit `T`).
  final ProtocolKeyCode code;

  /// The protocol name as written in the file.
  final String sourceProtocol;
}

/// The outcome of parsing one irdb CSV file.
final class IrdbParseResult {
  /// Creates a result.
  IrdbParseResult({
    required List<IrdbSignal> signals,
    required List<IrdbSkipped> skipped,
  }) : signals = List.unmodifiable(signals),
       skipped = List.unmodifiable(skipped);

  /// Rows that were imported, in file order.
  final List<IrdbSignal> signals;

  /// Rows that were not imported, in file order.
  final List<IrdbSkipped> skipped;
}

final class _Skip implements Exception {
  const _Skip(this.reason, this.detail);
  final IrdbSkipReason reason;
  final String detail;
}

/// Parsing of irdb CSV files and the protocol-name mapping.
abstract final class IrdbCsv {
  /// Largest input accepted, in characters (5 MiB, the import limit).
  static const int maxInputLength = 5 * 1024 * 1024;

  /// Most rows accepted in one file.
  static const int maxSignals = 10000;

  /// Longest line accepted, in characters.
  static const int maxLineLength = 4096;

  /// The header irdb files start with.
  static const String header =
      'functionname,protocol,device,subdevice,function';

  /// irdb protocol name (lower case) to ir_core protocol ID. Only names whose
  /// IRP was checked against the ir_core codec are listed.
  static const Map<String, String> protocolIds = {
    'nec': 'NEC1',
    'nec1': 'NEC1',
    'nec2': 'NEC2',
    'necx1': 'NECx1',
    'necx2': 'NECx2',
    'sony12': 'Sony12',
    'sony15': 'Sony15',
    'sony20': 'Sony20',
    'rc5': 'RC5',
    'rc6': 'RC6',
    'panasonic': 'Panasonic',
    'jvc': 'JVC',
    'sharp': 'Sharp',
    'denon': 'Denon',
  };

  static final RegExp _int = RegExp(r'^-?[0-9]{1,6}$');

  /// Parses one irdb CSV file.
  ///
  /// The header line is optional. Throws [FormatException] (and nothing
  /// else) when the input is too large or has more than [maxSignals] rows
  /// or a line longer than [maxLineLength]; rows that cannot be imported are
  /// reported in [IrdbParseResult.skipped].
  static IrdbParseResult parse(String text) {
    if (text.length > maxInputLength) {
      throw const FormatException('irdb file is larger than 5 MiB');
    }
    final signals = <IrdbSignal>[];
    final skipped = <IrdbSkipped>[];
    var lineNo = 0;
    var rows = 0;
    for (final raw in const LineSplitter().convert(text)) {
      lineNo++;
      if (raw.length > maxLineLength) {
        throw FormatException('line $lineNo is too long');
      }
      final line = raw.trim();
      if (line.isEmpty) continue;
      if (lineNo == 1 && _isHeader(line)) continue;
      if (++rows > maxSignals) {
        throw const FormatException('more than 10000 rows in one file');
      }
      String? name;
      String? protocol;
      try {
        // The function name may itself contain commas (irdb quotes such
        // names); the four trailing fields never do, so split from the right.
        final fields = <String>[];
        var end = line.length;
        for (var i = 0; i < 4; i++) {
          final comma = line.lastIndexOf(',', end - 1);
          if (comma < 0) {
            throw const _Skip(
              IrdbSkipReason.malformedRow,
              'expected 5 comma-separated fields',
            );
          }
          fields.insert(0, line.substring(comma + 1, end).trim());
          end = comma;
          if (end == 0) break;
        }
        if (fields.length != 4) {
          throw const _Skip(
            IrdbSkipReason.malformedRow,
            'expected 5 comma-separated fields',
          );
        }
        if (end == 0) {
          throw const _Skip(IrdbSkipReason.malformedRow, 'empty function name');
        }
        name = _unquote(line.substring(0, end).trim());
        protocol = fields[0];
        if (name.isEmpty) {
          throw const _Skip(IrdbSkipReason.malformedRow, 'empty function name');
        }
        final code = _map(protocol, fields[1], fields[2], fields[3]);
        signals.add(
          IrdbSignal(
            line: lineNo,
            functionName: name,
            code: code,
            sourceProtocol: protocol,
          ),
        );
      } on _Skip catch (e) {
        skipped.add(
          IrdbSkipped(
            line: lineNo,
            reason: e.reason,
            functionName: name,
            protocol: protocol,
            detail: e.detail,
          ),
        );
      }
    }
    return IrdbParseResult(signals: signals, skipped: skipped);
  }

  static bool _isHeader(String line) {
    final l = line.toLowerCase().replaceAll('\t', ',');
    return l.endsWith('protocol,device,subdevice,function');
  }

  static String _unquote(String s) {
    if (s.length >= 2 && s.startsWith('"') && s.endsWith('"')) {
      return s.substring(1, s.length - 1).replaceAll('""', '"').trim();
    }
    return s;
  }

  /// Maps one row's protocol name and device, subdevice and function fields
  /// (as text) to a protocol key code, or throws [_Skip].
  static ProtocolKeyCode _map(
    String protocol,
    String device,
    String subdevice,
    String function,
  ) {
    final id = protocolIds[protocol.toLowerCase()];
    if (id == null) {
      throw _Skip(
        IrdbSkipReason.unsupportedProtocol,
        'no verified mapping for protocol "$protocol"',
      );
    }
    int num(String v, String what) {
      if (!_int.hasMatch(v)) {
        throw _Skip(IrdbSkipReason.malformedRow, '$what "$v" is not a number');
      }
      return int.parse(v);
    }

    final d = num(device, 'device');
    final s = num(subdevice, 'subdevice');
    final f = num(function, 'function');
    final codec = ProtocolRegistry.standard.require(id);
    final hasS = codec.params.any((p) => p.name == 'S');
    final sDefault = codec.params.any((p) => p.name == 'S' && p.hasDefault);
    final params = <String, int>{'D': d, 'F': f};
    if (s == -1) {
      if (hasS && !sDefault) {
        throw _Skip(
          IrdbSkipReason.malformedRow,
          '$id needs a subdevice; the row has -1',
        );
      }
    } else if (!hasS) {
      throw _Skip(
        IrdbSkipReason.outOfRange,
        '$id has no subdevice; the row has $s',
      );
    } else {
      params['S'] = s;
    }
    try {
      final n = codec.normalize(params);
      return ProtocolKeyCode(
        id,
        Map.unmodifiable({
          for (final p in codec.params)
            if (p.name != 'T') p.name: n[p.name]!,
        }),
      );
    } on ProtocolParamException catch (e) {
      throw _Skip(IrdbSkipReason.outOfRange, e.message);
    }
  }
}

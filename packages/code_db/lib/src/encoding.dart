/// Compact column encodings shared by the writer and the reader.
library;

import 'dart:typed_data';

import 'package:ir_core/ir_core.dart';

import 'errors.dart';

/// Encodes non-negative integers as unsigned LEB128 varints.
Uint8List encodeVarints(List<int> values) {
  final out = BytesBuilder(copy: false);
  final buf = <int>[];
  for (final v in values) {
    if (v < 0) throw ArgumentError.value(v, 'values', 'must be >= 0');
    var x = v;
    buf.clear();
    while (x >= 0x80) {
      buf.add((x & 0x7F) | 0x80);
      x >>= 7;
    }
    buf.add(x);
    out.add(buf);
  }
  return out.takeBytes();
}

/// Decodes [encodeVarints] output; throws [CodeDbFormatException] when the
/// bytes are truncated or a value exceeds 32 bits.
List<int> decodeVarints(Uint8List bytes) {
  final out = <int>[];
  var i = 0;
  while (i < bytes.length) {
    var v = 0;
    var shift = 0;
    while (true) {
      if (i >= bytes.length || shift > 28) {
        throw const CodeDbFormatException('malformed duration blob');
      }
      final b = bytes[i++];
      v |= (b & 0x7F) << shift;
      if (b < 0x80) break;
      shift += 7;
    }
    out.add(v);
  }
  return out;
}

final RegExp _paramName = RegExp(r'^[A-Za-z][A-Za-z0-9_]*$');

/// Encodes protocol parameters as `D=4,S=251,F=8`, in map order.
String encodeParams(Map<String, int> params) {
  final parts = <String>[];
  params.forEach((k, v) {
    if (!_paramName.hasMatch(k)) {
      throw ArgumentError.value(k, 'params', 'invalid parameter name');
    }
    parts.add('$k=$v');
  });
  return parts.join(',');
}

/// Decodes [encodeParams] output; throws [CodeDbFormatException].
Map<String, int> decodeParams(String text) {
  final out = <String, int>{};
  if (text.isEmpty) return out;
  for (final part in text.split(',')) {
    final eq = part.indexOf('=');
    final v = eq > 0 ? int.tryParse(part.substring(eq + 1)) : null;
    if (v == null || !_paramName.hasMatch(part.substring(0, eq))) {
      throw CodeDbFormatException('malformed params "$text"');
    }
    out[part.substring(0, eq)] = v;
  }
  return out;
}

final List<String> _vocabulary = Keys.all.toList(growable: false);
final Map<String, int> _vocabularyIndex = {
  for (var i = 0; i < _vocabulary.length; i++) _vocabulary[i]: i,
};

/// Canonical key order inside a code set: the fixed vocabulary in its
/// declared order, then custom keys by code unit order.
int compareKeys(String a, String b) {
  final ia = _vocabularyIndex[a];
  final ib = _vocabularyIndex[b];
  if (ia != null && ib != null) return ia.compareTo(ib);
  if (ia != null) return -1;
  if (ib != null) return 1;
  return a.compareTo(b);
}

/// Search key for brand names: lower case without spaces or punctuation, so
/// "Tata Play", "tata-play" and "TATAPLAY" all match.
String brandSearchKey(String name) =>
    name.toLowerCase().replaceAll(RegExp(r'''[\s\-_.,&/+()'"!?:;*#@]'''), '');

/// One `key_code` row's value columns.
typedef KeyCodeColumns = ({
  String? protocol,
  String? params,
  int? carrierHz,
  Uint8List? durations,
  Uint8List? repeatFrame,
  int? repeatLeadInUs,
  int? repeatGapUs,
  int? repeatMin,
});

/// Splits a key code into its columns.
KeyCodeColumns keyCodeToColumns(KeyCode code) {
  switch (code) {
    case ProtocolKeyCode(:final protocol, :final params):
      return (
        protocol: protocol,
        params: encodeParams(params),
        carrierHz: null,
        durations: null,
        repeatFrame: null,
        repeatLeadInUs: null,
        repeatGapUs: null,
        repeatMin: null,
      );
    case RawKeyCode(:final signal):
      final r = signal.repeat;
      final sameFrame = r != null && _listEquals(r.frameUs, signal.durationsUs);
      return (
        protocol: null,
        params: null,
        carrierHz: signal.carrierHz,
        durations: encodeVarints(signal.durationsUs),
        repeatFrame: r == null || sameFrame ? null : encodeVarints(r.frameUs),
        repeatLeadInUs: r?.leadInGapUs,
        repeatGapUs: r?.gapUs,
        repeatMin: r?.minRepeats,
      );
  }
}

/// Rebuilds a key code from its columns; throws [CodeDbFormatException].
KeyCode keyCodeFromColumns(KeyCodeColumns c) {
  final protocol = c.protocol;
  if (protocol != null) {
    final params = c.params;
    if (params == null) throw const CodeDbFormatException('params missing');
    return ProtocolKeyCode(protocol, Map.unmodifiable(decodeParams(params)));
  }
  final carrier = c.carrierHz;
  final blob = c.durations;
  if (carrier == null || blob == null) {
    throw const CodeDbFormatException('raw key without carrier or durations');
  }
  final durations = decodeVarints(blob);
  RepeatSpec? repeat;
  if (c.repeatLeadInUs != null || c.repeatGapUs != null) {
    final leadIn = c.repeatLeadInUs;
    final gap = c.repeatGapUs;
    if (leadIn == null || gap == null || leadIn <= 0 || gap <= 0) {
      throw const CodeDbFormatException('incomplete repeat columns');
    }
    final frame = c.repeatFrame;
    repeat = RepeatSpec(
      frameUs: frame == null ? durations : decodeVarints(frame),
      leadInGapUs: leadIn,
      gapUs: gap,
      minRepeats: c.repeatMin ?? 0,
    );
  }
  return RawKeyCode(
    IrSignal(carrierHz: carrier, durationsUs: durations, repeat: repeat),
  );
}

bool _listEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

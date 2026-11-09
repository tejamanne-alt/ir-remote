/// The content hash: SHA-256 over a canonical serialization of every row.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:sqlite3/sqlite3.dart';

import 'errors.dart';
import 'schema.dart';

/// Computes the content hash of an open code database.
///
/// Tables are visited in [codeDbTables] order and rows in each table's
/// primary-key order. Each row is the table name and then its columns in
/// [TableSpec.columns] order, separated by 0x1F and ended by 0x0A. A value
/// is `~` for NULL, `i<decimal>` for an integer, `s<n>:<utf8>` for text and
/// `b<n>:<bytes>` for a blob, where `<n>` is the byte length. The
/// `content_hash` meta row itself is excluded. The result is lower-case hex.
///
/// Because the hash covers rows rather than file bytes, it is independent of
/// page layout and of the SQLite version that wrote the file.
String computeContentHash(Database db) {
  final out = _DigestSink();
  final input = sha256.startChunkedConversion(out);
  final w = _Buffer();
  for (final t in codeDbTables) {
    final where = t.name == 'meta' ? "WHERE key <> '$metaContentHash' " : '';
    final stmt = db.prepare(
      'SELECT ${t.columns.join(', ')} FROM ${t.name} $where'
      'ORDER BY ${t.orderBy}',
    );
    try {
      final cursor = stmt.selectCursor();
      while (cursor.moveNext()) {
        w.ascii(t.name);
        for (final v in cursor.current.values) {
          w.byte(0x1F);
          switch (v) {
            case null:
              w.byte(0x7E);
            case int():
              w
                ..byte(0x69) // i
                ..ascii('$v');
            case String():
              w.text(v);
            case Uint8List():
              w
                ..byte(0x62) // b
                ..ascii('${v.length}')
                ..byte(0x3A)
                ..bytes(v);
            default:
              throw CodeDbFormatException('unexpected value type in ${t.name}');
          }
        }
        w.byte(0x0A);
        if (w.length >= 1 << 16) input.add(w.take());
      }
    } finally {
      stmt.close();
    }
  }
  input
    ..add(w.take())
    ..close();
  return out.value.toString();
}

/// A growable byte buffer that avoids per-value allocations.
final class _Buffer {
  Uint8List _b = Uint8List(1 << 17);
  int length = 0;

  void _ensure(int n) {
    if (length + n <= _b.length) return;
    var size = _b.length * 2;
    while (size < length + n) {
      size *= 2;
    }
    _b = Uint8List(size)..setRange(0, length, _b);
  }

  void byte(int v) {
    _ensure(1);
    _b[length++] = v;
  }

  void bytes(List<int> v) {
    _ensure(v.length);
    _b.setRange(length, length + v.length, v);
    length += v.length;
  }

  /// Appends [s], which must be ASCII.
  void ascii(String s) {
    _ensure(s.length);
    for (var i = 0; i < s.length; i++) {
      _b[length++] = s.codeUnitAt(i);
    }
  }

  /// Appends `s<n>:<utf8>`.
  void text(String s) {
    var asciiOnly = true;
    for (var i = 0; i < s.length; i++) {
      if (s.codeUnitAt(i) > 0x7F) {
        asciiOnly = false;
        break;
      }
    }
    byte(0x73); // s
    if (asciiOnly) {
      ascii('${s.length}');
      byte(0x3A);
      ascii(s);
    } else {
      final u = utf8.encode(s);
      ascii('${u.length}');
      byte(0x3A);
      bytes(u);
    }
  }

  Uint8List take() {
    final out = Uint8List.sublistView(_b, 0, length);
    _b = Uint8List(_b.length);
    length = 0;
    return out;
  }
}

final class _DigestSink implements Sink<Digest> {
  late Digest value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}

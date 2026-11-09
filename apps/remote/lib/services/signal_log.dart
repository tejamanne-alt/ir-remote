/// The debug Signal Inspector's ring buffer.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:ir_transports/ir_transports.dart';

/// Keeps the last [capacity] transmissions for the inspector.
final class SignalLog extends ChangeNotifier {
  /// Creates a log.
  SignalLog({this.capacity = 20});

  /// How many records are kept.
  final int capacity;

  final List<TransmitRecord> _records = [];

  /// Records, newest first.
  List<TransmitRecord> get records => List.unmodifiable(_records.reversed);

  /// Adds a record, dropping the oldest beyond [capacity].
  void add(TransmitRecord r) {
    _records.add(r);
    if (_records.length > capacity) _records.removeAt(0);
    notifyListeners();
  }

  /// JSON export of every record, newest first.
  String exportJson() =>
      const JsonEncoder.withIndent('  ')
          .convert([for (final r in records) r.toJson()]);
}

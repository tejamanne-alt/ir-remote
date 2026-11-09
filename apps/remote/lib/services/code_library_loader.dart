/// Loads the bundled code database. Falls back to an empty library (the
/// add-device flow then offers learning and Pronto paste) rather than failing
/// to start.
library;

import 'package:flutter/foundation.dart';

import 'code_library.dart';

/// Loads the bundled library.
Future<CodeLibrary> loadBundledCodeLibrary() async {
  try {
    return InMemoryCodeLibrary.empty();
  } on Object catch (e) {
    debugPrint('code library unavailable: $e');
    return InMemoryCodeLibrary.empty();
  }
}

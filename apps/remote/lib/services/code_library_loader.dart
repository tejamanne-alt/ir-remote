/// Loads the bundled code database (packages/code_db/assets).
///
/// The asset is copied once into app support storage (SQLite needs a file),
/// fully hash-verified on that first open, and opened with the cheap
/// stored-hash check afterwards. Any failure falls back to an empty library:
/// the app still starts, and the add-device flow offers learning, Flipper
/// import and Pronto paste.
library;

import 'dart:io';

import 'package:code_db/code_db.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:ir_core/ir_core.dart';
import 'package:path_provider/path_provider.dart';

import 'code_library.dart';

const _assetDir = 'packages/code_db/assets';

/// Adapts [CodeDb] to the app's [CodeLibrary].
final class CodeDbLibrary implements CodeLibrary {
  /// Wraps an open database.
  CodeDbLibrary(this.db) : notices = _notices(db);

  /// The open database.
  final CodeDb db;

  @override
  final List<DataSourceNotice> notices;

  static List<DataSourceNotice> _notices(CodeDb db) => [
    for (final s in db.sources())
      DataSourceNotice(
        source:
            '${s.name} @${s.commit.substring(0, s.commit.length < 7 ? s.commit.length : 7)}',
        url: s.url,
        license: s.license,
        notice: s.notice,
      ),
  ];

  @override
  List<BrandEntry> brands(DeviceCategory category, {String query = ''}) => [
    for (final b in db.brands(category, search: query))
      BrandEntry(b.name, b.codeSetCount, primaryMarket: b.primaryMarket),
  ];

  @override
  List<CodeSet> codeSets(
    DeviceCategory category, {
    String? brand,
    int limit = 40,
  }) {
    if (brand != null) return db.codeSets(brand, category).take(limit).toList();
    // "Not listed": the best-ranked set of each brand, in brand order, so
    // the most common codes of the category come first.
    final out = <CodeSet>[];
    for (final b in db.brands(category)) {
      final sets = db.codeSets(b.name, category);
      if (sets.isNotEmpty) out.add(sets.first);
      if (out.length >= limit) break;
    }
    return out;
  }

  @override
  CodeSet? byId(String id) => db.codeSetById(id);
}

/// Loads the bundled library, or an empty one if anything goes wrong.
Future<CodeLibrary> loadBundledCodeLibrary({AssetBundle? bundle}) async {
  final assets = bundle ?? rootBundle;
  File? file;
  try {
    final manifest = CodeDbManifest.parse(
      await assets.loadString('$_assetDir/codes.manifest.json'),
    );
    final dir = await getApplicationSupportDirectory();
    file = File(
      '${dir.path}/codes-${manifest.fileSha256.substring(0, 16)}.sqlite',
    );
    var verification = CodeDbVerification.storedHashOnly;
    if (!file.existsSync()) {
      final data = await assets.load('$_assetDir/${manifest.file}');
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
      await tmp.rename(file.path);
      verification = CodeDbVerification.full;
      _deleteStaleCopies(dir, keep: file.path);
    }
    final db = CodeDb.open(
      file.path,
      expectedContentHash: manifest.contentSha256,
      verification: verification,
    );
    return CodeDbLibrary(db);
  } on Object catch (e) {
    debugPrint('code database unavailable: $e');
    // A corrupt copy is removed so the next launch copies it again.
    try {
      if (file != null && file.existsSync()) file.deleteSync();
    } on Object {
      // ignore
    }
    return InMemoryCodeLibrary.empty();
  }
}

void _deleteStaleCopies(Directory dir, {required String keep}) {
  try {
    for (final f in dir.listSync().whereType<File>()) {
      final name = f.uri.pathSegments.last;
      if (name.startsWith('codes-') &&
          name.endsWith('.sqlite') &&
          f.path != keep) {
        f.deleteSync();
      }
    }
  } on FileSystemException {
    // best effort
  }
}

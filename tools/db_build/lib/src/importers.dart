/// Importers that turn a checked-out source tree into candidate code sets.
library;

import 'dart:convert';
import 'dart:io';

import 'package:ir_core/ir_core.dart';
import 'package:path/path.dart' as p;

import 'candidate.dart';
import 'report.dart';
import 'sources.dart';

/// Largest source file read (the import limit, 5 MiB).
const int maxSourceFileBytes = 5 * 1024 * 1024;

/// Largest Flipper `config.json` read.
const int _maxConfigBytes = 1024 * 1024;

int _byName(FileSystemEntity a, FileSystemEntity b) =>
    p.basename(a.path).compareTo(p.basename(b.path));

List<Directory> _dirs(Directory d) =>
    d.listSync(followLinks: false).whereType<Directory>().where((e) {
      return !p.basename(e.path).startsWith('.');
    }).toList()..sort(_byName);

List<File> _files(Directory d, String ext) =>
    d
        .listSync(followLinks: false)
        .whereType<File>()
        .where((f) => f.path.endsWith(ext))
        .toList()
      ..sort(_byName);

int _countFiles(Directory d, String ext) => d
    .listSync(recursive: true, followLinks: false)
    .whereType<File>()
    .where((f) => f.path.endsWith(ext))
    .length;

String? _readText(File f, SourceStats stats) {
  final len = f.lengthSync();
  if (len > maxSourceFileBytes) {
    stats.filesExcluded.add('fileTooLarge');
    return null;
  }
  try {
    return utf8.decode(f.readAsBytesSync());
  } on FormatException {
    stats.filesExcluded.add('notUtf8');
    return null;
  }
}

Provenance _provenance(ResolvedSource src, String importedAt, String path) =>
    Provenance(
      source: src.spec.name,
      sourceUrl: src.spec.url,
      sourceCommit: src.spec.commit,
      license: src.spec.licenseId,
      importedAt: importedAt,
      path: path,
    );

/// Imports flipperdevices/irdb, one code set per file:
/// `database/categories/{Category}/{Brand}/{Model}/{Model}.ir`.
abstract final class FlipperImporter {
  /// Source category directory to app category. DVD players and cameras are
  /// not v1 categories and are excluded; this commit has no AC category.
  static const Map<String, DeviceCategory> categories = {
    'TVs': DeviceCategory.tv,
    'Box': DeviceCategory.setTopBox,
    'A_V_receiver': DeviceCategory.soundbar,
    'Projector': DeviceCategory.projector,
    'Fan': DeviceCategory.fan,
    'Air_Purifiers': DeviceCategory.airPurifier,
  };

  /// Reads every file of [src] into candidates, counting into [stats].
  static List<Candidate> run(
    ResolvedSource src,
    String importedAt,
    SourceStats stats,
  ) {
    final root = Directory(p.join(src.root, 'database', 'categories'));
    if (!root.existsSync()) {
      throw SourceException('${src.spec.name}: database/categories missing');
    }
    final out = <Candidate>[];
    final total = _countFiles(root, '.ir');
    final seenBefore = stats.filesSeen;
    for (final catDir in _dirs(root)) {
      final catName = p.basename(catDir.path);
      final category = categories[catName];
      if (category == null) {
        final n = _countFiles(catDir, '.ir');
        stats
          ..filesSeen += n
          ..filesExcluded.add('categoryNotInV1:$catName', n);
        continue;
      }
      for (final brandDir in _dirs(catDir)) {
        for (final modelDir in _dirs(brandDir)) {
          final aliases = _configAliases(modelDir, stats);
          for (final f in _files(modelDir, '.ir')) {
            stats.filesSeen++;
            final c = _file(
              src,
              importedAt,
              stats,
              f,
              category,
              p.basename(brandDir.path),
              p.basename(modelDir.path),
              aliases,
            );
            if (c != null) out.add(c);
          }
        }
      }
    }
    // Files outside {Category}/{Brand}/{Model}/ have no brand or model.
    final stray = total - (stats.filesSeen - seenBefore);
    if (stray > 0) {
      stats
        ..filesSeen += stray
        ..filesExcluded.add('unexpectedPath', stray);
    }
    return out;
  }

  static Map<String, String> _configAliases(Directory dir, SourceStats stats) {
    final f = File(p.join(dir.path, 'config.json'));
    if (!f.existsSync()) return const {};
    try {
      if (f.lengthSync() > _maxConfigBytes) throw const FormatException();
      final json = jsonDecode(utf8.decode(f.readAsBytesSync()));
      final map = json is Map ? json['key_map'] : null;
      if (map is! Map) throw const FormatException();
      final out = <String, String>{};
      map.forEach((flipperKey, entry) {
        final name = entry is Map ? entry['key_name'] : null;
        if (flipperKey is String && name is String) {
          out.putIfAbsent(name, () => flipperKey);
        }
      });
      return out;
    } on FormatException {
      stats.filesExcluded.add('configJsonIgnored');
      return const {};
    }
  }

  static Candidate? _file(
    ResolvedSource src,
    String importedAt,
    SourceStats stats,
    File f,
    DeviceCategory category,
    String brand,
    String model,
    Map<String, String> aliases,
  ) {
    final text = _readText(f, stats);
    if (text == null) return null;
    final FlipperParseResult parsed;
    try {
      parsed = FlipperIr.parse(text);
    } on FormatException {
      stats.filesExcluded.add('formatError');
      return null;
    }
    for (final s in parsed.skipped) {
      stats.signalsSkipped.add(
        '${s.reason.name}${s.protocol == null ? '' : ':${s.protocol}'}',
      );
    }
    final keys = KeyAssembler(stats, aliases: aliases);
    for (final s in parsed.signals) {
      keys.add(s.name, s.code);
    }
    if (keys.keys.isEmpty) {
      stats.filesExcluded.add('noImportableSignals');
      return null;
    }
    stats.filesImported++;
    final rel = p.posix.joinAll(p.split(p.relative(f.path, from: src.root)));
    return Candidate(
      id: stableId('fz', src.spec.name, rel),
      rawBrand: brand,
      category: category,
      label: model,
      keys: keys.keys,
      provenance: _provenance(src, importedAt, rel),
      source: src.spec,
    );
  }
}

/// Imports probonopd/irdb, one code set per file:
/// `codes/{Brand}/{DeviceType}/{D},{S}.csv`.
abstract final class IrdbImporter {
  /// irdb device-type directory (lower case) to app category. Types not
  /// listed are excluded and counted.
  static const Map<String, DeviceCategory> deviceTypes = {
    'tv': DeviceCategory.tv,
    'plasma': DeviceCategory.tv,
    'lcd': DeviceCategory.tv,
    'unknown_tv': DeviceCategory.tv,
    'television': DeviceCategory.tv,
    'satellite': DeviceCategory.setTopBox,
    'satelite dvr': DeviceCategory.setTopBox,
    'unknown_sat': DeviceCategory.setTopBox,
    'cable box': DeviceCategory.setTopBox,
    'set top box': DeviceCategory.setTopBox,
    'dss': DeviceCategory.setTopBox,
    'unknown_dvb': DeviceCategory.setTopBox,
    'iptv': DeviceCategory.setTopBox,
    'receiver': DeviceCategory.soundbar,
    'surround receiver': DeviceCategory.soundbar,
    'multi-zone receiver': DeviceCategory.soundbar,
    'amplifier': DeviceCategory.soundbar,
    'integrated amplifier': DeviceCategory.soundbar,
    'pre-amplifier': DeviceCategory.soundbar,
    'surround processor': DeviceCategory.soundbar,
    'soundbar': DeviceCategory.soundbar,
    'sound bar': DeviceCategory.soundbar,
    'video projector': DeviceCategory.projector,
    'projector': DeviceCategory.projector,
    'fan': DeviceCategory.fan,
    'air conditioner': DeviceCategory.airConditioner,
    'air purifier': DeviceCategory.airPurifier,
  };

  /// Reads every file of [src] into candidates, counting into [stats].
  static List<Candidate> run(
    ResolvedSource src,
    String importedAt,
    SourceStats stats,
  ) {
    final root = Directory(p.join(src.root, 'codes'));
    if (!root.existsSync()) {
      throw SourceException('${src.spec.name}: codes/ missing');
    }
    final out = <Candidate>[];
    for (final brandDir in _dirs(root)) {
      for (final typeDir in _dirs(brandDir)) {
        final type = p.basename(typeDir.path);
        final category = deviceTypes[type.toLowerCase()];
        if (category == null) {
          final n = _countFiles(typeDir, '.csv');
          stats
            ..filesSeen += n
            ..filesExcluded.add('deviceTypeNotInV1', n);
          continue;
        }
        for (final f in _files(typeDir, '.csv')) {
          stats.filesSeen++;
          final text = _readText(f, stats);
          if (text == null) continue;
          final IrdbParseResult parsed;
          try {
            parsed = IrdbCsv.parse(text);
          } on FormatException {
            stats.filesExcluded.add('formatError');
            continue;
          }
          for (final s in parsed.skipped) {
            stats.signalsSkipped.add(
              '${s.reason.name}${s.protocol == null ? '' : ':${s.protocol}'}',
            );
          }
          final keys = KeyAssembler(stats);
          for (final s in parsed.signals) {
            keys.add(s.functionName, s.code);
          }
          if (keys.keys.isEmpty) {
            stats.filesExcluded.add('noImportableSignals');
            continue;
          }
          stats.filesImported++;
          final rel = p.posix.joinAll(
            p.split(p.relative(f.path, from: src.root)),
          );
          out.add(
            Candidate(
              id: stableId('irdb', src.spec.name, rel),
              rawBrand: p.basename(brandDir.path),
              category: category,
              label: '$type ${p.basenameWithoutExtension(f.path)}',
              keys: keys.keys,
              provenance: _provenance(src, importedAt, rel),
              source: src.spec,
            ),
          );
        }
      }
    }
    return out;
  }
}

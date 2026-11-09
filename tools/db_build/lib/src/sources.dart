/// Pinned data sources, fetching them with git, and licence verification.
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

/// The format a source is imported with.
enum SourceKind {
  /// Flipper `.ir` files under `database/categories/<Category>/<Brand>/...`.
  flipper,

  /// irdb CSV files under `codes/<Brand>/<DeviceType>/<D>,<S>.csv`.
  irdb,
}

/// A source pinned to one commit, with the licence reviewed at that commit.
final class SourceSpec {
  /// Creates a spec.
  const SourceSpec({
    required this.kind,
    required this.name,
    required this.url,
    required this.cloneUrl,
    required this.commit,
    required this.cacheName,
    required this.licensePath,
    required this.licenseId,
    required this.licenseSha256,
    required this.priority,
  });

  /// Import format.
  final SourceKind kind;

  /// Short name used in provenance, for example `flipperdevices/irdb`.
  final String name;

  /// Repository URL recorded in provenance.
  final String url;

  /// URL `git` fetches from.
  final String cloneUrl;

  /// Pinned commit (full SHA-1).
  final String commit;

  /// Directory name inside the cache directory.
  final String cacheName;

  /// Path of the licence file in the repository.
  final String licensePath;

  /// Licence identifier recorded in provenance.
  final String licenseId;

  /// SHA-256 of the licence file at [commit], as reviewed. A different hash
  /// stops the build: the licence must be reviewed again before the pin
  /// moves.
  final String licenseSha256;

  /// Deduplication preference: lower wins between equivalent code sets.
  final int priority;
}

/// flipperdevices/irdb, MIT. HEAD as of 2026-11-09.
const SourceSpec flipperIrdb = SourceSpec(
  kind: SourceKind.flipper,
  name: 'flipperdevices/irdb',
  url: 'https://github.com/flipperdevices/irdb',
  cloneUrl: 'https://github.com/flipperdevices/irdb.git',
  commit: 'f7b15366521cc81ba11b341538f0097bddbb748b',
  cacheName: 'flipperdevices-irdb',
  licensePath: 'LICENSE',
  licenseId: 'MIT',
  licenseSha256:
      'e368c2c4c2a508f4d07fb13c501558633d68a43dd6e7751101acd95558f80eac',
  priority: 0,
);

/// probonopd/irdb under its own licence (announce via an issue, include a
/// fixed notice, up to three free copies on request). HEAD as of
/// 2026-11-09. Included only behind gate L4.
const SourceSpec probonopdIrdb = SourceSpec(
  kind: SourceKind.irdb,
  name: 'probonopd/irdb',
  url: 'https://github.com/probonopd/irdb',
  cloneUrl: 'https://github.com/probonopd/irdb.git',
  commit: '11aa5eb3ad9fec9e5c03f170c29c1467733d9f3e',
  cacheName: 'probonopd-irdb',
  licensePath: 'LICENSE.md',
  licenseId: 'LicenseRef-irdb',
  licenseSha256:
      '338b44f76036d1003349ae254051c861941e694ebbfc35b726bd4e607436463d',
  priority: 1,
);

/// Every source the build knows. The community UberGuidoZ/Flipper-IRDB
/// repository is deliberately absent: its CC0 grant covers only
/// contributions after a specific commit, so it is excluded in v1.
const List<SourceSpec> pinnedSources = [flipperIrdb, probonopdIrdb];

/// A source checked out at its pinned commit with a verified licence.
final class ResolvedSource {
  /// Creates a resolved source.
  const ResolvedSource({
    required this.spec,
    required this.root,
    required this.commitDate,
    required this.notice,
  });

  /// The pin.
  final SourceSpec spec;

  /// Directory holding the checked-out tree.
  final String root;

  /// Committer date of the pinned commit, as a UTC `YYYY-MM-DD` date.
  final String commitDate;

  /// The notice the app must show verbatim (gate L3).
  final String notice;
}

/// Thrown when a source cannot be fetched or verified.
final class SourceException implements Exception {
  /// Creates the exception.
  const SourceException(this.message);

  /// What went wrong.
  final String message;

  @override
  String toString() => 'SourceException: $message';
}

/// Fetches pinned commits with the `git` command line into a cache
/// directory and verifies them.
final class GitFetcher {
  /// Creates a fetcher that keeps checkouts under [cacheDir].
  GitFetcher({required this.cacheDir, this.offline = false, this.log});

  /// Cache directory, outside the repository.
  final String cacheDir;

  /// When true, never contact the network; the commit must be cached.
  final bool offline;

  /// Progress sink.
  final void Function(String line)? log;

  /// Default cache directory under the system temp directory.
  static String defaultCacheDir() =>
      p.join(Directory.systemTemp.path, 'irremote_db_build_cache');

  ProcessResult _git(List<String> args, {String? dir, bool check = true}) {
    final r = Process.runSync('git', [
      if (dir != null) ...['-C', dir],
      '-c',
      'advice.detachedHead=false',
      ...args,
    ]);
    if (check && r.exitCode != 0) {
      throw SourceException(
        'git ${args.join(' ')} failed (${r.exitCode}): '
        '${(r.stderr as String).trim()}',
      );
    }
    return r;
  }

  /// Checks out [spec] at its pinned commit and returns the directory.
  ///
  /// Throws [SourceException] when the commit cannot be fetched, the cache
  /// belongs to another remote, the checked-out commit differs from the pin,
  /// or the working tree is not clean.
  String checkout(SourceSpec spec) {
    final dir = p.join(cacheDir, spec.cacheName);
    if (!Directory(p.join(dir, '.git')).existsSync()) {
      Directory(dir).createSync(recursive: true);
      _git(['init', '-q'], dir: dir);
      _git(['remote', 'add', 'origin', spec.cloneUrl], dir: dir);
    }
    final remote =
        (_git(['config', '--get', 'remote.origin.url'], dir: dir).stdout
                as String)
            .trim();
    if (remote != spec.cloneUrl) {
      throw SourceException(
        'cache $dir tracks $remote, not ${spec.cloneUrl}; delete it',
      );
    }
    final have =
        _git(
          ['cat-file', '-e', '${spec.commit}^{commit}'],
          dir: dir,
          check: false,
        ).exitCode ==
        0;
    if (!have) {
      if (offline) {
        throw SourceException('${spec.name}@${spec.commit} is not cached');
      }
      log?.call('fetching ${spec.name}@${spec.commit}');
      final shallow = _git(
        ['fetch', '-q', '--depth', '1', 'origin', spec.commit],
        dir: dir,
        check: false,
      );
      if (shallow.exitCode != 0) {
        _git(['fetch', '-q', 'origin'], dir: dir);
      }
    }
    _git(['checkout', '-q', '--force', '--detach', spec.commit], dir: dir);
    final head = (_git(['rev-parse', 'HEAD'], dir: dir).stdout as String)
        .trim();
    if (head != spec.commit) {
      throw SourceException(
        '${spec.name}: checked out $head, expected ${spec.commit}',
      );
    }
    final status =
        (_git([
                  'status',
                  '--porcelain',
                  '--untracked-files=all',
                ], dir: dir).stdout
                as String)
            .trim();
    if (status.isNotEmpty) {
      throw SourceException('${spec.name}: cache $dir has local changes');
    }
    return dir;
  }

  /// The pinned commit's committer date as a UTC `YYYY-MM-DD` date.
  String commitDate(String dir, String commit) {
    final iso =
        (_git(['show', '-s', '--format=%cI', commit], dir: dir).stdout
                as String)
            .trim();
    final t = DateTime.tryParse(iso);
    if (t == null) throw SourceException('cannot parse commit date "$iso"');
    return t.toUtc().toIso8601String().substring(0, 10);
  }

  /// The bytes of [path] at [commit], independent of the working tree.
  List<int> fileAt(String dir, String commit, String path) {
    final r = Process.runSync('git', [
      '-C',
      dir,
      'show',
      '$commit:$path',
    ], stdoutEncoding: null);
    if (r.exitCode != 0) {
      throw SourceException('$path is missing at $commit');
    }
    return r.stdout as List<int>;
  }

  /// Fetches, checks out and licence-checks [spec].
  ResolvedSource resolve(SourceSpec spec) {
    final dir = checkout(spec);
    final license = fileAt(dir, spec.commit, spec.licensePath);
    final notice = verifyLicense(spec, license);
    return ResolvedSource(
      spec: spec,
      root: dir,
      commitDate: commitDate(dir, spec.commit),
      notice: notice,
    );
  }
}

String _squash(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();

/// The MIT licence body after its copyright line, whitespace-normalized.
const String _mitBody =
    'Permission is hereby granted, free of charge, to any person obtaining a '
    'copy of this software and associated documentation files (the '
    '"Software"), to deal in the Software without restriction, including '
    'without limitation the rights to use, copy, modify, merge, publish, '
    'distribute, sublicense, and/or sell copies of the Software, and to '
    'permit persons to whom the Software is furnished to do so, subject to '
    'the following conditions: The above copyright notice and this '
    'permission notice shall be included in all copies or substantial '
    'portions of the Software. THE SOFTWARE IS PROVIDED "AS IS", WITHOUT '
    'WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO '
    'THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND '
    'NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE '
    'LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION '
    'OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION '
    'WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.';

/// Whether [text] is the MIT licence with a single copyright line.
bool isMitLicense(String text) {
  final m = RegExp(
    r'^MIT License Copyright \(c\) [^.]{1,200}? (Permission is hereby .*)$',
  ).firstMatch(_squash(text));
  return m != null && m.group(1) == _mitBody;
}

/// The notice irdb's licence requires products to include, whitespace
/// normalized, or `null` when the text does not carry the three expected
/// conditions.
String? irdbNotice(String text) {
  final t = _squash(text);
  final notice = RegExp(r'`(Contains/accesses irdb[^`]+)`').firstMatch(t);
  final conditions =
      t.contains(
        'inform the irdb project about your product by opening an '
        'issue on https://github.com/probonopd/irdb/issues',
      ) &&
      t.contains('make available up to three fully licensed copies/units');
  if (notice == null || !conditions) return null;
  return notice.group(1)!.trim();
}

/// Verifies the licence of [spec] from the file [bytes] at the pinned
/// commit and returns the notice to show. Throws [SourceException] when the
/// text differs from the reviewed one or is not the expected licence.
String verifyLicense(SourceSpec spec, List<int> bytes) {
  final hash = sha256.convert(bytes).toString();
  final text = utf8.decode(bytes, allowMalformed: true);
  if (hash != spec.licenseSha256) {
    throw SourceException(
      '${spec.name} licence (${spec.licensePath}) at ${spec.commit} has '
      'SHA-256 $hash, not the reviewed ${spec.licenseSha256}; review it '
      'before building',
    );
  }
  switch (spec.kind) {
    case SourceKind.flipper:
      if (spec.licenseId != 'MIT' || !isMitLicense(text)) {
        throw SourceException('${spec.name} licence is not MIT; stop');
      }
      return text.trim();
    case SourceKind.irdb:
      final notice = irdbNotice(text);
      if (notice == null) {
        throw SourceException(
          '${spec.name} licence lacks the expected conditions',
        );
      }
      return notice;
  }
}

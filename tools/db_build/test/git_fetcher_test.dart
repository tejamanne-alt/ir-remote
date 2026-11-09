import 'dart:io';

import 'package:db_build/db_build.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'fixtures.dart';

String _git(String dir, List<String> args, {Map<String, String>? env}) {
  final r = Process.runSync('git', [
    '-C',
    dir,
    '-c',
    'user.name=Test',
    '-c',
    'user.email=test@example.invalid',
    '-c',
    'commit.gpgsign=false',
    ...args,
  ], environment: env);
  if (r.exitCode != 0) fail('git ${args.join(' ')}: ${r.stderr}');
  return (r.stdout as String).trim();
}

void main() {
  late Directory tmp;
  late String origin;
  late String first;
  late SourceSpec spec;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('git_fetcher_test_');
    origin = p.join(tmp.path, 'origin');
    Directory(origin).createSync();
    _git(origin, ['init', '-q']);
    File(p.join(origin, 'LICENSE')).writeAsStringSync(mitText);
    File(p.join(origin, 'data.txt')).writeAsStringSync('v1\n');
    _git(origin, ['add', '.']);
    _git(
      origin,
      ['commit', '-q', '-m', 'first'],
      env: {'GIT_COMMITTER_DATE': '2026-04-24T17:33:26+03:00'},
    );
    first = _git(origin, ['rev-parse', 'HEAD']);
    // The remote moves on; the pin must not follow.
    File(p.join(origin, 'data.txt')).writeAsStringSync('v2\n');
    _git(origin, ['commit', '-q', '-am', 'second']);
    spec = SourceSpec(
      kind: SourceKind.flipper,
      name: 'test/repo',
      url: 'https://example.invalid/test/repo',
      cloneUrl: Uri.directory(origin).toString(),
      commit: first,
      cacheName: 'repo',
      licensePath: 'LICENSE',
      licenseId: 'MIT',
      licenseSha256: flipperIrdb.licenseSha256,
      priority: 0,
    );
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  String cache() => p.join(tmp.path, 'cache');

  test('checks out and verifies the pinned commit, not the remote HEAD', () {
    final r = GitFetcher(cacheDir: cache()).resolve(spec);
    expect(r.root, p.join(cache(), 'repo'));
    expect(r.commitDate, '2026-04-24');
    expect(r.notice, mitText.trim());
    expect(File(p.join(r.root, 'data.txt')).readAsStringSync(), 'v1\n');
    expect(_git(r.root, ['rev-parse', 'HEAD']), first);
    // A second resolve works offline from the cache.
    final again = GitFetcher(cacheDir: cache(), offline: true).resolve(spec);
    expect(again.root, r.root);
  });

  test('restores modified tracked files and refuses untracked ones', () {
    final f = GitFetcher(cacheDir: cache());
    final dir = f.checkout(spec);
    File(p.join(dir, 'data.txt')).writeAsStringSync('edited\n');
    f.checkout(spec);
    expect(File(p.join(dir, 'data.txt')).readAsStringSync(), 'v1\n');
    File(p.join(dir, 'planted.ir')).writeAsStringSync('x');
    expect(() => f.checkout(spec), throwsA(isA<SourceException>()));
  });

  test('fails for unknown commits, offline misses and foreign caches', () {
    final bad = copySpec(spec, commit: 'f' * 40);
    expect(
      () => GitFetcher(cacheDir: cache()).checkout(bad),
      throwsA(isA<SourceException>()),
    );
    expect(
      () => GitFetcher(
        cacheDir: p.join(tmp.path, 'c2'),
        offline: true,
      ).checkout(spec),
      throwsA(isA<SourceException>()),
    );
    GitFetcher(cacheDir: cache()).checkout(spec);
    final foreign = SourceSpec(
      kind: spec.kind,
      name: spec.name,
      url: spec.url,
      cloneUrl: 'https://example.invalid/other.git',
      commit: spec.commit,
      cacheName: spec.cacheName,
      licensePath: spec.licensePath,
      licenseId: spec.licenseId,
      licenseSha256: spec.licenseSha256,
      priority: 0,
    );
    expect(
      () => GitFetcher(cacheDir: cache()).checkout(foreign),
      throwsA(isA<SourceException>()),
    );
  });

  test('reads the licence at the commit, not from the working tree', () {
    final f = GitFetcher(cacheDir: cache());
    final dir = f.checkout(spec);
    File(p.join(dir, 'LICENSE')).writeAsStringSync('GPL');
    expect(String.fromCharCodes(f.fileAt(dir, first, 'LICENSE')), mitText);
    expect(() => f.fileAt(dir, first, 'NOPE'), throwsA(isA<SourceException>()));
    final wrong = copySpec(spec, licenseSha256: '0' * 64);
    expect(() => f.resolve(wrong), throwsA(isA<SourceException>()));
  });
}

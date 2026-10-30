import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';
import 'package:path/path.dart' as p;

import 'package:setup_hooks/src/mihomo.dart';

void main() {
  late Directory core;
  late Directory source;
  late File existing;
  late File added;
  late File patch;

  String git(List<String> arguments) {
    final result = Process.runSync('git', ['-C', source.path, ...arguments]);
    if (result.exitCode != 0) {
      throw StateError('${result.stderr}');
    }
    return (result.stdout as String).trim();
  }

  setUp(() {
    core = Directory.systemTemp.createTempSync('mihomo-source-test-');
    source = Directory(p.join(core.path, 'Clash.Meta'))..createSync();
    existing = File(p.join(source.path, 'features.txt'))
      ..writeAsStringSync('base\n');
    added = File(p.join(source.path, 'dns.txt'));
    git(['init', '--quiet']);
    git(['add', 'features.txt']);
    git([
      '-c',
      'user.name=Mihomo source test',
      '-c',
      'user.email=source-test@example.invalid',
      'commit',
      '--quiet',
      '-m',
      'Fixture upstream',
    ]);
    final commit = git(['rev-parse', 'HEAD']);
    existing.writeAsStringSync('base\npatched\n');
    added.writeAsStringSync('DNS adapter\n');
    git(['add', '-N', 'dns.txt']);
    final diff =
        Process.runSync('git', ['-C', source.path, 'diff', '--binary']).stdout
            as String;
    patch = File(p.join(core.path, 'openharmony.patch'))
      ..writeAsStringSync(diff);
    File(p.join(core.path, 'mihomo.lock.json')).writeAsStringSync(
      jsonEncode({
        'version': 'v1.19.33',
        'upstreamCommit': commit,
        'flClashCommit': commit,
        'patch': 'openharmony.patch',
        'patchSha256': sha256.convert(patch.readAsBytesSync()).toString(),
        'patchedFiles': {
          'features.txt': sha256.convert(existing.readAsBytesSync()).toString(),
          'dns.txt': sha256.convert(added.readAsBytesSync()).toString(),
        },
      }),
    );
    git(['reset', '--', 'dns.txt']);
    git(['checkout', '--', 'features.txt']);
    added.deleteSync();
  });

  tearDown(() => core.deleteSync(recursive: true));

  test('check verifies clean sources without applying the patch', () {
    expect(prepareMihomo(corePath: core.path, checkOnly: true), 'v1.19.33');
    expect(existing.readAsStringSync(), 'base\n');
    expect(added.existsSync(), isFalse);
    expect(git(['status', '--porcelain']), isEmpty);
  });

  test('prepare is repeatable and reverse restores clean upstream sources', () {
    expect(prepareMihomo(corePath: core.path), 'v1.19.33');
    expect(existing.readAsStringSync(), 'base\npatched\n');
    expect(added.readAsStringSync(), 'DNS adapter\n');
    expect(prepareMihomo(corePath: core.path), 'v1.19.33');
    expect(prepareMihomo(corePath: core.path, checkOnly: true), 'v1.19.33');
    prepareMihomo(corePath: core.path, reverse: true);
    expect(git(['status', '--porcelain']), isEmpty);
    expect(existing.readAsStringSync(), 'base\n');
    expect(added.existsSync(), isFalse);
    prepareMihomo(corePath: core.path, reverse: true);
  });

  test('refuses a patch whose checksum changed', () {
    patch.writeAsStringSync('${patch.readAsStringSync()}\n');
    expect(() => prepareMihomo(corePath: core.path), throwsStateError);
    expect(git(['status', '--porcelain']), isEmpty);
  });

  test('refuses a different source commit', () {
    git([
      '-c',
      'user.name=Mihomo source test',
      '-c',
      'user.email=source-test@example.invalid',
      'commit',
      '--allow-empty',
      '--quiet',
      '-m',
      'Different source',
    ]);
    expect(() => prepareMihomo(corePath: core.path), throwsStateError);
    expect(added.existsSync(), isFalse);
  });

  test('refuses unrelated changes without overwriting them', () {
    final unrelated = File(p.join(source.path, 'user.txt'))
      ..writeAsStringSync('keep this\n');
    expect(() => prepareMihomo(corePath: core.path), throwsStateError);
    expect(unrelated.readAsStringSync(), 'keep this\n');
    expect(existing.readAsStringSync(), 'base\n');
  });

  test('reverse preserves edits made after preparation', () {
    prepareMihomo(corePath: core.path);
    existing.writeAsStringSync('${existing.readAsStringSync()}user edit\n');
    expect(
      () => prepareMihomo(corePath: core.path, reverse: true),
      throwsStateError,
    );
    expect(existing.readAsStringSync(), contains('user edit'));
    expect(added.existsSync(), isTrue);
  });
}

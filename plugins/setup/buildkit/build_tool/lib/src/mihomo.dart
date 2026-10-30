import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

/// Prepares only the audited OHOS changes on the pinned FlClash core.
///
/// The submodule stays on a publicly fetchable commit. Repeated preparation is
/// safe, and reverse refuses to overwrite changes made after preparation.
String prepareMihomo({
  required String corePath,
  bool checkOnly = false,
  bool reverse = false,
}) {
  if (checkOnly && reverse) {
    throw ArgumentError('Use either --check or --reverse.');
  }
  final lock =
      jsonDecode(File(p.join(corePath, 'mihomo.lock.json')).readAsStringSync())
          as Map<String, dynamic>;
  final version = lock['version'] as String;
  final commit = lock['flClashCommit'] as String;
  final upstream = lock['upstreamCommit'] as String;
  final files = Map<String, String>.from(lock['patchedFiles'] as Map);
  final sourcePath = p.join(corePath, 'Clash.Meta');
  final patch = File(p.join(corePath, lock['patch'] as String));
  if (sha256.convert(patch.readAsBytesSync()).toString() !=
      lock['patchSha256']) {
    throw StateError('Mihomo OHOS patch SHA256 does not match its lock file.');
  }
  if (files.isEmpty ||
      files.keys.any((name) => p.isAbsolute(name) || name.contains('..'))) {
    throw StateError('Invalid managed Mihomo paths.');
  }

  ProcessResult git(List<String> arguments) =>
      Process.runSync('git', ['-C', sourcePath, ...arguments]);

  String checkedGit(List<String> arguments) {
    final result = git(arguments);
    if (result.exitCode != 0) {
      throw StateError('Mihomo git ${arguments.join(' ')}: ${result.stderr}');
    }
    return (result.stdout as String).trim();
  }

  if (checkedGit(['rev-parse', 'HEAD']) != commit) {
    throw StateError('Mihomo checkout must be $commit ($version).');
  }
  checkedGit(['merge-base', '--is-ancestor', upstream, commit]);
  final status = checkedGit([
    'status',
    '--porcelain=v1',
    '-z',
    '--untracked-files=all',
  ]);
  if (status.isEmpty) {
    checkedGit(['apply', '--check', patch.absolute.path]);
    if (!checkOnly && !reverse) {
      checkedGit(['apply', patch.absolute.path]);
    }
    return version;
  }

  // Do not trim porcelain records: the leading space distinguishes unstaged
  // changes from staged changes, which this preparation never owns.
  final rawStatus =
      git(['status', '--porcelain=v1', '-z', '--untracked-files=all']).stdout
          as String;
  final records = rawStatus.split('\u0000').where((s) => s.isNotEmpty);
  final changed = <String>{};
  for (final record in records) {
    if (record.length < 4 ||
        !const [' M', '??'].contains(record.substring(0, 2))) {
      throw StateError(
        'Mihomo contains changes outside the managed OHOS patch.',
      );
    }
    changed.add(record.substring(3));
  }
  if (changed.length != files.length || !changed.containsAll(files.keys)) {
    throw StateError('Mihomo contains changes outside the managed OHOS patch.');
  }
  for (final entry in files.entries) {
    final file = File(p.join(sourcePath, entry.key));
    if (!file.existsSync() ||
        sha256.convert(file.readAsBytesSync()).toString() != entry.value) {
      throw StateError(
        'Mihomo ${entry.key} differs from the managed OHOS patch.',
      );
    }
  }
  checkedGit(['apply', '--reverse', '--check', patch.absolute.path]);
  if (reverse) {
    checkedGit(['apply', '--reverse', patch.absolute.path]);
  }
  return version;
}

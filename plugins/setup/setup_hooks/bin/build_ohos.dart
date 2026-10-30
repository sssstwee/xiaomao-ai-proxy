import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:setup_hooks/src/build.dart';
import 'package:setup_hooks/src/target.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length > 1) {
    stderr.writeln(
      'Usage: dart run plugins/setup/setup_hooks/bin/build_ohos.dart [repository-root]',
    );
    exitCode = 64;
    return;
  }
  final root = arguments.isEmpty ? Directory.current.path : arguments.single;
  await buildPlatform(
    BuildRequest(
      rootDir: root,
      target: Target.ohosArm64,
      harnessDir: p.join(root, 'plugins', 'setup', 'setup_hooks'),
    ),
  );
}

import 'dart:io';

// Reuse the build harness without adding another package to the app.
// ignore: avoid_relative_lib_imports
import '../plugins/setup/buildkit/build_tool/lib/src/mihomo.dart';

void main(List<String> arguments) {
  if (arguments.any(
    (argument) => !const ['--check', '--reverse'].contains(argument),
  )) {
    stderr.writeln(
      'Usage: dart run core/prepare_mihomo.dart [--check|--reverse]',
    );
    exitCode = 64;
    return;
  }
  try {
    final version = prepareMihomo(
      corePath: File.fromUri(Platform.script).parent.path,
      checkOnly: arguments.contains('--check'),
      reverse: arguments.contains('--reverse'),
    );
    stdout.writeln('Mihomo $version source and OHOS patch verified.');
  } on Object catch (error) {
    stderr.writeln(error);
    exitCode = 1;
  }
}

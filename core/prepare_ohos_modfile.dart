import 'dart:io';

// ignore: avoid_relative_lib_imports
import '../plugins/setup/setup_hooks/lib/src/mihomo.dart';

void main() {
  stdout.writeln(
    prepareOhosModule(corePath: File.fromUri(Platform.script).parent.path),
  );
}

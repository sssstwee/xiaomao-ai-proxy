import 'dart:io';

import 'package:hooks/hooks.dart';
import 'package:setup_hooks/setup_hooks.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (Platform.environment['FLCLASH_OHOS_BUILD'] == '1') return;
    await const CoreBuilder().run(input: input, output: output);
  });
}

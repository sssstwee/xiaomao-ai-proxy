import 'dart:io';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show ExternalLibrary;

import 'rust/frb_generated.dart';

Future<void> initializeRustApi() {
  if (Platform.operatingSystem == 'ohos') {
    return RustLib.init(
      externalLibrary: ExternalLibrary.open('librust_api.so'),
    );
  }
  return RustLib.init();
}

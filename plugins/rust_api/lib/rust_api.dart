library;

import 'src/rust/frb_generated.dart';

export 'src/rust/api/hotkey.dart';
export 'src/rust/api/ipc.dart';
export 'src/rust/api/script.dart';
export 'src/rust/frb_generated.dart' show RustLib;
export 'src/initialize.dart'
    if (dart.library.io) 'src/initialize_io.dart'
    show initializeRustApi;

bool get isRustLibInitialized => RustLib.instance.initialized;

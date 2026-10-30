# file_picker_ohos

An explicit, unendorsed OHOS implementation for upstream `file_picker` 12.3.
The application keeps the official current file-picker API and all other
platform implementations. This package registers only on OHOS.

The Dart bridge reuses `android_file_picker` 1.1's existing channel protocol.
Its file operations have no `Platform.isAndroid` gate and native cached-file
results are read through `XFile`, without an Android content resolver or SAF.
OHOS supplies the matching native method/event channels, file selection,
sandbox caching, and document-save implementation.

The `ohos/` sources are reused from
[tljk/flutter_file_picker](https://github.com/tljk/flutter_file_picker/tree/0b87942446aae6d11079ba5d6fd2a3a29c626332/ohos),
commit `0b87942446aae6d11079ba5d6fd2a3a29c626332`, tag
`v12.0.0-beta.7-fix-ohos`. They retain their Apache-2.0 headers. The original
package's MIT license is retained in `LICENSE`; the Apache license is in
`LICENSE-APACHE`. Local changes default omitted `withData` to false and make
modern saves use their supplied bytes (including empty files), independently
of earlier file selections.

Run `flutter test` and `flutter analyze --no-fatal-infos` in this directory.
The channel tests simulate the OHOS result maps; real system-picker, URI
permissions, and document-save behavior still require an authorized HAP and
the target device.

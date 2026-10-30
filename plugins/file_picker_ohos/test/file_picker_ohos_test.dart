import 'dart:io';

import 'package:file_picker_ohos/file_picker_ohos.dart';
import 'package:file_picker_platform_interface/file_picker_platform_interface.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('miguelruivo.flutter.plugins.filepicker');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late FilePickerPlatform previous;
  late FilePickerOhos picker;
  late Directory directory;

  setUp(() async {
    previous = FilePickerPlatform.instance;
    FilePickerOhos.registerWith();
    picker = FilePickerPlatform.instance as FilePickerOhos;
    directory = await Directory.systemTemp.createTemp('file_picker_ohos_');
  });

  tearDown(() async {
    messenger.setMockMethodCallHandler(channel, null);
    FilePickerPlatform.instance = previous;
    await directory.delete(recursive: true);
  });

  Future<void> mockPickedFile(String path, Uint8List bytes) async {
    await File(path).writeAsBytes(bytes);
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'any');
      expect(call.arguments['allowMultipleSelection'], false);
      return [
        {
          'path': path,
          'name': '测试配置.yaml',
          'size': bytes.length,
          'bytes': null,
          'identifier': 'file://docs/storage/Users/currentUser/测试配置.yaml',
        },
      ];
    });
  }

  test('reads the native cached path without an Android resolver', () async {
    final path = '${directory.path}/测试配置.yaml';
    final bytes = Uint8List.fromList([0, 1, 2, 127, 255]);
    await mockPickedFile(path, bytes);

    final file = await picker.pickFile();

    expect(file, isNotNull);
    expect(file!.name, '测试配置.yaml');
    expect(file.uri, Uri.file(path));
    expect(file.path, path);
    expect(file.lengthSync(), bytes.length);
    expect(await file.readAsBytes(), bytes);
    expect(
      await file.readAsByteStream().expand((part) => part).toList(),
      bytes,
    );
  });

  test('returns null or an empty list when selection is cancelled', () async {
    messenger.setMockMethodCallHandler(channel, (call) async => null);

    expect(await picker.pickFile(), isNull);
    expect(await picker.pickFiles(), isEmpty);
  });

  test('saves the supplied bytes and preserves the document URI', () async {
    final bytes = Uint8List.fromList([1, 2, 3]);
    const saved = 'file://docs/storage/Users/currentUser/配置备份.zip';
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'save');
      expect(call.arguments['fileName'], '配置备份.zip');
      expect(call.arguments['bytes'], bytes);
      return saved;
    });

    final uri = await picker.saveFile(
      fileName: '配置备份.zip',
      bytes: bytes,
      mimeType: 'application/zip',
    );

    expect(uri, Uri.parse(saved));
    expect(uri!.authority, 'docs');
  });

  test('passes an empty file to the native save implementation', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.arguments['bytes'], isEmpty);
      return 'file://docs/storage/Users/currentUser/empty.yaml';
    });

    expect(
      await picker.saveFile(
        fileName: 'empty.yaml',
        bytes: Uint8List(0),
        mimeType: 'application/yaml',
      ),
      Uri.parse('file://docs/storage/Users/currentUser/empty.yaml'),
    );
  });

  test('returns null when the save dialog is cancelled', () async {
    messenger.setMockMethodCallHandler(channel, (call) async => null);

    expect(
      await picker.saveFile(
        fileName: 'profile.yaml',
        bytes: Uint8List.fromList([1]),
        mimeType: 'application/yaml',
      ),
      isNull,
    );
  });
}

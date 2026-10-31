import 'dart:async';
import 'dart:io';

import 'package:fl_clash/common/package.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

class _RealHttpOverrides extends HttpOverrides {}

final _localizedPackageInfo = PackageInfo(
  appName: '野猫代理',
  packageName: 'com.xiaomao.proxy',
  version: '1.0.0',
  buildNumber: '2026103002',
);

void main() {
  group('package user agent', () {
    test('uses the fixed ASCII name when the package has a localized name', () {
      expect(
        _localizedPackageInfo.ua,
        'FlClash/v1.0.0 clash-verge Platform/${Platform.operatingSystem}',
      );
      expect(
        _localizedPackageInfo.ua.codeUnits.every((unit) => unit < 128),
        isTrue,
      );
      expect(_localizedPackageInfo.appName, '野猫代理');
    });

    test('is accepted as an actual HttpClient request header', () async {
      await HttpOverrides.runWithHttpOverrides(() async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final received = Completer<String?>();
        final subscription = server.listen((request) {
          received.complete(request.headers.value(HttpHeaders.userAgentHeader));
          unawaited(request.response.close());
        });
        final client = HttpClient()
          ..userAgent = _localizedPackageInfo.ua
          ..findProxy = (_) => 'DIRECT';
        try {
          final request = await client.getUrl(
            Uri.http('127.0.0.1:${server.port}', '/profile'),
          );
          final response = await request.close();
          await response.drain<void>();

          expect(await received.future, _localizedPackageInfo.ua);
        } finally {
          client.close(force: true);
          await subscription.cancel();
          await server.close(force: true);
        }
      }, _RealHttpOverrides());
    });
  });
}

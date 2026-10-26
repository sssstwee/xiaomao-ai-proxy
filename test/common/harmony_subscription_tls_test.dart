import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:fl_clash/common/harmony_account.dart';
import 'package:fl_clash/common/http.dart';
import 'package:flutter_test/flutter_test.dart';

class _SubscriptionStore extends HarmonySessionStore {
  _SubscriptionStore(this.url);

  final String url;

  @override
  Future<String?> readSubscriptionUrl() async => url;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late HttpServer server;
  final receivedPaths = <String>[];

  setUp(() async {
    receivedPaths.clear();
    final context = SecurityContext()
      ..useCertificateChainBytes(utf8.encode(_certificate))
      ..usePrivateKeyBytes(utf8.encode(_privateKey));
    server = await HttpServer.bindSecure(
      InternetAddress.loopbackIPv4,
      0,
      context,
    );
    server.listen((request) async {
      receivedPaths.add(request.uri.path);
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'schemaVersion': 1}));
      await request.response.close();
    }, onError: (Object error) => expect(error, isA<HandshakeException>()));
  });

  tearDown(() async {
    await server.close(force: true);
  });

  test(
    'subscription rejects untrusted TLS despite the global override',
    () async {
      await HttpOverrides.runWithHttpOverrides(() async {
        final origin = 'https://127.0.0.1:${server.port}';
        // Prove the fixture is reachable and the application-wide override would
        // accept its self-signed certificate without the subscription guard.
        final permissive = HttpClient();
        try {
          final response = await (await permissive.getUrl(
            Uri.parse('$origin/control'),
          )).close();
          expect(response.statusCode, HttpStatus.ok);
          await response.drain<void>();
        } finally {
          permissive.close(force: true);
        }
        final http = Dio(
          BaseOptions(connectTimeout: const Duration(seconds: 2)),
        );
        addTearDown(() => http.close(force: true));
        final api = HarmonyAccountApi(
          http: http,
          storage: _SubscriptionStore('$origin/subscription/config.yaml'),
          directSubscription: true,
        );
        await api.restore();
        await expectLater(
          api.fetchHomeDisplay(),
          throwsA(HarmonyAccountError.unavailable),
        );
        expect(receivedPaths, ['/control']);
      }, FlClashHttpOverrides());
    },
  );
}

// Self-signed loopback-only test fixture, valid 2020-2120. This key was generated
// for these tests and is never used by an application or deployment.
const _certificate = '''-----BEGIN CERTIFICATE-----
MIIBXTCCAQKgAwIBAgIBATAKBggqhkjOPQQDAjAeMRwwGgYDVQQDDBNsb2NhbGhv
c3QgdGVzdCBvbmx5MCAXDTIwMDEwMTAwMDAwMFoYDzIxMjAwMTAxMDAwMDAwWjAe
MRwwGgYDVQQDDBNsb2NhbGhvc3QgdGVzdCBvbmx5MFkwEwYHKoZIzj0CAQYIKoZI
zj0DAQcDQgAE8KRRueF79E5394r5P7hY5FFFLmsuCl8uEyNSiTHs2Mis8/6rSzHJ
KgVo9VGn5Lmp/tx0xswV5Ju3bH4uVT7SNaMvMC0wGgYDVR0RBBMwEYIJbG9jYWxo
b3N0hwR/AAABMA8GA1UdEwEB/wQFMAMBAf8wCgYIKoZIzj0EAwIDSQAwRgIhANDg
QpkSLZlJMcCANJHGkgLwpNa6Go7TqTdZY/w7tZ41AiEA4yf8X58/+hvgedKIzp4x
vn/O44/P/51VuhG+wc7aYuE=
-----END CERTIFICATE-----
''';
const _privateKey = '''-----BEGIN PRIVATE KEY-----
MIGHAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBG0wawIBAQQge522zjCzPvzC/jX1
FHEBqRGeRhAJSxmF93CAPKKH6pGhRANCAATwpFG54Xv0Tnf3ivk/uFjkUUUuay4K
Xy4TI1KJMezYyKzz/qtLMckqBWj1Uafkuan+3HTGzBXkm7dsfi5VPtI1
-----END PRIVATE KEY-----
''';

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

class _TrustedFixtureOverride extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final trusted = SecurityContext(withTrustedRoots: false)
      ..setTrustedCertificatesBytes(utf8.encode(_caCertificate));
    return super.createHttpClient(trusted);
  }
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
      if (request.uri.path.endsWith('/version')) {
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'version': 'new-version'}));
      } else if (request.uri.path.endsWith('config.yaml')) {
        request.response.headers.set('x-config-version', 'new-version');
        request.response.write('proxies: []\nrules: []\n');
      } else {
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'schemaVersion': 1}));
      }
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

  test(
    'disconnected subscription uses and releases its temporary proxy',
    () async {
      final proxy = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(proxy.close);
      final sockets = <Socket>[];
      addTearDown(() {
        for (final socket in sockets) {
          socket.destroy();
        }
      });
      var connects = 0;
      proxy.listen((downstream) {
        sockets.add(downstream);
        Socket? upstream;
        var headers = <int>[];
        downstream.listen((bytes) async {
          if (upstream != null) {
            upstream!.add(bytes);
            return;
          }
          headers.addAll(bytes);
          final text = latin1.decode(headers);
          if (!text.contains('\r\n\r\n')) return;
          expect(text, startsWith('CONNECT '));
          connects++;
          upstream = await Socket.connect(
            InternetAddress.loopbackIPv4,
            server.port,
          );
          sockets.add(upstream!);
          upstream!.listen(downstream.add, onDone: downstream.destroy);
          downstream.write('HTTP/1.1 200 Connection Established\r\n\r\n');
          headers = [];
        }, onDone: () => upstream?.destroy());
      });
      final unused = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final closedPort = unused.port;
      await unused.close();
      var closed = 0;
      await HttpOverrides.runWithHttpOverrides(() async {
        final http = Dio(
          BaseOptions(connectTimeout: const Duration(seconds: 2)),
        );
        addTearDown(() => http.close(force: true));
        final api = HarmonyAccountApi(
          http: http,
          storage: _SubscriptionStore(
            'https://localhost:$closedPort/subscription/config.yaml',
          ),
          directSubscription: true,
        );
        await api.restore();
        api.openOfflineProxy = () async => HarmonySubscriptionProxyLease(
          port: proxy.port,
          close: () async => closed++,
        );

        final response = await api.fetchHomeDisplay();
        final version = await api.fetchConfigVersionInfo();
        final config = await api.downloadConfig();
        expect(response.statusCode, HttpStatus.ok);
        expect(version?.version, 'new-version');
        expect(config.configVersion, 'new-version');
        expect(utf8.decode(config.bytes!), 'proxies: []\nrules: []\n');
        expect(connects, 3);
        expect(receivedPaths, [
          '/subscription/home.json',
          '/subscription/config.yaml/version',
          '/subscription/config.yaml',
        ]);
        expect(closed, 3);
      }, _TrustedFixtureOverride());
    },
  );

  test('an unavailable temporary proxy falls back to direct HTTPS', () async {
    final unused = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final closedPort = unused.port;
    await unused.close();
    var closed = 0;
    await HttpOverrides.runWithHttpOverrides(() async {
      final http = Dio(BaseOptions(connectTimeout: const Duration(seconds: 2)));
      addTearDown(() => http.close(force: true));
      final api = HarmonyAccountApi(
        http: http,
        storage: _SubscriptionStore(
          'https://localhost:${server.port}/subscription/config.yaml',
        ),
        directSubscription: true,
      );
      await api.restore();
      api.openOfflineProxy = () async => HarmonySubscriptionProxyLease(
        port: closedPort,
        close: () async => closed++,
      );
      expect((await api.fetchHomeDisplay()).statusCode, HttpStatus.ok);
      expect(receivedPaths, ['/subscription/home.json']);
      expect(closed, 1);
    }, _TrustedFixtureOverride());
  });
}

// Loopback-only test fixture, signed by a test root and valid 2015-2120. This key was generated
// for these tests and is never used by an application or deployment.
const _certificate = '''-----BEGIN CERTIFICATE-----
MIIBiDCCAS6gAwIBAgIUIJStk9D9s78x4pMkEmTYhCdhvYswCgYIKoZIzj0EAwIw
HzEdMBsGA1UEAwwUTG9jYWwgdGVzdCByb290IG9ubHkwIBcNMTUwMTAxMDAwMDAw
WhgPMjEyMDAxMDEwMDAwMDBaMBQxEjAQBgNVBAMMCWxvY2FsaG9zdDBZMBMGByqG
SM49AgEGCCqGSM49AwEHA0IABBhkkUBPlEFKRjICN4Tzi1FGgJE2aIK4z7XoTDJZ
/PxjTz9dC1u7C6uSwY3PQi2FwJpLj1thpfYlUwf/w7xH9x2jUTBPMAwGA1UdEwEB
/wQCMAAwGgYDVR0RBBMwEYIJbG9jYWxob3N0hwR/AAABMBMGA1UdJQQMMAoGCCsG
AQUFBwMBMA4GA1UdDwEB/wQEAwIFoDAKBggqhkjOPQQDAgNIADBFAiEAz9zzEbP5
hbVKlEkKm9adwZ8QXSEhiw340LHGHm3uERQCICoWIypPwvsKN4cKl0RhBfi+Hg/W
BBufp2ZI8h0/x0Gq
-----END CERTIFICATE-----
''';
const _privateKey = '''-----BEGIN PRIVATE KEY-----
MIGHAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBG0wawIBAQQgIM4/k7uMfLFJilP0
cUwziCVHlHizuNllIQqP1V+WFdehRANCAAQYZJFAT5RBSkYyAjeE84tRRoCRNmiC
uM+16EwyWfz8Y08/XQtbuwurksGNz0IthcCaS49bYaX2JVMH/8O8R/cd
-----END PRIVATE KEY-----
''';

const _caCertificate = '''-----BEGIN CERTIFICATE-----
MIIBaDCCAQ6gAwIBAgIUGZjfOvxOC2oG9Vj70E/UUj8sxlowCgYIKoZIzj0EAwIw
HzEdMBsGA1UEAwwUTG9jYWwgdGVzdCByb290IG9ubHkwIBcNMTUwMTAxMDAwMDAw
WhgPMjEyMDAxMDEwMDAwMDBaMB8xHTAbBgNVBAMMFExvY2FsIHRlc3Qgcm9vdCBv
bmx5MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEna+d4FzBbNMw2hjV8RWDC4hH
UMZ3+m7+mpo/hu4PvCD1hdc3DjlPVkp5guPy0oiJrcp5n31Pfj0Ie2BESgXCwaMm
MCQwEgYDVR0TAQH/BAgwBgEB/wIBADAOBgNVHQ8BAf8EBAMCAYYwCgYIKoZIzj0E
AwIDSAAwRQIhAMdZph/tKSb3I29LaqIIQ7U2iN+NKFYEYIWjLIZyog+0AiAYIcyq
7Hxwycb39r0TuNdA2LRNiF5eAZo4EktJf20lxg==
-----END CERTIFICATE-----
''';

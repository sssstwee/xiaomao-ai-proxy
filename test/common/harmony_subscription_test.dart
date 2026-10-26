import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:fl_clash/common/harmony_account.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harmony_account_test.dart' show Adapter, MemoryStore, jsonBody;

class SubscriptionStore extends MemoryStore {
  String? url;

  @override
  Future<String?> readSubscriptionUrl() async => url;

  @override
  Future<void> writeSubscriptionUrl(String value) async => url = value;

  @override
  Future<void> deleteSubscriptionUrl() async => url = null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const source = 'https://vps.example.test:8444/private/vpn.yml';

  test(
    'the app uses direct subscriptions without restoring old account tokens',
    () async {
      final store = SubscriptionStore()..token = 'old-cloud-session';
      final http = Dio(BaseOptions(baseUrl: harmonyApiUrl));
      http.httpClientAdapter = Adapter(
        (_) => throw StateError('Unexpected network request'),
      );
      final api = HarmonyAccountApi(
        http: http,
        storage: store,
        directSubscription: true,
      );
      expect(harmonyAccount.directSubscription, isTrue);
      expect(await api.restore(), isNull);
      expect(api.isAuthorized, isFalse);
      http.close();
    },
  );

  test(
    'subscription, version and home requests go to the VPS without bearer auth',
    () async {
      final requests = <RequestOptions>[];
      final store = SubscriptionStore();
      final http = Dio(BaseOptions(baseUrl: harmonyApiUrl));
      http.httpClientAdapter = Adapter((request) {
        requests.add(request);
        switch (request.uri.path) {
          case '/private/vpn.yml':
            return ResponseBody.fromString(
              'proxies: []\n',
              200,
              headers: {
                'content-type': ['application/yaml'],
                'etag': ['"source-v1"'],
                'x-config-version': ['source-v1'],
              },
            );
          case '/private/vpn.yml/version':
            return jsonBody({'version': 'source-v1', 'min_check_seconds': 300});
          case '/private/home.json':
            return jsonBody({'schemaVersion': 1});
          default:
            throw StateError('Unexpected endpoint');
        }
      });
      final api = HarmonyAccountApi(
        http: http,
        storage: store,
        directSubscription: true,
      );
      await api.configureSubscription(source);
      final session = await api.restore();
      expect(session, isNotNull);
      expect(api.isAuthorized, isTrue);
      expect(store.token, isNull);
      expect(store.url, source);
      final download = await api.downloadConfig();
      expect(utf8.decode(download.bytes!), 'proxies: []\n');
      expect((await api.fetchConfigVersionInfo())!.version, 'source-v1');
      await api.fetchHomeDisplay();
      expect(requests, hasLength(3));
      for (final request in requests) {
        expect(request.uri.host, 'vps.example.test');
        expect(request.uri.port, 8444);
        expect(
          request.headers.keys.map((key) => key.toLowerCase()),
          isNot(contains('authorization')),
        );
      }
      await api.logout();
      expect(store.url, isNull);
      expect(api.session, isNull);
      expect(requests, hasLength(3));
      http.close();
    },
  );

  test(
    'subscription ownership survives restart and changes with the source URL',
    () async {
      final store = SubscriptionStore();
      final first = HarmonyAccountApi(storage: store, directSubscription: true);
      await first.configureSubscription(source);
      final original = await first.restore();
      final restarted = HarmonyAccountApi(
        storage: store,
        directSubscription: true,
      );
      expect((await restarted.restore())!.token, original!.token);
      await restarted.configureSubscription(
        'https://other.example.test/vpn.yml',
      );
      expect((await restarted.restore())!.token, isNot(original.token));
    },
  );

  test(
    'invalid and plaintext subscription URLs do not replace a saved source',
    () async {
      final store = SubscriptionStore()..url = source;
      final api = HarmonyAccountApi(storage: store, directSubscription: true);
      for (final invalid in [
        'http://vps.example.test/vpn.yml',
        'https://user:pass@vps.example.test/vpn.yml',
        'not-a-url',
      ]) {
        await expectLater(
          api.configureSubscription(invalid),
          throwsA(HarmonyAccountError.config),
        );
        expect(store.url, source);
      }
    },
  );
}

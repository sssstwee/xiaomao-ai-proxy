import 'dart:async';

import 'package:fl_clash/core/interface.dart';
import 'package:fl_clash/core/lib.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/plugins/service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _Handler extends CoreHandlerInterface {
  String? response;

  @override
  final Completer<bool> completer = Completer<bool>()..complete(true);

  @override
  Future<T?> invoke<T>({
    required ActionMethod method,
    dynamic data,
    Duration? timeout,
  }) async => response as T?;

  @override
  bool destroy() => true;

  @override
  Future<String> preload() async => '';

  @override
  Future<bool> shutdown(bool isUser) async => true;
}

class _Service extends Mock implements Service {}

const _setup = SetupParams(selectedMap: {}, testUrl: 'https://example.test');
const _update = UpdateParams(
  tun: Tun(enable: false),
  mixedPort: 7890,
  allowLan: false,
  findProcessMode: FindProcessMode.off,
  mode: Mode.rule,
  logLevel: LogLevel.info,
  ipv6: false,
  tcpConcurrent: false,
  externalController: ExternalControllerStatus.close,
  unifiedDelay: false,
);
const _change = ChangeProxyParams(groupName: 'Proxy', proxyName: 'Node');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue(
      const Action(method: ActionMethod.setupConfig, data: null, id: 'test'),
    );
  });

  final operations = <String, Future<String> Function(_Handler)>{
    'validateConfig': (handler) => handler.validateConfig('/tmp/config.yaml'),
    'setupConfig': (handler) => handler.setupConfig(_setup),
    'updateConfig': (handler) => handler.updateConfig(_update),
    'changeProxy': (handler) => handler.changeProxy(_change),
  };
  for (final entry in operations.entries) {
    group(entry.key, () {
      test('a missing core response is a failure', () async {
        await expectLater(entry.value(_Handler()), throwsStateError);
      });

      test('an acknowledged empty response remains successful', () async {
        final handler = _Handler()..response = '';
        expect(await entry.value(handler), '');
      });

      test('preserves an explicit core error', () async {
        final handler = _Handler()..response = 'Invalid configuration';
        expect(await entry.value(handler), 'Invalid configuration');
      });
    });
  }

  group('mobile listener lifecycle', () {
    late _Service service;
    late CoreLib core;
    late List<String> events;
    bool? coreResponse = true;
    Object? coreFailure;

    setUp(() {
      service = _Service();
      core = CoreLib.test(service);
      events = [];
      coreResponse = true;
      coreFailure = null;
      when(() => service.invokeAction(any())).thenAnswer((invocation) async {
        final action = invocation.positionalArguments.single as Action;
        events.add(action.method.name);
        if (coreFailure != null) throw coreFailure!;
        if (coreResponse == null) return null;
        return ActionResult(method: action.method, data: coreResponse);
      });
      when(() => service.start()).thenAnswer((_) async {
        events.add('nativeStart');
        return true;
      });
      when(() => service.stop()).thenAnswer((_) async {
        events.add('nativeStop');
        return true;
      });
    });

    test('a rejected core start never starts the native VPN', () async {
      coreResponse = false;
      await expectLater(core.startListener(), throwsStateError);
      expect(events, ['startListener']);
      verifyNever(() => service.start());
    });

    test('a missing core start response never starts the native VPN', () async {
      coreResponse = null;
      await expectLater(core.startListener(), throwsStateError);
      expect(events, ['startListener']);
      verifyNever(() => service.start());
    });

    test('starts the native VPN only after the core acknowledges', () async {
      expect(await core.startListener(), isTrue);
      expect(events, ['startListener', 'nativeStart']);
    });

    test('a native startup failure rolls back the core listener', () async {
      when(() => service.start()).thenAnswer((_) async {
        events.add('nativeStart');
        return false;
      });
      await expectLater(core.startListener(), throwsStateError);
      expect(events, ['startListener', 'nativeStart', 'stopListener']);
    });

    test(
      'rollback failure preserves the original native startup error',
      () async {
        final failure = StateError('Native VPN denied');
        when(() => service.start()).thenAnswer((_) async {
          coreFailure = StateError('Core rollback transport failed');
          throw failure;
        });
        await expectLater(core.startListener(), throwsA(same(failure)));
        expect(events, ['startListener', 'stopListener']);
      },
    );

    test('a rejected core stop still cleans up the native VPN', () async {
      coreResponse = false;
      await expectLater(core.stopListener(), throwsStateError);
      expect(events, ['stopListener', 'nativeStop']);
    });

    test('a core transport failure still cleans up the native VPN', () async {
      final failure = StateError('Core transport failed');
      coreFailure = failure;
      await expectLater(core.stopListener(), throwsA(same(failure)));
      expect(events, ['stopListener', 'nativeStop']);
    });

    test('a native cleanup failure is reported', () async {
      when(() => service.stop()).thenAnswer((_) async => false);
      await expectLater(core.stopListener(), throwsStateError);
      verify(() => service.stop()).called(1);
    });

    test('stop succeeds after both layers acknowledge', () async {
      expect(await core.stopListener(), isTrue);
      expect(events, ['stopListener', 'nativeStop']);
    });
  });
}

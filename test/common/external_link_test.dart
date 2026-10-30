import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/test_app.dart';

const _launcherChannel = MethodChannel('plugins.flutter.io/url_launcher');
const _url = 'https://github.com/sssstwee/xiaomao-ai-proxy/releases/latest';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <MethodCall>[];
  var launches = true;
  var throws = false;
  String? copied;

  setUp(() {
    calls.clear();
    launches = true;
    throws = false;
    copied = null;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(_launcherChannel, (
      call,
    ) async {
      calls.add(call);
      if (throws) throw PlatformException(code: 'ACTIVITY_NOT_FOUND');
      return launches;
    });
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
  });

  tearDown(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      _launcherChannel,
      null,
    );
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    );
  });

  Future<ProviderContainer> host(WidgetTester tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    globalState.container = container;
    container.read(viewSizeProvider.notifier).value = const Size(800, 600);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const TestApp(
          locale: Locale('en'),
          child: Scaffold(body: SizedBox.shrink()),
        ),
      ),
    );
    return container;
  }

  void expectExternalLaunch(String url) {
    expect(calls, hasLength(1));
    final call = calls.single;
    expect(call.method, 'launch');
    expect(call.arguments['url'], url);
    expect(call.arguments['useWebView'], isFalse);
    expect(call.arguments['useSafariVC'], isFalse);
  }

  testWidgets('external links open the system browser after confirmation', (
    tester,
  ) async {
    await host(tester);
    final result = dialogs.openUrl(_url);
    await tester.pumpAndSettle();
    expect(calls, isEmpty);
    await tester.tap(find.text('Go'));
    await tester.pumpAndSettle();
    await result;
    expectExternalLaunch(_url);
    expect(find.text('Copy link'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancelling an external link does not open the browser', (
    tester,
  ) async {
    await host(tester);
    final result = dialogs.openUrl(_url);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await result;
    expect(calls, isEmpty);
  });

  for (final failsWithException in [false, true]) {
    testWidgets('browser failure offers a copyable link '
        '(exception: $failsWithException)', (tester) async {
      launches = false;
      throws = failsWithException;
      await host(tester);
      final result = dialogs.openUrl(_url, confirm: false);
      await tester.pumpAndSettle();
      expectExternalLaunch(_url);
      expect(find.textContaining(_url, findRichText: true), findsOneWidget);
      expect(
        find.textContaining('Could not open the browser.', findRichText: true),
        findsOneWidget,
      );
      await tester.tap(find.text('Copy link'));
      await tester.pumpAndSettle();
      await result;
      expect(copied, _url);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('update opens the discovered release without a second prompt', (
    tester,
  ) async {
    final container = await host(tester);
    const tag = 'v1.0.1+2026103003';
    final result = container
        .read(commonActionProvider.notifier)
        .checkUpdateResultHandle(
          isUser: true,
          data: {'tag_name': tag, 'body': null},
        );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Download'));
    await tester.pumpAndSettle();
    await result;
    expectExternalLaunch('https://github.com/$repository/releases/tag/$tag');
    expect(find.text('External link'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

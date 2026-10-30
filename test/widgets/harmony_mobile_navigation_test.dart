import 'package:fl_clash/common/navigation.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/pages/home.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/views/dashboard/simple.dart';
import 'package:fl_clash/views/proxies/proxies.dart';
import 'package:fl_clash/views/proxies/tab.dart';
import 'package:fl_clash/views/logs.dart';
import 'package:fl_clash/views/config/advanced.dart';
import 'package:fl_clash/views/config/config.dart';
import 'package:fl_clash/views/config/general.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget child) => MaterialApp(
  locale: const Locale('zh', 'CN'),
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: const [Locale('zh', 'CN')],
  home: Scaffold(body: child),
);

class _FormPage extends StatefulWidget {
  const _FormPage();

  @override
  State<_FormPage> createState() => _FormPageState();
}

class _FormPageState extends State<_FormPage> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Center(
    child: TextField(
      key: const Key('retained_profile_form'),
      controller: _controller,
    ),
  );
}

void main() {
  setUpAll(() async {
    await AppLocalizations.load(const Locale('zh', 'CN'));
  });

  test('Harmony exposes four tabs before any subscription is imported', () {
    final items = navigation.getItems(isHarmony: true);
    expect(
      items
          .where((item) => item.modes.contains(NavigationItemMode.mobile))
          .map((item) => item.label),
      [
        PageLabel.dashboard,
        PageLabel.proxies,
        PageLabel.profiles,
        PageLabel.tools,
      ],
    );
    final home = items.singleWhere((item) => item.label == PageLabel.dashboard);
    expect(home.keep, isTrue);
    final logs = items.singleWhere((item) => item.label == PageLabel.logs);
    expect(logs.modes, contains(NavigationItemMode.more));
  });

  testWidgets('Harmony dashboard reuses the subscription-aware home', (
    tester,
  ) async {
    final contextKey = GlobalKey();
    await tester.pumpWidget(_app(SizedBox(key: contextKey)));
    final item = navigation
        .getItems(isHarmony: true)
        .singleWhere((item) => item.label == PageLabel.dashboard);
    expect(
      item.builder(contextKey.currentContext!),
      isA<SimpleDashboardView>(),
    );
  });

  testWidgets('four tabs switch without losing an in-progress profile form', (
    tester,
  ) async {
    final items = [
      NavigationItem(
        icon: const Icon(Icons.space_dashboard),
        label: PageLabel.dashboard,
        builder: (_) => const Center(child: Text('home page')),
      ),
      NavigationItem(
        icon: const Icon(Icons.article),
        label: PageLabel.proxies,
        builder: (_) => const Center(child: Text('proxy page')),
      ),
      NavigationItem(
        icon: const Icon(Icons.folder),
        label: PageLabel.profiles,
        builder: (_) => const _FormPage(),
      ),
      NavigationItem(
        icon: const Icon(Icons.construction),
        label: PageLabel.tools,
        builder: (_) => const Center(child: Text('tools page')),
      ),
    ];
    final container = ProviderContainer(
      overrides: [
        viewSizeProvider.overrideWithBuild((_, _) => const Size(440, 744)),
        currentNavigationItemsStateProvider.overrideWithValue(
          NavigationItemsState(value: items),
        ),
        appSettingProvider.overrideWithBuild(
          (_, _) => const AppSettingProps(isAnimateToPage: false),
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: _app(const HomePage(isHarmony: true)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(NavigationDestination), findsNWidgets(4));
    expect(find.text('首页'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.folder));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('retained_profile_form')),
      'keep me',
    );
    await tester.tap(find.byIcon(Icons.article));
    await tester.pumpAndSettle();
    expect(container.read(currentPageLabelProvider), PageLabel.proxies);
    await tester.tap(find.byIcon(Icons.construction));
    await tester.pumpAndSettle();
    expect(container.read(currentPageLabelProvider), PageLabel.tools);
    await tester.tap(find.byIcon(Icons.folder));
    await tester.pumpAndSettle();
    expect(find.text('keep me'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty proxy page opens profiles instead of stranding the user', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: _app(const ProxiesEmptyState()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('前往配置'), findsOneWidget);
    await tester.tap(find.byKey(const Key('harmony_open_profiles')));
    expect(container.read(currentPageLabelProvider), PageLabel.profiles);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'empty filtered proxy groups cannot schedule an invalid tab index',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            proxiesTabStateProvider.overrideWithValue(
              const ProxiesTabState(
                groups: [],
                currentGroupName: null,
                proxyCardType: ProxyCardType.expand,
                columns: 1,
              ),
            ),
          ],
          child: _app(const ProxiesTabView()),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('logs remain discoverable with an explicit capture switch', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        appSettingProvider.overrideWithBuild(
          (_, _) => const AppSettingProps(openLogs: false),
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: _app(const LogsView()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('日志捕获已关闭，可通过上方开关收集新的日志。'), findsOneWidget);
    expect(container.read(appSettingProvider).openLogs, isFalse);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(container.read(appSettingProvider).openLogs, isTrue);
    expect(find.text('日志捕获已关闭，可通过上方开关收集新的日志。'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Harmony settings expose working controls without DNS overrides',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(child: _app(const ConfigView(isHarmony: true))),
      );
      await tester.pumpAndSettle();
      expect(find.text('分流与 DNS 由当前配置管理。'), findsOneWidget);
      expect(find.byType(HostsItem), findsNothing);
      expect(find.byType(AppendSystemDNSItem), findsNothing);
      expect(find.byType(FindProcessItem), findsNothing);
      expect(find.byType(LogLevelItem), findsOneWidget);
      expect(find.byType(TestUrlItem), findsOneWidget);

      await tester.pumpWidget(
        ProviderScope(child: _app(const AdvancedConfigView(isHarmony: true))),
      );
      await tester.pumpAndSettle();
      expect(find.text('分流与 DNS 由当前配置管理。'), findsOneWidget);
      expect(find.text('DNS'), findsNothing);
      expect(find.byIcon(Icons.library_books), findsNothing);
      expect(find.byIcon(Icons.rocket), findsNothing);
      expect(find.byIcon(Icons.vpn_key), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

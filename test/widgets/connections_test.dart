import 'dart:async';

import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/views/connection/connections.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Widget app(Widget child) => ProviderScope(
  child: MaterialApp(
    locale: const Locale('zh', 'CN'),
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const [Locale('zh', 'CN')],
    home: child,
  ),
);

void main() {
  setUpAll(() async {
    await AppLocalizations.load(const Locale('zh', 'CN'));
  });

  testWidgets('live connections continue polling while the page is idle', (
    tester,
  ) async {
    var reads = 0;
    await tester.pumpWidget(
      app(
        ConnectionsView(
          connectionsReader: () async {
            reads++;
            return [];
          },
        ),
      ),
    );
    await tester.pump();
    expect(reads, 1);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(reads, 2);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(reads, 3);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
    expect(reads, 3);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'leaving connections during a read does not update disposed state',
    (tester) async {
      final pending = Completer<List<TrackerInfo>>();
      await tester.pumpWidget(
        app(ConnectionsView(connectionsReader: () => pending.future)),
      );
      await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());
      pending.complete([]);
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );
}

import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/state.dart';
import 'package:fl_clash/views/tools.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_app.dart';

void main() {
  testWidgets('mobile tools expose app access without desktop shortcuts', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(440, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final container = ProviderContainer(
      overrides: [
        moreToolsSelectorStateProvider.overrideWithValue(
          const MoreToolsSelectorState(navigationItems: []),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const TestApp(
          child: ToolsView(isMobile: true, isDesktop: false),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final l10n = AppLocalizations.current;
    expect(find.text(l10n.accessControl), findsOneWidget);
    expect(find.text(l10n.hotkeyManagement), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

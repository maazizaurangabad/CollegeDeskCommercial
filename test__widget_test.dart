import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiksha_desk/app/app.dart';
import 'package:shiksha_desk/app/startup/startup_state.dart';
import 'package:shiksha_desk/platform/data/data_providers.dart';
import 'package:shiksha_desk/platform/data/module_settings_repository.dart';

import 'test_support.dart';

Future<StartupState> _pumpAt(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final startup = (await tester.runAsync(newTestStartup))!;
  await tester.pumpWidget(ProviderScope(
    overrides: [startupStateProvider.overrideWithValue(startup)],
    child: const ShikshaDeskApp(),
  ));
  await tester.pumpAndSettle();
  return startup;
}

Future<void> _close(WidgetTester tester, StartupState startup) async {
  await tester.pumpWidget(const SizedBox());
  await tester.runAsync(() => startup.database.close());
}

void main() {
  testWidgets('phone layout uses a bottom navigation bar', (tester) async {
    final startup = await _pumpAt(tester, const Size(400, 860));
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    expect(find.text('Dashboard'), findsWidgets);
    expect(find.text('Demo mode: sample data only'), findsOneWidget);
    await _close(tester, startup);
  });

  testWidgets('desktop layout uses a sidebar', (tester) async {
    final startup = await _pumpAt(tester, const Size(1280, 800));
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    await _close(tester, startup);
  });

  testWidgets('switching off Students hides it and saves the choice', (tester) async {
    final startup = await _pumpAt(tester, const Size(1280, 800));
    expect(find.text('Students'), findsWidgets);

    await tester.tap(find.text('Settings').first);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Modules'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Modules'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(SwitchListTile, 'Students'));
    await tester.pumpAndSettle();
    expect(find.descendant(of: find.byType(NavigationRail), matching: find.text('Students')), findsNothing);

    final saved = await tester.runAsync(
      () => ModuleSettingsRepository(startup.database, startup.session).loadAll(),
    );
    expect(saved!['students'], isFalse);
    await _close(tester, startup);
  });

  testWidgets('the demo institution has its classes and divisions', (tester) async {
    final startup = await _pumpAt(tester, const Size(1280, 900));
    await tester.tap(find.text('Settings').first);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Classes and divisions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Classes and divisions'));
    await tester.pumpAndSettle();
    expect(find.text('11th Science'), findsOneWidget);
    expect(find.text('Add division'), findsWidgets);
    await _close(tester, startup);
  });

  testWidgets('the students list shows demo students and search narrows it', (tester) async {
    final startup = await _pumpAt(tester, const Size(1280, 900));
    await tester.tap(find.text('Students').first);
    await tester.pumpAndSettle();
    expect(find.text('30 students'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'STU-000007');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.text('1 students'), findsOneWidget);
    await _close(tester, startup);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('App boots and shows Contract Shield home UI', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({'releaseSafeMode': false});

    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    expect(find.text('Contract Shield'), findsWidgets);
    expect(find.text('Store Submission Text'), findsOneWidget);
    expect(find.text('Runtime Diagnostics'), findsOneWidget);
  });

  testWidgets('Release-safe mode hides debug-only home actions', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({'releaseSafeMode': true});

    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    expect(find.text('Store Submission Text'), findsOneWidget);
    expect(find.text('Analytics Dashboard (Debug)'), findsNothing);
    expect(find.text('Runtime Diagnostics'), findsNothing);
  });

  test('Runtime diagnostics stores and clears errors', () async {
    await RuntimeDiagnostics.clearErrors();
    await RuntimeDiagnostics.recordError('test_scope', 'sample_error');

    final entries = await RuntimeDiagnostics.getRecentErrors();
    expect(entries.isNotEmpty, isTrue);
    expect(entries.last.contains('test_scope'), isTrue);

    await RuntimeDiagnostics.clearErrors();
    final afterClear = await RuntimeDiagnostics.getRecentErrors();
    expect(afterClear, isEmpty);
  });
}

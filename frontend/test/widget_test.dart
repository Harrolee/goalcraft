import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:goalcraft/main.dart';

void main() {
  group('GoalCraftApp', () {
    testWidgets('app smoke test - loads without crashing', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: GoalCraftApp(),
        ),
      );

      // Let it settle
      await tester.pumpAndSettle(const Duration(seconds: 1));

      // Verify the app loads with title in AppBar
      expect(find.text('GoalCraft'), findsWidgets);
    });

    testWidgets('home screen shows goals title', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: GoalCraftApp(),
        ),
      );

      await tester.pumpAndSettle(const Duration(seconds: 1));

      // Should show My Goals or similar heading
      expect(find.textContaining('Goals'), findsWidgets);
    });

    testWidgets('has floating action button for new goal', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: GoalCraftApp(),
        ),
      );

      await tester.pumpAndSettle(const Duration(seconds: 1));

      // Should have a FAB for adding new goals
      expect(find.byType(FloatingActionButton), findsOneWidget);
    });

    testWidgets('FAB navigates to new goal screen', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: GoalCraftApp(),
        ),
      );

      await tester.pumpAndSettle(const Duration(seconds: 1));

      // Tap the FAB
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      // Should navigate to new goal screen - look for form elements
      expect(find.byType(TextField), findsWidgets);
    });

    testWidgets('new goal screen has title field', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: GoalCraftApp(),
        ),
      );

      await tester.pumpAndSettle(const Duration(seconds: 1));

      // Navigate to new goal screen
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      // Should have a title text field with label
      expect(find.widgetWithText(TextFormField, ''), findsWidgets);
    });
  });
}

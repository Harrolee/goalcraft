import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goalcraft/models/milestone.dart';
import 'package:goalcraft/widgets/milestone_tile.dart';

void main() {
  group('MilestoneTile', () {
    testWidgets('displays milestone title', (tester) async {
      final milestone = Milestone(
        id: 1,
        title: 'Test Milestone',
        status: MilestoneStatus.pending,
        order: 0,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MilestoneTile(
              milestone: milestone,
              onToggle: () {},
            ),
          ),
        ),
      );

      expect(find.text('Test Milestone'), findsOneWidget);
    });

    testWidgets('displays milestone description when provided', (tester) async {
      final milestone = Milestone(
        id: 1,
        title: 'Test Milestone',
        description: 'This is a description',
        status: MilestoneStatus.pending,
        order: 0,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MilestoneTile(
              milestone: milestone,
              onToggle: () {},
            ),
          ),
        ),
      );

      expect(find.text('Test Milestone'), findsOneWidget);
      expect(find.text('This is a description'), findsOneWidget);
    });

    testWidgets('shows checkbox unchecked for pending status', (tester) async {
      final milestone = Milestone(
        id: 1,
        title: 'Pending Milestone',
        status: MilestoneStatus.pending,
        order: 0,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MilestoneTile(
              milestone: milestone,
              onToggle: () {},
            ),
          ),
        ),
      );

      final checkbox = tester.widget<Checkbox>(find.byType(Checkbox));
      expect(checkbox.value, false);
    });

    testWidgets('shows checkbox checked for completed status', (tester) async {
      final milestone = Milestone(
        id: 1,
        title: 'Completed Milestone',
        status: MilestoneStatus.completed,
        order: 0,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MilestoneTile(
              milestone: milestone,
              onToggle: () {},
            ),
          ),
        ),
      );

      final checkbox = tester.widget<Checkbox>(find.byType(Checkbox));
      expect(checkbox.value, true);
    });

    testWidgets('calls onToggle when checkbox is tapped', (tester) async {
      bool toggleCalled = false;

      final milestone = Milestone(
        id: 1,
        title: 'Test Milestone',
        status: MilestoneStatus.pending,
        order: 0,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MilestoneTile(
              milestone: milestone,
              onToggle: () => toggleCalled = true,
            ),
          ),
        ),
      );

      await tester.tap(find.byType(Checkbox));
      expect(toggleCalled, true);
    });

    testWidgets('displays due date when provided', (tester) async {
      final milestone = Milestone(
        id: 1,
        title: 'Milestone with due date',
        dueDate: DateTime(2024, 2, 15),
        status: MilestoneStatus.pending,
        order: 0,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MilestoneTile(
              milestone: milestone,
              onToggle: () {},
            ),
          ),
        ),
      );

      // The widget should show the due date in some format
      expect(find.textContaining('Feb'), findsOneWidget);
    });

    testWidgets('shows in_progress indicator', (tester) async {
      final milestone = Milestone(
        id: 1,
        title: 'In Progress Milestone',
        status: MilestoneStatus.inProgress,
        order: 0,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MilestoneTile(
              milestone: milestone,
              onToggle: () {},
            ),
          ),
        ),
      );

      // Checkbox should be indeterminate (tristate) for in_progress
      final checkbox = tester.widget<Checkbox>(find.byType(Checkbox));
      expect(checkbox.value, false); // or could be null if tristate
    });
  });
}

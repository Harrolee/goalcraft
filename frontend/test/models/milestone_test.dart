import 'package:flutter_test/flutter_test.dart';
import 'package:goalcraft/models/milestone.dart';

void main() {
  group('Milestone', () {
    test('fromJson parses all fields', () {
      final json = {
        'id': 101,
        'title': 'Complete tutorial',
        'description': 'Finish the official tutorial',
        'due_date': '2024-02-01T00:00:00',
        'status': 'pending',
        'order': 0,
        'created_at': '2024-01-15T10:30:00',
      };

      final milestone = Milestone.fromJson(json);

      expect(milestone.id, 101);
      expect(milestone.title, 'Complete tutorial');
      expect(milestone.description, 'Finish the official tutorial');
      expect(milestone.dueDate, DateTime(2024, 2, 1));
      expect(milestone.status, MilestoneStatus.pending);
      expect(milestone.order, 0);
      expect(milestone.createdAt, DateTime(2024, 1, 15, 10, 30));
    });

    test('fromJson parses minimal fields with defaults', () {
      final json = {
        'id': 102,
        'title': 'Simple milestone',
        'description': null,
        'due_date': null,
        'status': 'pending',
        'order': 1,
        'created_at': null,
      };

      final milestone = Milestone.fromJson(json);

      expect(milestone.id, 102);
      expect(milestone.title, 'Simple milestone');
      expect(milestone.description, isNull);
      expect(milestone.dueDate, isNull);
      expect(milestone.status, MilestoneStatus.pending);
      expect(milestone.order, 1);
      expect(milestone.createdAt, isNull);
    });

    test('fromJson parses all status values', () {
      final statuses = {
        'pending': MilestoneStatus.pending,
        'in_progress': MilestoneStatus.inProgress,
        'completed': MilestoneStatus.completed,
        'skipped': MilestoneStatus.skipped,
      };

      for (final entry in statuses.entries) {
        final json = {
          'id': 1,
          'title': 'Test',
          'status': entry.key,
          'order': 0,
        };

        final milestone = Milestone.fromJson(json);
        expect(milestone.status, entry.value,
            reason: 'Status ${entry.key} should map to ${entry.value}');
      }
    });

    test('toJson serializes correctly', () {
      final milestone = Milestone(
        id: 101,
        title: 'Test milestone',
        description: 'Test description',
        dueDate: DateTime(2024, 2, 1),
        status: MilestoneStatus.inProgress,
        order: 2,
        createdAt: DateTime(2024, 1, 15),
      );

      final json = milestone.toJson();

      expect(json['id'], 101);
      expect(json['title'], 'Test milestone');
      expect(json['description'], 'Test description');
      expect(json['due_date'], '2024-02-01T00:00:00.000');
      expect(json['status'], 'in_progress');
      expect(json['order'], 2);
    });

    test('copyWith creates new instance with updated status', () {
      final original = Milestone(
        id: 101,
        title: 'Test',
        status: MilestoneStatus.pending,
        order: 0,
      );

      final updated = original.copyWith(status: MilestoneStatus.completed);

      expect(updated.status, MilestoneStatus.completed);
      expect(original.status, MilestoneStatus.pending);
    });
  });

  group('MilestoneStatus', () {
    test('all statuses have correct JSON values', () {
      expect(MilestoneStatus.pending.name, 'pending');
      expect(MilestoneStatus.inProgress.name, 'inProgress');
      expect(MilestoneStatus.completed.name, 'completed');
      expect(MilestoneStatus.skipped.name, 'skipped');
    });
  });
}

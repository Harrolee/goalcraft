import 'package:flutter_test/flutter_test.dart';
import 'package:goalcraft/models/goal.dart';
import 'package:goalcraft/models/milestone.dart';

void main() {
  group('Goal', () {
    test('fromJson parses goal without milestones', () {
      final json = {
        'id': 1,
        'user_id': 42,
        'title': 'Learn Flutter',
        'description': 'Master Flutter development',
        'target_date': '2024-06-01T00:00:00',
        'created_at': '2024-01-15T10:30:00',
        'milestones': [],
      };

      final goal = Goal.fromJson(json);

      expect(goal.id, 1);
      expect(goal.userId, 42);
      expect(goal.title, 'Learn Flutter');
      expect(goal.description, 'Master Flutter development');
      expect(goal.targetDate, DateTime(2024, 6, 1));
      expect(goal.createdAt, DateTime(2024, 1, 15, 10, 30));
      expect(goal.milestones, isEmpty);
    });

    test('fromJson parses goal with milestones', () {
      final json = {
        'id': 1,
        'user_id': 42,
        'title': 'Learn Flutter',
        'description': null,
        'target_date': null,
        'created_at': '2024-01-15T10:30:00',
        'milestones': [
          {
            'id': 101,
            'title': 'Complete tutorial',
            'description': 'Finish the official tutorial',
            'due_date': '2024-02-01T00:00:00',
            'status': 'pending',
            'order': 0,
            'created_at': '2024-01-15T10:30:00',
          },
          {
            'id': 102,
            'title': 'Build first app',
            'description': null,
            'due_date': null,
            'status': 'in_progress',
            'order': 1,
            'created_at': '2024-01-15T10:30:00',
          },
        ],
      };

      final goal = Goal.fromJson(json);

      expect(goal.id, 1);
      expect(goal.description, isNull);
      expect(goal.targetDate, isNull);
      expect(goal.milestones, hasLength(2));
      expect(goal.milestones[0].title, 'Complete tutorial');
      expect(goal.milestones[0].status, MilestoneStatus.pending);
      expect(goal.milestones[1].title, 'Build first app');
      expect(goal.milestones[1].status, MilestoneStatus.inProgress);
    });

    test('toJson serializes correctly', () {
      final goal = Goal(
        id: 1,
        userId: 42,
        title: 'Test Goal',
        description: 'Test description',
        targetDate: DateTime(2024, 6, 1),
        createdAt: DateTime(2024, 1, 15, 10, 30),
        milestones: [],
      );

      final json = goal.toJson();

      expect(json['id'], 1);
      expect(json['user_id'], 42);
      expect(json['title'], 'Test Goal');
      expect(json['description'], 'Test description');
      expect(json['target_date'], '2024-06-01T00:00:00.000');
      expect(json['created_at'], '2024-01-15T10:30:00.000');
    });

    test('copyWith creates new instance with updated values', () {
      final original = Goal(
        id: 1,
        userId: 42,
        title: 'Original',
        description: 'Original desc',
        targetDate: DateTime(2024, 6, 1),
        createdAt: DateTime(2024, 1, 15),
        milestones: [],
      );

      final updated = original.copyWith(title: 'Updated');

      expect(updated.id, 1);
      expect(updated.title, 'Updated');
      expect(updated.description, 'Original desc');
      expect(original.title, 'Original'); // Original unchanged
    });
  });
}

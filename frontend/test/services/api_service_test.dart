import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:goalcraft/services/api_service.dart';
import 'package:goalcraft/models/milestone.dart';

void main() {
  late Dio dio;
  late DioAdapter dioAdapter;
  late ApiService apiService;

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: 'http://localhost:8000/api'));
    dioAdapter = DioAdapter(dio: dio);
    apiService = ApiService(dio: dio);
  });

  group('ApiService', () {
    group('createGoal', () {
      test('creates goal with title only', () async {
        dioAdapter.onPost(
          '/goals',
          (server) => server.reply(201, {
            'id': 1,
            'user_id': 42,
            'title': 'Test Goal',
            'description': null,
            'target_date': null,
            'created_at': '2024-01-15T10:30:00',
            'milestones': [],
          }),
          data: {
            'title': 'Test Goal',
            'description': null,
            'target_date': null,
          },
        );

        final goal = await apiService.createGoal(title: 'Test Goal');

        expect(goal.id, 1);
        expect(goal.title, 'Test Goal');
        expect(goal.milestones, isEmpty);
      });

      test('creates goal with all fields', () async {
        final targetDate = DateTime(2024, 6, 1);

        dioAdapter.onPost(
          '/goals',
          (server) => server.reply(201, {
            'id': 2,
            'user_id': 42,
            'title': 'Full Goal',
            'description': 'Goal description',
            'target_date': '2024-06-01T00:00:00',
            'created_at': '2024-01-15T10:30:00',
            'milestones': [
              {
                'id': 101,
                'title': 'Milestone 1',
                'description': 'First step',
                'due_date': '2024-02-01T00:00:00',
                'status': 'pending',
                'order': 0,
                'created_at': '2024-01-15T10:30:00',
              },
            ],
          }),
          data: {
            'title': 'Full Goal',
            'description': 'Goal description',
            'target_date': targetDate.toIso8601String(),
          },
        );

        final goal = await apiService.createGoal(
          title: 'Full Goal',
          description: 'Goal description',
          targetDate: targetDate,
        );

        expect(goal.id, 2);
        expect(goal.title, 'Full Goal');
        expect(goal.description, 'Goal description');
        expect(goal.milestones, hasLength(1));
        expect(goal.milestones[0].title, 'Milestone 1');
      });

      test('throws exception on error', () async {
        dioAdapter.onPost(
          '/goals',
          (server) => server.reply(422, {
            'detail': 'Title cannot be empty',
          }),
          data: {
            'title': '',
            'description': null,
            'target_date': null,
          },
        );

        expect(
          () => apiService.createGoal(title: ''),
          throwsA(isA<Exception>()),
        );
      });
    });

    group('getGoals', () {
      test('returns list of goals', () async {
        dioAdapter.onGet(
          '/goals',
          (server) => server.reply(200, [
            {
              'id': 1,
              'user_id': 42,
              'title': 'Goal 1',
              'description': null,
              'target_date': null,
              'created_at': '2024-01-15T10:30:00',
              'milestones': [],
            },
            {
              'id': 2,
              'user_id': 42,
              'title': 'Goal 2',
              'description': 'Second goal',
              'target_date': '2024-06-01T00:00:00',
              'created_at': '2024-01-16T09:00:00',
              'milestones': [],
            },
          ]),
        );

        final goals = await apiService.getGoals();

        expect(goals, hasLength(2));
        expect(goals[0].title, 'Goal 1');
        expect(goals[1].title, 'Goal 2');
      });

      test('returns empty list when no goals', () async {
        dioAdapter.onGet(
          '/goals',
          (server) => server.reply(200, []),
        );

        final goals = await apiService.getGoals();

        expect(goals, isEmpty);
      });
    });

    group('getGoal', () {
      test('returns single goal with milestones', () async {
        dioAdapter.onGet(
          '/goals/1',
          (server) => server.reply(200, {
            'id': 1,
            'user_id': 42,
            'title': 'Test Goal',
            'description': 'Description',
            'target_date': '2024-06-01T00:00:00',
            'created_at': '2024-01-15T10:30:00',
            'milestones': [
              {
                'id': 101,
                'title': 'Step 1',
                'description': null,
                'due_date': null,
                'status': 'completed',
                'order': 0,
                'created_at': '2024-01-15T10:30:00',
              },
              {
                'id': 102,
                'title': 'Step 2',
                'description': null,
                'due_date': null,
                'status': 'in_progress',
                'order': 1,
                'created_at': '2024-01-15T10:30:00',
              },
            ],
          }),
        );

        final goal = await apiService.getGoal('1');

        expect(goal.id, 1);
        expect(goal.title, 'Test Goal');
        expect(goal.milestones, hasLength(2));
        expect(goal.milestones[0].status, MilestoneStatus.completed);
        expect(goal.milestones[1].status, MilestoneStatus.inProgress);
      });

      test('throws on 404', () async {
        dioAdapter.onGet(
          '/goals/999',
          (server) => server.reply(404, {
            'detail': 'Goal with id 999 not found',
          }),
        );

        expect(
          () => apiService.getGoal('999'),
          throwsA(isA<Exception>()),
        );
      });
    });

    group('deleteGoal', () {
      test('deletes goal successfully', () async {
        dioAdapter.onDelete(
          '/goals/1',
          (server) => server.reply(204, null),
        );

        // Should not throw
        await apiService.deleteGoal('1');
      });

      test('throws on 404', () async {
        dioAdapter.onDelete(
          '/goals/999',
          (server) => server.reply(404, {
            'detail': 'Goal with id 999 not found',
          }),
        );

        expect(
          () => apiService.deleteGoal('999'),
          throwsA(isA<Exception>()),
        );
      });
    });

    group('updateMilestone', () {
      test('updates milestone status', () async {
        dioAdapter.onPatch(
          '/goals/1/milestones/101',
          (server) => server.reply(200, {
            'id': 101,
            'title': 'Step 1',
            'description': null,
            'due_date': null,
            'status': 'completed',
            'order': 0,
            'created_at': '2024-01-15T10:30:00',
          }),
          data: {'status': 'completed'},
        );

        final milestone = await apiService.updateMilestone(
          '1',
          '101',
          status: MilestoneStatus.completed,
        );

        expect(milestone.id, 101);
        expect(milestone.status, MilestoneStatus.completed);
      });
    });
  });
}

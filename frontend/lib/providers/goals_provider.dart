import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/goal.dart';
import '../models/milestone.dart';
import '../services/api_service.dart';
import 'auth_provider.dart';

// API Service provider
final apiServiceProvider = Provider<ApiService>((ref) {
  final authState = ref.watch(authStateProvider);
  return ApiService(accessToken: authState.credentials?.accessToken);
});

// Goals list provider
final goalsProvider = AsyncNotifierProvider<GoalsNotifier, List<Goal>>(() {
  return GoalsNotifier();
});

class GoalsNotifier extends AsyncNotifier<List<Goal>> {
  @override
  Future<List<Goal>> build() async {
    return _fetchGoals();
  }

  Future<List<Goal>> _fetchGoals() async {
    final apiService = ref.read(apiServiceProvider);
    return apiService.getGoals();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _fetchGoals());
  }

  Future<Goal> createGoal({
    required String title,
    String? description,
    DateTime? targetDate,
  }) async {
    final apiService = ref.read(apiServiceProvider);
    final goal = await apiService.createGoal(
      title: title,
      description: description,
      targetDate: targetDate,
    );

    // Update the list
    state = state.whenData((goals) => [...goals, goal]);

    return goal;
  }

  Future<void> deleteGoal(int id) async {
    final apiService = ref.read(apiServiceProvider);
    await apiService.deleteGoal(id.toString());

    state = state.whenData((goals) => goals.where((g) => g.id != id).toList());
  }
}

// Single goal provider
final goalProvider = FutureProvider.family<Goal, String>((ref, id) async {
  final apiService = ref.read(apiServiceProvider);
  return apiService.getGoal(id);
});

// Goal detail notifier for managing a single goal's state
final goalDetailProvider =
    AsyncNotifierProvider.family<GoalDetailNotifier, Goal, String>(() {
  return GoalDetailNotifier();
});

class GoalDetailNotifier extends FamilyAsyncNotifier<Goal, String> {
  @override
  Future<Goal> build(String arg) async {
    final apiService = ref.read(apiServiceProvider);
    return apiService.getGoal(arg);
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final apiService = ref.read(apiServiceProvider);
      return apiService.getGoal(arg);
    });
  }

  Future<void> updateMilestone(
    int milestoneId, {
    MilestoneStatus? status,
    String? title,
  }) async {
    final apiService = ref.read(apiServiceProvider);

    await apiService.updateMilestone(
      arg,
      milestoneId.toString(),
      status: status,
      title: title,
    );

    // Refresh the goal to get updated milestones
    await refresh();
  }

  Future<void> toggleMilestoneStatus(int milestoneId) async {
    final currentGoal = state.valueOrNull;
    if (currentGoal == null) return;

    final milestone = currentGoal.milestones.firstWhere(
      (m) => m.id == milestoneId,
      orElse: () => throw Exception('Milestone not found'),
    );

    final newStatus = milestone.status == MilestoneStatus.completed
        ? MilestoneStatus.pending
        : MilestoneStatus.completed;

    await updateMilestone(milestoneId, status: newStatus);
  }
}

// Create goal state
class CreateGoalState {
  final bool isLoading;
  final String? error;
  final Goal? result;

  const CreateGoalState({
    this.isLoading = false,
    this.error,
    this.result,
  });

  CreateGoalState copyWith({
    bool? isLoading,
    String? error,
    Goal? result,
  }) {
    return CreateGoalState(
      isLoading: isLoading ?? this.isLoading,
      error: error,
      result: result ?? this.result,
    );
  }
}

final createGoalProvider =
    StateNotifierProvider<CreateGoalNotifier, CreateGoalState>((ref) {
  return CreateGoalNotifier(ref);
});

class CreateGoalNotifier extends StateNotifier<CreateGoalState> {
  final Ref _ref;

  CreateGoalNotifier(this._ref) : super(const CreateGoalState());

  Future<Goal?> createGoal({
    required String title,
    String? description,
    DateTime? targetDate,
  }) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final goal = await _ref.read(goalsProvider.notifier).createGoal(
            title: title,
            description: description,
            targetDate: targetDate,
          );

      state = state.copyWith(isLoading: false, result: goal);
      return goal;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
      return null;
    }
  }

  void reset() {
    state = const CreateGoalState();
  }
}

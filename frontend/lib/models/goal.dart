import 'package:freezed_annotation/freezed_annotation.dart';
import 'milestone.dart';

part 'goal.freezed.dart';
part 'goal.g.dart';

@freezed
class Goal with _$Goal {
  const factory Goal({
    required int id,
    @JsonKey(name: 'user_id') required int userId,
    required String title,
    String? description,
    @JsonKey(name: 'target_date') DateTime? targetDate,
    @Default([]) List<Milestone> milestones,
    @JsonKey(name: 'created_at') required DateTime createdAt,
  }) = _Goal;

  factory Goal.fromJson(Map<String, dynamic> json) => _$GoalFromJson(json);
}

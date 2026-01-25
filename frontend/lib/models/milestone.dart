import 'package:freezed_annotation/freezed_annotation.dart';

part 'milestone.freezed.dart';
part 'milestone.g.dart';

enum MilestoneStatus {
  @JsonValue('pending')
  pending,
  @JsonValue('in_progress')
  inProgress,
  @JsonValue('completed')
  completed,
  @JsonValue('skipped')
  skipped,
}

@freezed
class Milestone with _$Milestone {
  const factory Milestone({
    required int id,
    required String title,
    String? description,
    @JsonKey(name: 'due_date') DateTime? dueDate,
    @Default(MilestoneStatus.pending) MilestoneStatus status,
    @Default(0) int order,
    @JsonKey(name: 'created_at') DateTime? createdAt,
  }) = _Milestone;

  factory Milestone.fromJson(Map<String, dynamic> json) =>
      _$MilestoneFromJson(json);
}

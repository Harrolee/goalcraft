// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'milestone.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$MilestoneImpl _$$MilestoneImplFromJson(Map<String, dynamic> json) =>
    _$MilestoneImpl(
      id: (json['id'] as num).toInt(),
      title: json['title'] as String,
      description: json['description'] as String?,
      dueDate: json['due_date'] == null
          ? null
          : DateTime.parse(json['due_date'] as String),
      status: $enumDecodeNullable(_$MilestoneStatusEnumMap, json['status']) ??
          MilestoneStatus.pending,
      order: (json['order'] as num?)?.toInt() ?? 0,
      createdAt: json['created_at'] == null
          ? null
          : DateTime.parse(json['created_at'] as String),
    );

Map<String, dynamic> _$$MilestoneImplToJson(_$MilestoneImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'title': instance.title,
      'description': instance.description,
      'due_date': instance.dueDate?.toIso8601String(),
      'status': _$MilestoneStatusEnumMap[instance.status]!,
      'order': instance.order,
      'created_at': instance.createdAt?.toIso8601String(),
    };

const _$MilestoneStatusEnumMap = {
  MilestoneStatus.pending: 'pending',
  MilestoneStatus.inProgress: 'in_progress',
  MilestoneStatus.completed: 'completed',
  MilestoneStatus.skipped: 'skipped',
};

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/milestone.dart';

class MilestoneTile extends StatelessWidget {
  final Milestone milestone;
  final VoidCallback? onToggle;
  final VoidCallback? onTap;

  const MilestoneTile({
    super.key,
    required this.milestone,
    this.onToggle,
    this.onTap,
  });

  Color _getStatusColor(BuildContext context) {
    switch (milestone.status) {
      case MilestoneStatus.completed:
        return Colors.green;
      case MilestoneStatus.inProgress:
        return Theme.of(context).colorScheme.primary;
      case MilestoneStatus.skipped:
        return Colors.grey;
      case MilestoneStatus.pending:
      default:
        return Theme.of(context).colorScheme.outline;
    }
  }

  IconData _getStatusIcon() {
    switch (milestone.status) {
      case MilestoneStatus.completed:
        return Icons.check_circle;
      case MilestoneStatus.inProgress:
        return Icons.pending;
      case MilestoneStatus.skipped:
        return Icons.remove_circle;
      case MilestoneStatus.pending:
      default:
        return Icons.circle_outlined;
    }
  }

  String _getStatusLabel() {
    switch (milestone.status) {
      case MilestoneStatus.completed:
        return 'Completed';
      case MilestoneStatus.inProgress:
        return 'In Progress';
      case MilestoneStatus.skipped:
        return 'Skipped';
      case MilestoneStatus.pending:
      default:
        return 'Pending';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isCompleted = milestone.status == MilestoneStatus.completed;
    final statusColor = _getStatusColor(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Checkbox / Status Icon
              InkWell(
                onTap: onToggle,
                borderRadius: BorderRadius.circular(20),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    _getStatusIcon(),
                    size: 28,
                    color: statusColor,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      milestone.title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            decoration: isCompleted
                                ? TextDecoration.lineThrough
                                : null,
                            color: isCompleted
                                ? Theme.of(context)
                                    .colorScheme
                                    .onSurface
                                    .withOpacity(0.5)
                                : null,
                          ),
                    ),
                    if (milestone.description != null &&
                        milestone.description!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        milestone.description!,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: isCompleted
                                  ? Theme.of(context)
                                      .colorScheme
                                      .onSurface
                                      .withOpacity(0.4)
                                  : Theme.of(context)
                                      .colorScheme
                                      .onSurface
                                      .withOpacity(0.7),
                            ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _StatusBadge(
                          label: _getStatusLabel(),
                          color: statusColor,
                        ),
                        if (milestone.dueDate != null) ...[
                          const SizedBox(width: 8),
                          Icon(
                            Icons.calendar_today_outlined,
                            size: 14,
                            color: _isDueSoon(milestone.dueDate!)
                                ? Colors.orange
                                : Theme.of(context)
                                    .colorScheme
                                    .onSurface
                                    .withOpacity(0.5),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            DateFormat.MMMd().format(milestone.dueDate!),
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: _isDueSoon(milestone.dueDate!)
                                          ? Colors.orange
                                          : Theme.of(context)
                                              .colorScheme
                                              .onSurface
                                              .withOpacity(0.5),
                                    ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool _isDueSoon(DateTime dueDate) {
    final now = DateTime.now();
    final difference = dueDate.difference(now).inDays;
    return difference <= 3 && difference >= 0;
  }
}

class _StatusBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusBadge({
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w500,
              fontSize: 11,
            ),
      ),
    );
  }
}

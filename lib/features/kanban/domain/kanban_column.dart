import 'package:kpi_drive_app/features/kanban/domain/kanban_task.dart';

class KanbanColumn {
  const KanbanColumn({
    required this.parentId,
    required this.title,
    required this.subtitle,
    required this.tasks,
  });

  final int? parentId;
  final String title;
  final String subtitle;
  final List<KanbanTask> tasks;

  KanbanColumn copyWith({
    Object? parentId = _columnSentinel,
    String? title,
    String? subtitle,
    List<KanbanTask>? tasks,
  }) {
    return KanbanColumn(
      parentId:
          identical(parentId, _columnSentinel) ? this.parentId : parentId as int?,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      tasks: tasks ?? this.tasks,
    );
  }
}

const _columnSentinel = Object();

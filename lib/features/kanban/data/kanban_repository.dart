import 'package:kpi_drive_app/features/kanban/data/kanban_api_service.dart';
import 'package:kpi_drive_app/features/kanban/domain/kanban_column.dart';
import 'package:kpi_drive_app/features/kanban/domain/kanban_load_result.dart';
import 'package:kpi_drive_app/features/kanban/domain/kanban_task.dart';

class KanbanRepository {
  KanbanRepository({required this.apiService});

  final KanbanApiService apiService;

  Future<KanbanLoadResult> fetchBoard() async {
    final response = await apiService.loadTasks();

    switch (response.mode) {
      case LoadTasksMode.success:
        return KanbanLoadResult.success(
          columns: _groupTasks(response.tasks),
          rawSnippet: response.rawSnippet,
        );
      case LoadTasksMode.unknownFormat:
        return KanbanLoadResult.unknownFormat(
          message: response.message!,
          rawSnippet: response.rawSnippet,
        );
      case LoadTasksMode.error:
        return KanbanLoadResult.error(
          message: response.message!,
          rawSnippet: response.rawSnippet,
        );
    }
  }

  Future<void> saveParentId({
    required int taskId,
    required int? parentId,
  }) {
    return apiService.saveTaskField(
      taskId: taskId,
      fieldName: 'parent_id',
      fieldValue: parentId?.toString() ?? '',
    );
  }

  Future<void> saveOrder({
    required int taskId,
    required int order,
  }) {
    return apiService.saveTaskField(
      taskId: taskId,
      fieldName: 'order',
      fieldValue: order.toString(),
    );
  }

  List<KanbanColumn> _groupTasks(List<KanbanTask> tasks) {
    final grouped = <int?, List<KanbanTask>>{};

    for (final task in tasks) {
      grouped.putIfAbsent(task.parentId, () => <KanbanTask>[]).add(task);
    }

    final columns = grouped.entries.map((entry) {
      final sortedTasks = [...entry.value]
        ..sort((left, right) {
          final orderCompare = left.order.compareTo(right.order);
          if (orderCompare != 0) {
            return orderCompare;
          }
          return (left.id ?? 0).compareTo(right.id ?? 0);
        });

      if (entry.key == null) {
        return KanbanColumn(
          parentId: null,
          title: 'Без папки',
          subtitle: 'parent_id отсутствует',
          tasks: sortedTasks,
        );
      }

      return KanbanColumn(
        parentId: entry.key,
        title: 'Папка ${entry.key}',
        subtitle: 'parent_id: ${entry.key}',
        tasks: sortedTasks,
      );
    }).toList()
      ..sort((left, right) {
        if (left.parentId == null) {
          return 1;
        }
        if (right.parentId == null) {
          return -1;
        }
        return left.parentId!.compareTo(right.parentId!);
      });

    return columns;
  }
}

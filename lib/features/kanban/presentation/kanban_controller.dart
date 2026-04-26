import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:kpi_drive_app/features/kanban/data/kanban_repository.dart';
import 'package:kpi_drive_app/features/kanban/domain/kanban_column.dart';
import 'package:kpi_drive_app/features/kanban/domain/kanban_load_result.dart';
import 'package:kpi_drive_app/features/kanban/domain/kanban_task.dart';

class KanbanController extends ChangeNotifier {
  KanbanController({required this.repository});

  final KanbanRepository repository;

  BoardViewState _viewState = BoardViewState.loading;
  List<KanbanColumn> _columns = const [];
  String? _message;
  String _diagnosticSnippet = '';
  DateTime? _lastUpdatedAt;
  final Map<int, TaskSaveState> _taskSaveStates = <int, TaskSaveState>{};
  UiNotice? _pendingNotice;
  bool _isDemoMode = false;
  bool _isSavingChanges = false;

  BoardViewState get viewState => _viewState;
  List<KanbanColumn> get columns => _columns;
  String? get message => _message;
  String get diagnosticSnippet => _diagnosticSnippet;
  DateTime? get lastUpdatedAt => _lastUpdatedAt;
  bool get isLoading => _viewState == BoardViewState.loading;
  bool get isReady => _viewState == BoardViewState.ready;
  bool get isDemoMode => _isDemoMode;
  bool get isSavingChanges => _isSavingChanges;

  TaskSaveState taskStateFor(int? taskId) {
    if (taskId == null) {
      return TaskSaveState.idle;
    }
    return _taskSaveStates[taskId] ?? TaskSaveState.idle;
  }

  bool isTaskLocked(int? taskId) =>
      _isSavingChanges || taskStateFor(taskId) == TaskSaveState.saving;

  UiNotice? consumeNotice() {
    final notice = _pendingNotice;
    _pendingNotice = null;
    return notice;
  }

  void notifySaveInProgress() {
    _emitNotice(
      const UiNotice(
        text: 'Дождитесь завершения сохранения.',
        type: NoticeType.info,
      ),
    );
    notifyListeners();
  }

  Future<void> load() async {
    _viewState = BoardViewState.loading;
    _message = null;
    _isSavingChanges = false;
    _taskSaveStates.clear();
    notifyListeners();

    try {
      final result = await repository.fetchBoard();
      _diagnosticSnippet = result.rawSnippet;

      switch (result.mode) {
        case KanbanLoadMode.success:
          _columns = _normalizeColumns(result.columns);
          _viewState = BoardViewState.ready;
          _message = _columns.isEmpty
              ? 'API ответил успешно, но список задач пуст.'
              : null;
          _isDemoMode = false;
          _lastUpdatedAt = DateTime.now();
          break;
        case KanbanLoadMode.error:
          _columns = const [];
          _viewState = BoardViewState.error;
          _message = result.message;
          break;
        case KanbanLoadMode.unknownFormat:
          _columns = const [];
          _viewState = BoardViewState.diagnostic;
          _message = result.message;
          break;
      }
    } catch (error) {
      _columns = const [];
      _viewState = BoardViewState.error;
      _message = error.toString();
    } finally {
      notifyListeners();
    }
  }

  void showDemoBoard() {
    _columns = _buildDemoColumns();
    _viewState = BoardViewState.ready;
    _isDemoMode = true;
    _message =
        'Показана демо-доска. Основной режим приложения работает с реальным API.';
    _emitNotice(
      const UiNotice(
        text: 'Включена демо-доска вместо внешнего API.',
        type: NoticeType.info,
      ),
    );
    notifyListeners();
  }

  Future<void> moveTask({
    required int taskId,
    required int? targetParentId,
    required int targetIndex,
  }) async {
    final movedTask = _findTask(taskId);
    if (movedTask == null || movedTask.id == null) {
      return;
    }

    if (_isSavingChanges) {
      notifySaveInProgress();
      return;
    }

    if (movedTask.parentId != targetParentId &&
        _wouldCreateParentCycle(taskId, targetParentId)) {
      _emitNotice(
        const UiNotice(
          text: 'Нельзя переместить задачу в собственную дочернюю папку.',
          type: NoticeType.error,
        ),
      );
      notifyListeners();
      return;
    }

    final previousColumns = _cloneColumns(_columns);
    final updatedColumns = _buildMovedColumns(
      source: previousColumns,
      taskId: taskId,
      targetParentId: targetParentId,
      targetIndex: targetIndex,
    );

    if (_areColumnsEqual(previousColumns, updatedColumns)) {
      return;
    }

    final movedTaskAfter = _findTaskInColumns(updatedColumns, taskId);
    if (movedTaskAfter == null || movedTaskAfter.id == null) {
      return;
    }

    _columns = updatedColumns;
    _isSavingChanges = true;
    _taskSaveStates[taskId] = TaskSaveState.saving;
    _emitNotice(
      const UiNotice(
        text: 'Сохранение изменений...',
        type: NoticeType.info,
      ),
    );
    notifyListeners();

    var shouldClearSavedStateLater = false;

    try {
      if (movedTask.parentId != movedTaskAfter.parentId) {
        await repository.saveParentId(
          taskId: movedTaskAfter.id!,
          parentId: movedTaskAfter.parentId,
        );
      }

      await repository.saveOrder(
        taskId: movedTaskAfter.id!,
        order: movedTaskAfter.order,
      );

      await _syncBoardFromBackend(fallbackColumns: updatedColumns);

      _taskSaveStates[taskId] = TaskSaveState.saved;
      _lastUpdatedAt = DateTime.now();
      _emitNotice(
        const UiNotice(
          text: 'Изменения сохранены.',
          type: NoticeType.success,
        ),
      );
      shouldClearSavedStateLater = true;
    } catch (error) {
      _columns = previousColumns;
      _taskSaveStates.remove(taskId);
      _emitNotice(
        UiNotice(
          text: 'Не удалось сохранить изменения. ${error.toString()}',
          type: NoticeType.error,
        ),
      );
    } finally {
      _isSavingChanges = false;
      notifyListeners();

      if (shouldClearSavedStateLater) {
        unawaited(_clearSavedState(taskId));
      }
    }
  }

  Future<void> _syncBoardFromBackend({
    required List<KanbanColumn> fallbackColumns,
  }) async {
    try {
      final result = await repository.fetchBoard();
      _diagnosticSnippet = result.rawSnippet;

      if (result.mode == KanbanLoadMode.success) {
        _columns = _normalizeColumns(result.columns);
        _viewState = BoardViewState.ready;
        _message = _columns.isEmpty
            ? 'API ответил успешно, но список задач пуст.'
            : null;
        _isDemoMode = false;
        return;
      }
    } catch (_) {
      // Keep the optimistic board state when post-save sync is temporarily unavailable.
    }

    _columns = fallbackColumns;
  }

  Future<void> _clearSavedState(int taskId) async {
    await Future<void>.delayed(const Duration(seconds: 2));
    if (_taskSaveStates[taskId] == TaskSaveState.saved) {
      _taskSaveStates.remove(taskId);
      notifyListeners();
    }
  }

  bool _wouldCreateParentCycle(int taskId, int? targetParentId) {
    if (targetParentId == null) {
      return false;
    }

    final parentByTaskId = <int, int?>{};
    for (final column in _columns) {
      for (final task in column.tasks) {
        if (task.id != null) {
          parentByTaskId[task.id!] = task.parentId;
        }
      }
    }

    int? cursor = targetParentId;
    final visited = <int>{};

    while (cursor != null && visited.add(cursor)) {
      if (cursor == taskId) {
        return true;
      }
      cursor = parentByTaskId[cursor];
    }

    return false;
  }

  List<KanbanColumn> _buildMovedColumns({
    required List<KanbanColumn> source,
    required int taskId,
    required int? targetParentId,
    required int targetIndex,
  }) {
    final columns = _cloneColumns(source);

    var sourceColumnIndex = -1;
    var sourceTaskIndex = -1;
    KanbanTask? task;

    for (var columnIndex = 0; columnIndex < columns.length; columnIndex++) {
      final taskIndex =
          columns[columnIndex].tasks.indexWhere((item) => item.id == taskId);
      if (taskIndex != -1) {
        sourceColumnIndex = columnIndex;
        sourceTaskIndex = taskIndex;
        task = columns[columnIndex].tasks[taskIndex];
        break;
      }
    }

    if (task == null) {
      return source;
    }

    final targetColumnIndex =
        columns.indexWhere((column) => column.parentId == targetParentId);
    if (targetColumnIndex == -1) {
      return source;
    }

    final sourceTasks = [...columns[sourceColumnIndex].tasks]..removeAt(sourceTaskIndex);

    final targetTasks = sourceColumnIndex == targetColumnIndex
        ? sourceTasks
        : [...columns[targetColumnIndex].tasks];

    var insertionIndex = targetIndex.clamp(0, targetTasks.length);
    if (sourceColumnIndex == targetColumnIndex && sourceTaskIndex < insertionIndex) {
      insertionIndex -= 1;
    }

    final movedTask = task.copyWith(parentId: targetParentId);
    targetTasks.insert(insertionIndex, movedTask);

    columns[sourceColumnIndex] = columns[sourceColumnIndex].copyWith(
      tasks: _reorderTasks(sourceColumnIndex == targetColumnIndex ? targetTasks : sourceTasks),
    );

    if (sourceColumnIndex != targetColumnIndex) {
      columns[targetColumnIndex] = columns[targetColumnIndex].copyWith(
        tasks: _reorderTasks(targetTasks),
      );
    }

    return columns;
  }

  List<KanbanTask> _reorderTasks(List<KanbanTask> tasks) {
    return [
      for (var index = 0; index < tasks.length; index++)
        tasks[index].copyWith(order: index + 1),
    ];
  }

  KanbanTask? _findTask(int taskId) => _findTaskInColumns(_columns, taskId);

  KanbanTask? _findTaskInColumns(List<KanbanColumn> columns, int taskId) {
    for (final column in columns) {
      for (final task in column.tasks) {
        if (task.id == taskId) {
          return task;
        }
      }
    }
    return null;
  }

  List<KanbanColumn> _normalizeColumns(List<KanbanColumn> input) {
    return input
        .map(
          (column) => column.copyWith(
            tasks: _reorderTasks([...column.tasks]..sort((a, b) => a.order.compareTo(b.order))),
          ),
        )
        .toList();
  }

  List<KanbanColumn> _cloneColumns(List<KanbanColumn> source) {
    return source
        .map(
          (column) => column.copyWith(
            tasks: column.tasks.map((task) => task.copyWith()).toList(),
          ),
        )
        .toList();
  }

  bool _areColumnsEqual(List<KanbanColumn> left, List<KanbanColumn> right) {
    if (left.length != right.length) {
      return false;
    }

    for (var i = 0; i < left.length; i++) {
      if (left[i].parentId != right[i].parentId ||
          left[i].tasks.length != right[i].tasks.length) {
        return false;
      }

      for (var j = 0; j < left[i].tasks.length; j++) {
        final leftTask = left[i].tasks[j];
        final rightTask = right[i].tasks[j];
        if (leftTask.id != rightTask.id ||
            leftTask.parentId != rightTask.parentId ||
            leftTask.order != rightTask.order) {
          return false;
        }
      }
    }

    return true;
  }

  List<KanbanColumn> _buildDemoColumns() {
    final columns = [
      KanbanColumn(
        parentId: 4255,
        title: 'Папка 4255',
        subtitle: 'parent_id: 4255',
        tasks: const [
          KanbanTask(id: 1001, parentId: 4255, name: 'Результат', order: 1),
          KanbanTask(id: 1002, parentId: 4255, name: 'Оценка руководителя', order: 2),
          KanbanTask(id: 1003, parentId: 4255, name: 'Задачи', order: 3),
        ],
      ),
      KanbanColumn(
        parentId: 4257,
        title: 'Папка 4257',
        subtitle: 'parent_id: 4257',
        tasks: const [
          KanbanTask(
            id: 2001,
            parentId: 4257,
            name: 'Выставленные счета на семинары',
            order: 1,
          ),
          KanbanTask(
            id: 2002,
            parentId: 4257,
            name: 'Приход по открытым семинарам',
            order: 2,
          ),
          KanbanTask(id: 2003, parentId: 4257, name: 'Оплата', order: 3),
        ],
      ),
      KanbanColumn(
        parentId: 318139,
        title: 'Папка 318139',
        subtitle: 'parent_id: 318139',
        tasks: const [
          KanbanTask(id: 3001, parentId: 318139, name: 'Прирост платных клиентов', order: 1),
          KanbanTask(id: 3002, parentId: 318139, name: 'Оклад', order: 2),
          KanbanTask(id: 3003, parentId: 318139, name: 'Премия', order: 3),
        ],
      ),
    ];

    return _normalizeColumns(columns);
  }

  void _emitNotice(UiNotice notice) {
    _pendingNotice = notice;
  }
}

enum BoardViewState {
  loading,
  ready,
  error,
  diagnostic,
}

enum TaskSaveState {
  idle,
  saving,
  saved,
}

class UiNotice {
  const UiNotice({
    required this.text,
    required this.type,
  });

  final String text;
  final NoticeType type;
}

enum NoticeType {
  info,
  success,
  error,
}

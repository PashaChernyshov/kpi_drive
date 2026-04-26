import 'package:kpi_drive_app/features/kanban/domain/kanban_column.dart';

class KanbanLoadResult {
  const KanbanLoadResult.success({
    required this.columns,
    required this.rawSnippet,
  })  : mode = KanbanLoadMode.success,
        message = null;

  const KanbanLoadResult.error({
    required this.message,
    required this.rawSnippet,
  })  : mode = KanbanLoadMode.error,
        columns = const [];

  const KanbanLoadResult.unknownFormat({
    required this.message,
    required this.rawSnippet,
  })  : mode = KanbanLoadMode.unknownFormat,
        columns = const [];

  final KanbanLoadMode mode;
  final List<KanbanColumn> columns;
  final String? message;
  final String rawSnippet;

  bool get isSuccess => mode == KanbanLoadMode.success;
}

enum KanbanLoadMode {
  success,
  error,
  unknownFormat,
}

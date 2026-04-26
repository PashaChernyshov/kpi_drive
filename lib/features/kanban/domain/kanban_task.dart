class KanbanTask {
  const KanbanTask({
    required this.id,
    required this.parentId,
    required this.name,
    required this.order,
  });

  final int? id;
  final int? parentId;
  final String name;
  final int order;

  factory KanbanTask.fromJson(Map<String, dynamic> json) {
    final rawName = json['name'];
    final taskName = rawName is String && rawName.trim().isNotEmpty
        ? rawName.trim()
        : 'Без названия';

    return KanbanTask(
      id: _toInt(json['indicator_to_mo_id']),
      parentId: _toInt(json['parent_id']),
      name: taskName,
      order: _toInt(json['order']) ?? 0,
    );
  }

  KanbanTask copyWith({
    int? id,
    Object? parentId = _sentinel,
    String? name,
    int? order,
  }) {
    return KanbanTask(
      id: id ?? this.id,
      parentId: identical(parentId, _sentinel) ? this.parentId : parentId as int?,
      name: name ?? this.name,
      order: order ?? this.order,
    );
  }

  static int? _toInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is double) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value.trim());
    }
    return null;
  }
}

const _sentinel = Object();

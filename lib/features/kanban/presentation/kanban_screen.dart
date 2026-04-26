import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:kpi_drive_app/features/kanban/domain/kanban_column.dart';
import 'package:kpi_drive_app/features/kanban/domain/kanban_task.dart';
import 'package:kpi_drive_app/features/kanban/presentation/kanban_controller.dart';

class KanbanScreen extends StatefulWidget {
  const KanbanScreen({super.key, required this.controller});

  final KanbanController controller;

  @override
  State<KanbanScreen> createState() => _KanbanScreenState();
}

class _KanbanScreenState extends State<KanbanScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.controller.load();
    });
  }

  @override
  void dispose() {
    widget.controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _flushNotice());

        return Scaffold(
          backgroundColor: const Color(0xFF020202),
          body: SafeArea(
            child: Column(
              children: [
                _TopToolbar(controller: widget.controller),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                    child: _buildMainContent(),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _flushNotice() {
    final notice = widget.controller.consumeNotice();
    if (notice == null || !mounted) {
      return;
    }

    final color = switch (notice.type) {
      NoticeType.info => const Color(0xFF1C2532),
      NoticeType.success => const Color(0xFF123126),
      NoticeType.error => const Color(0xFF3A1820),
    };

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(notice.text),
          behavior: SnackBarBehavior.floating,
          backgroundColor: color,
          duration: const Duration(seconds: 3),
        ),
      );
  }

  Widget _buildMainContent() {
    switch (widget.controller.viewState) {
      case BoardViewState.loading:
        return _WorkspaceShell(
          child: const _InlineStatusPanel(
            title: 'Загрузка задач',
            subtitle: 'Получаем данные KPI-DRIVE через локальный proxy.',
            diagnosticSnippet: '',
            showDemoAction: false,
          ),
        );
      case BoardViewState.error:
        return _WorkspaceShell(
          child: _InlineStatusPanel(
            title: 'Не удалось загрузить доску',
            subtitle: widget.controller.message ?? 'Неизвестная ошибка',
            diagnosticSnippet: widget.controller.diagnosticSnippet,
            showDemoAction: true,
            onShowDemo: widget.controller.showDemoBoard,
            onRetry: widget.controller.load,
          ),
        );
      case BoardViewState.diagnostic:
        return _WorkspaceShell(
          child: _InlineStatusPanel(
            title: 'Формат ответа не распознан',
            subtitle: widget.controller.message ?? '',
            diagnosticSnippet: widget.controller.diagnosticSnippet,
            showDemoAction: true,
            onShowDemo: widget.controller.showDemoBoard,
            onRetry: widget.controller.load,
          ),
        );
      case BoardViewState.ready:
        return _BoardWorkspace(controller: widget.controller);
    }
  }
}

class _TopToolbar extends StatelessWidget {
  const _TopToolbar({required this.controller});

  final KanbanController controller;

  @override
  Widget build(BuildContext context) {
    final totalTasks = controller.columns.fold<int>(
      0,
      (sum, column) => sum + column.tasks.length,
    );

    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: Color(0xFF050505),
        border: Border(
          bottom: BorderSide(color: Color(0xFF2A2A2A)),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 20,
            height: 20,
            decoration: const BoxDecoration(
              color: Color(0xFF19C37D),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          const Text(
            'Задачи KPI-DRIVE',
            style: TextStyle(
              color: Color(0xFFF1F1F1),
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 12),
          _ToolbarBadge(label: 'Колонок: ${controller.columns.length}'),
          const SizedBox(width: 6),
          _ToolbarBadge(label: 'Задач: $totalTasks'),
          if (controller.isSavingChanges) ...[
            const SizedBox(width: 6),
            const _ToolbarBadge(
              label: 'Сохранение изменений...',
              color: Color(0xFF1C1710),
              borderColor: Color(0xFF5B4A1E),
              textColor: Color(0xFFF5C15E),
            ),
          ],
          if (controller.isDemoMode) ...[
            const SizedBox(width: 6),
            const _ToolbarBadge(
              label: 'Демо режим',
              color: Color(0xFF1C1710),
              borderColor: Color(0xFF4C3A17),
              textColor: Color(0xFFE8C16E),
            ),
          ],
          const Spacer(),
          Text(
            controller.lastUpdatedAt == null
                ? 'Нет обновления'
                : 'Обновлено ${_formatTime(controller.lastUpdatedAt!)}',
            style: const TextStyle(
              color: Color(0xFF8A8A8A),
              fontSize: 11,
            ),
          ),
          const SizedBox(width: 10),
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: ElevatedButton.icon(
              onPressed: controller.isLoading ? null : controller.load,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0B0B0B),
                foregroundColor: const Color(0xFFF1F1F1),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(2),
                  side: const BorderSide(color: Color(0xFF333333)),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              ),
              icon: controller.isLoading
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded, size: 16),
              label: Text(controller.isLoading ? 'Загрузка' : 'Обновить'),
            ),
          ),
        ],
      ),
    );
  }

  static String _formatTime(DateTime value) {
    final hours = value.hour.toString().padLeft(2, '0');
    final minutes = value.minute.toString().padLeft(2, '0');
    return '$hours:$minutes';
  }
}

class _ToolbarBadge extends StatelessWidget {
  const _ToolbarBadge({
    required this.label,
    this.color = const Color(0xFF101010),
    this.borderColor = const Color(0xFF2F2F2F),
    this.textColor = const Color(0xFFB2B2B2),
  });

  final String label;
  final Color color;
  final Color borderColor;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(2),
        border: Border.all(color: borderColor),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: textColor,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _WorkspaceShell extends StatelessWidget {
  const _WorkspaceShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF050505),
        borderRadius: BorderRadius.circular(2),
        border: Border.all(color: const Color(0xFF2A2A2A)),
      ),
      child: child,
    );
  }
}

class _InlineStatusPanel extends StatelessWidget {
  const _InlineStatusPanel({
    required this.title,
    required this.subtitle,
    required this.diagnosticSnippet,
    required this.showDemoAction,
    this.onShowDemo,
    this.onRetry,
  });

  final String title;
  final String subtitle;
  final String diagnosticSnippet;
  final bool showDemoAction;
  final VoidCallback? onShowDemo;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFFE6EBF2),
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: const TextStyle(
              color: Color(0xFF9BA6B8),
              fontSize: 13,
              height: 1.4,
            ),
          ),
          if (diagnosticSnippet.isNotEmpty) ...[
            const SizedBox(height: 14),
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF090909),
                  borderRadius: BorderRadius.circular(2),
                  border: Border.all(color: const Color(0xFF303030)),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    diagnosticSnippet,
                    style: const TextStyle(
                      color: Color(0xFF7FD5A1),
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              if (onRetry != null)
                _DarkActionButton(
                  label: 'Повторить',
                  onPressed: onRetry!,
                ),
              if (showDemoAction && onShowDemo != null)
                _DarkActionButton(
                  label: 'Показать демо-доску',
                  onPressed: onShowDemo!,
                  accent: true,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DarkActionButton extends StatelessWidget {
  const _DarkActionButton({
    required this.label,
    required this.onPressed,
    this.accent = false,
  });

  final String label;
  final VoidCallback onPressed;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor:
              accent ? const Color(0xFF101A12) : const Color(0xFF0B0B0B),
          foregroundColor:
              accent ? const Color(0xFF9BE7BB) : const Color(0xFFE6E6E6),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(2),
            side: BorderSide(
              color: accent ? const Color(0xFF285F45) : const Color(0xFF333333),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
        child: Text(label),
      ),
    );
  }
}

class _BoardWorkspace extends StatelessWidget {
  const _BoardWorkspace({required this.controller});

  final KanbanController controller;

  @override
  Widget build(BuildContext context) {
    return _WorkspaceShell(
      child: Column(
        children: [
          if (controller.message != null && controller.message!.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: Color(0xFF1B222C)),
                ),
              ),
              child: Text(
                controller.message!,
                style: TextStyle(
                  color: controller.isDemoMode
                      ? const Color(0xFFF3C96B)
                      : const Color(0xFF95A0B3),
                  fontSize: 12,
                ),
              ),
            ),
          Expanded(
            child: ScrollConfiguration(
              behavior: const MaterialScrollBehavior().copyWith(
                dragDevices: {
                  PointerDeviceKind.mouse,
                  PointerDeviceKind.touch,
                  PointerDeviceKind.trackpad,
                  PointerDeviceKind.stylus,
                },
              ),
              child: ListView.separated(
                padding: const EdgeInsets.all(6),
                scrollDirection: Axis.horizontal,
                itemCount: controller.columns.length,
                separatorBuilder: (_, _) => const SizedBox(width: 6),
                itemBuilder: (context, index) {
                  final column = controller.columns[index];
                  return SizedBox(
                    width: 274,
                    child: _KanbanColumnWidget(
                      column: column,
                      controller: controller,
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _KanbanColumnWidget extends StatelessWidget {
  const _KanbanColumnWidget({
    required this.column,
    required this.controller,
  });

  final KanbanColumn column;
  final KanbanController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF090909),
        borderRadius: BorderRadius.circular(2),
        border: Border.all(color: const Color(0xFF2E2E2E)),
      ),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Color(0xFF2A2A2A)),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        column.title,
                        style: const TextStyle(
                          color: Color(0xFFF0F0F0),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Text(
                      '${column.tasks.length}',
                      style: const TextStyle(
                        color: Color(0xFF28D17C),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  column.subtitle,
                  style: const TextStyle(
                    color: Color(0xFF7C7C7C),
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(6),
              itemCount: column.tasks.length + 1,
              itemBuilder: (context, slotIndex) {
                final widgets = <Widget>[
                  _DropZone(
                    column: column,
                    controller: controller,
                    insertionIndex: slotIndex,
                  ),
                ];

                if (slotIndex < column.tasks.length) {
                  widgets.add(
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: _CardDropTarget(
                        column: column,
                        controller: controller,
                        taskIndex: slotIndex,
                        task: column.tasks[slotIndex],
                        child: _TaskDraggableCard(
                          task: column.tasks[slotIndex],
                          controller: controller,
                        ),
                      ),
                    ),
                  );
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: widgets,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

enum _CardDropSide {
  none,
  before,
  after,
}

class _CardDropTarget extends StatefulWidget {
  const _CardDropTarget({
    required this.column,
    required this.controller,
    required this.taskIndex,
    required this.task,
    required this.child,
  });

  final KanbanColumn column;
  final KanbanController controller;
  final int taskIndex;
  final KanbanTask task;
  final Widget child;

  @override
  State<_CardDropTarget> createState() => _CardDropTargetState();
}

class _CardDropTargetState extends State<_CardDropTarget> {
  _CardDropSide _dropSide = _CardDropSide.none;

  @override
  Widget build(BuildContext context) {
    return DragTarget<_DragTaskPayload>(
      onWillAcceptWithDetails: (details) {
        if (widget.controller.isSavingChanges) {
          widget.controller.notifySaveInProgress();
          return false;
        }
        if (widget.controller.isTaskLocked(details.data.task.id)) {
          return false;
        }
        _updateDropSide(details.offset);
        return true;
      },
      onMove: (details) => _updateDropSide(details.offset),
      onLeave: (_) => setState(() => _dropSide = _CardDropSide.none),
      onAcceptWithDetails: (details) {
        final targetIndex =
            _dropSide == _CardDropSide.before ? widget.taskIndex : widget.taskIndex + 1;
        setState(() => _dropSide = _CardDropSide.none);
        widget.controller.moveTask(
          taskId: details.data.task.id!,
          targetParentId: widget.column.parentId,
          targetIndex: targetIndex,
        );
      },
      builder: (context, candidateData, rejectedData) {
        final highlightTop = _dropSide == _CardDropSide.before;
        final highlightBottom = _dropSide == _CardDropSide.after;

        return Stack(
          children: [
            widget.child,
            Positioned(
              left: 0,
              right: 0,
              top: -1,
              height: 6,
              child: IgnorePointer(
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 180),
                  opacity: highlightTop ? 1 : 0,
                  child: Container(
                    alignment: Alignment.topCenter,
                    child: Container(
                      height: 2,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      color: const Color(0xFF19C37D),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: -1,
              height: 6,
              child: IgnorePointer(
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 180),
                  opacity: highlightBottom ? 1 : 0,
                  child: Container(
                    alignment: Alignment.bottomCenter,
                    child: Container(
                      height: 2,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      color: const Color(0xFF19C37D),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _updateDropSide(Offset globalOffset) {
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox) {
      return;
    }

    final localOffset = renderObject.globalToLocal(globalOffset);
    final nextSide = localOffset.dy <= renderObject.size.height / 2
        ? _CardDropSide.before
        : _CardDropSide.after;

    if (nextSide != _dropSide) {
      setState(() => _dropSide = nextSide);
    }
  }
}

class _DropZone extends StatefulWidget {
  const _DropZone({
    required this.column,
    required this.controller,
    required this.insertionIndex,
  });

  final KanbanColumn column;
  final KanbanController controller;
  final int insertionIndex;

  @override
  State<_DropZone> createState() => _DropZoneState();
}

class _DropZoneState extends State<_DropZone> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    return DragTarget<_DragTaskPayload>(
      onWillAcceptWithDetails: (details) {
        if (widget.controller.isSavingChanges) {
          widget.controller.notifySaveInProgress();
          return false;
        }
        if (widget.controller.isTaskLocked(details.data.task.id)) {
          return false;
        }
        setState(() => _isHovering = true);
        return true;
      },
      onLeave: (_) => setState(() => _isHovering = false),
      onAcceptWithDetails: (details) {
        setState(() => _isHovering = false);
        widget.controller.moveTask(
          taskId: details.data.task.id!,
          targetParentId: widget.column.parentId,
          targetIndex: widget.insertionIndex,
        );
      },
      builder: (context, candidateData, rejectedData) {
        final hasCandidate = candidateData.isNotEmpty;
        final isActive = _isHovering || hasCandidate;

        return AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: isActive ? 12 : 8,
          margin: EdgeInsets.only(bottom: widget.insertionIndex == 0 ? 3 : 1),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(1),
          ),
          alignment: Alignment.center,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            height: 2,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            color: isActive ? const Color(0xFF19C37D) : Colors.transparent,
          ),
        );
      },
    );
  }
}

class _TaskDraggableCard extends StatelessWidget {
  const _TaskDraggableCard({
    required this.task,
    required this.controller,
  });

  final KanbanTask task;
  final KanbanController controller;

  @override
  Widget build(BuildContext context) {
    final saveState = controller.taskStateFor(task.id);
    final card = _TaskCard(
      task: task,
      saveState: saveState,
      isDisabled: controller.isSavingChanges,
    );

    if (controller.isSavingChanges) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => controller.notifySaveInProgress(),
        onPanStart: (_) => controller.notifySaveInProgress(),
        child: card,
      );
    }

    if (controller.isTaskLocked(task.id) || task.id == null) {
      return card;
    }

    return Draggable<_DragTaskPayload>(
      data: _DragTaskPayload(task: task),
      feedback: Material(
        color: Colors.transparent,
        child: SizedBox(
          width: 258,
          child: Opacity(opacity: 0.95, child: card),
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.35,
        child: card,
      ),
      child: card,
    );
  }
}

class _TaskCard extends StatefulWidget {
  const _TaskCard({
    required this.task,
    required this.saveState,
    required this.isDisabled,
  });

  final KanbanTask task;
  final TaskSaveState saveState;
  final bool isDisabled;

  @override
  State<_TaskCard> createState() => _TaskCardState();
}

class _TaskCardState extends State<_TaskCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final markerColor = _resolveMarkerColor(widget.task.id ?? 0);
    final statusText = switch (widget.saveState) {
      TaskSaveState.saving => 'Сохранение...',
      TaskSaveState.saved => 'Сохранено',
      TaskSaveState.idle => 'order ${widget.task.order}',
    };

    return MouseRegion(
      cursor: widget.saveState == TaskSaveState.saving || widget.isDisabled
          ? SystemMouseCursors.basic
          : SystemMouseCursors.grab,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 80),
        decoration: BoxDecoration(
          color: widget.isDisabled
              ? const Color(0xFF0A0A0A)
              : _hovered
                  ? const Color(0xFF111111)
                  : const Color(0xFF0D0D0D),
          borderRadius: BorderRadius.circular(2),
          border: Border.all(
            color: widget.isDisabled
                ? const Color(0xFF262626)
                : _hovered
                ? const Color(0xFF3A3A3A)
                : const Color(0xFF2E2E2E),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(8, 7, 8, 7),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _TriangleMarker(color: markerColor),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.task.name,
                    style: const TextStyle(
                      color: Color(0xFFEDEDED),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      Text(
                        'id ${widget.task.id ?? '—'}',
                        style: const TextStyle(
                          color: Color(0xFF808080),
                          fontSize: 10,
                        ),
                      ),
                      Text(
                        statusText,
                        style: TextStyle(
                          color: widget.saveState == TaskSaveState.saved
                              ? const Color(0xFF5ED48E)
                              : widget.saveState == TaskSaveState.saving
                                  ? const Color(0xFFF5C15E)
                                  : const Color(0xFF808080),
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const _KpiIndicator(),
          ],
        ),
      ),
    );
  }

  Color _resolveMarkerColor(int seed) {
    const colors = [
      Color(0xFF3B82F6),
      Color(0xFF22C55E),
      Color(0xFFFACC15),
      Color(0xFFEF4444),
    ];
    return colors[seed.abs() % colors.length];
  }
}

class _TriangleMarker extends StatelessWidget {
  const _TriangleMarker({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(12, 14),
      painter: _TrianglePainter(color: color),
    );
  }
}

class _TrianglePainter extends CustomPainter {
  const _TrianglePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, size.height / 2)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _TrianglePainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

class _KpiIndicator extends StatelessWidget {
  const _KpiIndicator();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 12,
      height: 12,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: Color(0xFF19C37D),
      ),
    );
  }
}

class _DragTaskPayload {
  const _DragTaskPayload({required this.task});

  final KanbanTask task;
}

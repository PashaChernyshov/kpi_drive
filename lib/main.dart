import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:kpi_drive_app/core/config/app_config.dart';
import 'package:kpi_drive_app/core/network/api_client.dart';
import 'package:kpi_drive_app/features/kanban/data/kanban_api_service.dart';
import 'package:kpi_drive_app/features/kanban/data/kanban_repository.dart';
import 'package:kpi_drive_app/features/kanban/presentation/kanban_controller.dart';
import 'package:kpi_drive_app/features/kanban/presentation/kanban_screen.dart';

void main() {
  final bootstrap = AppBootstrap();

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    bootstrap.reportFatal(details.exception, details.stack);
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    bootstrap.reportFatal(error, stack);
    return true;
  };

  runZonedGuarded(
    () => runApp(KpiDriveApp(bootstrap: bootstrap)),
    bootstrap.reportFatal,
  );
}

class KpiDriveApp extends StatelessWidget {
  const KpiDriveApp({super.key, required this.bootstrap});

  final AppBootstrap bootstrap;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: bootstrap,
      builder: (context, _) {
        return MaterialApp(
          title: AppConfig.appTitle,
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            brightness: Brightness.dark,
            scaffoldBackgroundColor: const Color(0xFF0A0E14),
            fontFamily: 'Segoe UI',
            useMaterial3: true,
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFF19C37D),
              surface: Color(0xFF11161E),
            ),
          ),
          home: bootstrap.hasFatalError
              ? FatalErrorScreen(message: bootstrap.errorDescription)
              : KanbanScreen(controller: bootstrap.controller),
        );
      },
    );
  }
}

class AppBootstrap extends ChangeNotifier {
  AppBootstrap()
    : controller = KanbanController(
        repository: KanbanRepository(
          apiService: KanbanApiService(
            apiClient: ApiClient(),
            config: AppConfig.instance,
          ),
        ),
      );

  final KanbanController controller;

  Object? _error;
  StackTrace? _stackTrace;

  bool get hasFatalError => _error != null;

  String get errorDescription {
    final stack = _stackTrace?.toString() ?? '';
    final snippet = stack.length > 700
        ? '${stack.substring(0, 700)}...'
        : stack;
    return '${_error ?? 'Неизвестная ошибка'}\n$snippet';
  }

  void reportFatal(Object error, StackTrace? stackTrace) {
    _error = error;
    _stackTrace = stackTrace;
    notifyListeners();
  }
}

class FatalErrorScreen extends StatelessWidget {
  const FatalErrorScreen({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E14),
      body: Center(
        child: Container(
          width: 760,
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xFF11161E),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF293241)),
          ),
          child: SelectableText(
            message,
            style: const TextStyle(
              color: Color(0xFFE6EBF2),
              fontSize: 13,
              height: 1.4,
            ),
          ),
        ),
      ),
    );
  }
}

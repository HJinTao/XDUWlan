import 'runtime_host.dart';

enum TrayAction {
  show,
  check,
  authenticate,
  configure,
  automaticRecovery,
  launchAtStartup,
  exit,
}

class TrayState {
  const TrayState({
    required this.status,
    required this.automaticRecovery,
    required this.launchAtStartup,
    required this.settingsReady,
    required this.startupReady,
  });
  final String status;
  final bool automaticRecovery;
  final bool launchAtStartup;
  final bool settingsReady;
  final bool startupReady;
}

/// 桌面能力只在首帧后初始化，界面和调度不直接依赖插件。
abstract interface class DesktopHost implements RuntimeHost {
  Future<void> initializeWindow({
    required bool background,
    required void Function() onClose,
    required void Function() onSuspend,
    required void Function() onResume,
  });
  Future<void> initializeTray(void Function(TrayAction) onAction);
  Future<bool> initializeStartup();
  Future<bool> setLaunchAtStartup(bool enabled);
  Future<void> updateTray(TrayState state);
  Future<void> showWindow();
  Future<void> hideWindow();
  Future<void> disposeTray();
  String? get trayAdvice;
}

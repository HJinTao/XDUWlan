import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/domain.dart';
import '../core/presentation.dart';
import 'desktop_host.dart';
import 'diagnostics.dart';
import 'recovery_controller.dart';
import 'settings.dart';

/// 首帧后的能力初始化、唯一调度计时器和桌面生命周期。
class AppRuntimeController extends ChangeNotifier {
  AppRuntimeController({
    required this.recovery,
    required this.desktop,
    required this.settingsStore,
    required this.diagnosticStore,
    this.background = false,
  }) {
    recovery.addListener(_recoveryChanged);
  }
  final RecoveryController recovery;
  final DesktopHost desktop;
  final SettingsStore settingsStore;
  final DiagnosticStore diagnosticStore;
  final bool background;
  AppSettings settings = const AppSettings();
  bool initialized = false;
  bool settingsReady = false;
  bool trayReady = false;
  bool trayAvailable = false;
  bool notificationReady = false;
  bool notificationsAvailable = false;
  bool startupReady = false;
  bool startupAvailable = false;
  bool windowReady = false;
  bool settingsSaving = false;
  bool authenticationPaused = false;
  String? settingsError;
  String? trayError;
  String? notificationError;
  String? startupError;
  String? windowError;
  String? diagnosticsError;
  List<DiagnosticRecord> records = const [];
  void Function()? onConfigureRequest;
  Timer? _timer;
  Future<void>? _initialization;
  Future<void>? _exitFuture;
  Future<void> _diagnosticTail = Future.value();
  Future<void> _trayTail = Future.value();
  OperationReport? _seenReport;
  FailureCode? _notifiedFailure;
  FailureCode? _lastFailureType;
  int _backoff = 0;
  int _seenAccountRevision = 0;
  int _operationAccountRevision = 0;
  int _seenOperationSequence = 0;
  bool _windowInitializationFinished = false;
  bool _suspended = false;
  bool _immediatePending = false;
  bool _exiting = false;
  bool _disposed = false;
  Duration _delay = const Duration(seconds: 60);

  Future<void> initialize() => _initialization ??= _initialize();

  Future<void> _initialize() async {
    // 诊断 I/O 独立排队，不成为认证或其他初始化的前置条件。
    _diagnosticTail = _loadDiagnostics();
    await Future.wait([
      _loadSettings(),
      _initializeWindow(),
      _initializeTray(),
      _initializeNotifications(),
      _initializeStartup(),
    ]);
    if (_exiting) return;
    initialized = true;
    _changed();
    if (settings.automaticRecoveryEnabled && !_suspended) await _cycle();
  }

  Future<void> _loadSettings() async {
    try {
      settings = await settingsStore.load();
    } catch (_) {
      settings = const AppSettings();
      settingsError = '设置读取失败，已使用默认值。请检查应用目录权限或重新保存设置。';
    }
    // 启动项状态以操作系统查询为准，不用旧文件覆盖先完成的系统查询。
    if (startupReady && startupAvailable) {
      settings = settings.copyWith(launchAtStartup: _actualStartup);
    }
    settingsReady = true;
    _changed();
  }

  Future<void> _initializeWindow() async {
    try {
      await desktop.initializeWindow(
        background: background,
        onClose: () => unawaited(closeWindow()),
        onSuspend: suspend,
        onResume: resume,
      );
      windowReady = true;
    } catch (_) {
      windowError = '窗口管理不可用，关闭窗口将退出应用。';
    }
    _windowInitializationFinished = true;
    await _showFallbackWindow();
    _changed();
  }

  Future<void> _initializeTray() async {
    try {
      await desktop.initializeTray(_trayAction);
      trayAvailable = true;
      if (_exiting) await desktop.disposeTray();
    } catch (_) {
      trayError = desktop.trayAdvice ?? '托盘不可用，关闭窗口将退出应用。';
    }
    trayReady = true;
    await _showFallbackWindow();
    _changed();
  }

  Future<void> _showFallbackWindow() async {
    if (!background ||
        !trayReady ||
        trayAvailable ||
        !_windowInitializationFinished ||
        _exiting) {
      return;
    }
    // 必须等窗口初始化的隐藏动作结束后再展示，避免无托盘时失去入口。
    try {
      await desktop.showWindow();
    } catch (_) {
      windowError = '窗口显示失败。请退出后重新打开应用。';
    }
  }

  Future<void> _initializeNotifications() async {
    try {
      await desktop.initializeNotifications();
      notificationsAvailable = true;
    } catch (_) {
      notificationError = '系统通知不可用，结果仍可在主界面和托盘查看。';
    }
    notificationReady = true;
    _changed();
  }

  bool _actualStartup = false;
  Future<void> _initializeStartup() async {
    try {
      _actualStartup = await desktop.initializeStartup();
      settings = settings.copyWith(launchAtStartup: _actualStartup);
      startupAvailable = true;
    } catch (_) {
      startupError = '无法读取登录启动状态。请检查系统启动项权限后重试。';
    }
    startupReady = true;
    _changed();
  }

  Future<void> _loadDiagnostics() async {
    try {
      records = List.unmodifiable((await diagnosticStore.load()).take(50));
    } catch (_) {
      diagnosticsError = '诊断记录读取失败，网络恢复仍继续。';
    }
    _changed();
  }

  Future<void> setAutomaticRecovery(bool enabled) async {
    if (!settingsReady || settingsSaving || _exiting) return;
    final proposed = settings.copyWith(automaticRecoveryEnabled: enabled);
    settingsSaving = true;
    _changed();
    try {
      await settingsStore.save(proposed);
      settings = settings.copyWith(automaticRecoveryEnabled: enabled);
      settingsError = null;
      if (settings.launchAtStartup != proposed.launchAtStartup) {
        try {
          await settingsStore.save(settings);
        } catch (_) {
          settingsError = '设置保存失败；登录启动开关显示系统中的实际状态。';
        }
      }
      if (enabled) {
        _immediatePending = true;
        if (initialized && !recovery.busy && !_suspended) unawaited(_cycle());
      } else {
        _timer?.cancel();
        _timer = null;
      }
    } catch (_) {
      settingsError = '设置保存失败，开关已恢复。请检查应用目录权限后重试。';
    } finally {
      settingsSaving = false;
      _changed();
    }
  }

  Future<void> setLaunchAtStartup(bool enabled) async {
    if (!settingsReady ||
        !startupReady ||
        !startupAvailable ||
        settingsSaving ||
        _exiting) {
      return;
    }
    settingsSaving = true;
    _changed();
    try {
      _actualStartup = await desktop.setLaunchAtStartup(enabled);
      startupError = _actualStartup == enabled ? null : '登录启动未能切换，已恢复实际状态。';
    } catch (_) {
      try {
        _actualStartup = await desktop.initializeStartup();
      } catch (_) {}
      startupError = '登录启动操作失败，已恢复实际状态。请检查系统启动项权限后重试。';
    }
    settings = settings.copyWith(launchAtStartup: _actualStartup);
    try {
      await settingsStore.save(settings);
    } catch (_) {
      settingsError = '设置保存失败；登录启动开关显示系统中的实际状态。';
    }
    settingsSaving = false;
    _changed();
  }

  Future<OperationReport?> check(OperationSource source) =>
      recovery.run(OperationKind.check, source);

  Future<OperationReport?> authenticate(OperationSource source) {
    authenticationPaused = false;
    return recovery.run(OperationKind.authenticate, source);
  }

  Future<void> _cycle() async {
    if (_exiting || _suspended || !settings.automaticRecoveryEnabled) return;
    _timer?.cancel();
    _timer = null;
    if (recovery.busy) {
      _immediatePending = true;
      return;
    }
    _immediatePending = false;
    await recovery.run(
      OperationKind.check,
      OperationSource.automatic,
      allowAuthentication: !authenticationPaused,
    );
  }

  void _recoveryChanged() {
    if (_exiting) return;
    if (recovery.operationSequence != _seenOperationSequence) {
      _seenOperationSequence = recovery.operationSequence;
      _operationAccountRevision = recovery.accountRevision;
      if (recovery.activeKind == OperationKind.authenticate &&
          recovery.activeSource != OperationSource.automatic) {
        authenticationPaused = false;
      }
    }
    if (recovery.busy) {
      _timer?.cancel();
      _timer = null;
    }
    if (recovery.accountRevision != _seenAccountRevision) {
      _seenAccountRevision = recovery.accountRevision;
      authenticationPaused = false;
      _backoff = 0;
      _immediatePending = true;
    }
    final report = recovery.lastReport;
    if (report != null && !identical(report, _seenReport)) {
      _seenReport = report;
      _consume(report);
    }
    if (initialized &&
        !recovery.busy &&
        settings.automaticRecoveryEnabled &&
        !_suspended) {
      if (_immediatePending) {
        unawaited(_cycle());
      } else {
        _schedule();
      }
    }
    _changed();
  }

  void _consume(OperationReport report) {
    if (report.failure != null && report.failure != _lastFailureType) {
      _notifiedFailure = null;
      _lastFailureType = report.failure;
    }
    final accountError = {
      FailureCode.credentialsMissing,
      FailureCode.credentialsInvalid,
      FailureCode.authRejected,
      FailureCode.credentialFileUnavailable,
      FailureCode.credentialStoreUnavailable,
    }.contains(report.failure);
    if (accountError && _operationAccountRevision == recovery.accountRevision) {
      authenticationPaused = true;
    }
    if (report.network == NetworkState.online) {
      _backoff = 0;
      _notifiedFailure = null;
      _lastFailureType = null;
      _delay = const Duration(seconds: 60);
    } else if (authenticationPaused) {
      _delay = const Duration(minutes: 5);
    } else {
      const delays = [
        Duration(seconds: 30),
        Duration(seconds: 60),
        Duration(minutes: 5),
      ];
      _delay = delays[_backoff.clamp(0, 2)];
      _backoff = (_backoff + 1).clamp(0, 2);
    }
    _diagnosticTail = _diagnosticTail.then((_) async {
      try {
        await diagnosticStore.append(DiagnosticRecord.fromReport(report));
        records = List.unmodifiable((await diagnosticStore.load()).take(50));
        diagnosticsError = null;
      } catch (_) {
        diagnosticsError = '诊断记录保存失败，网络恢复仍继续。';
      }
      _changed();
    });
    if (report.source == OperationSource.automatic &&
        report.kind == OperationKind.authenticate) {
      if (report.outcome == RecoveryOutcome.restored ||
          (report.failure != null && report.failure != _notifiedFailure)) {
        _notifiedFailure = report.failure;
        if (notificationsAvailable) unawaited(_notify(report));
      }
    }
  }

  Future<void> _notify(OperationReport report) async {
    try {
      await desktop.notifyAuthentication(report);
    } catch (_) {
      notificationsAvailable = false;
      notificationError = '系统通知不可用，结果仍可在主界面和托盘查看。';
      _changed();
    }
  }

  void _schedule() {
    if (_exiting || _suspended) return;
    _timer?.cancel();
    _timer = Timer(
      authenticationPaused ? const Duration(minutes: 5) : _delay,
      () {
        _timer = null;
        unawaited(_cycle());
      },
    );
  }

  void suspend() {
    if (_exiting) return;
    _suspended = true;
    _timer?.cancel();
    _timer = null;
  }

  void resume() {
    if (_exiting || !_suspended) return;
    _suspended = false;
    _immediatePending = true;
    if (initialized && settings.automaticRecoveryEnabled) unawaited(_cycle());
  }

  Future<void> closeWindow() async {
    if (_exiting) return;
    if (!trayAvailable || !windowReady) {
      await exit();
      return;
    }
    try {
      await desktop.hideWindow();
    } catch (_) {
      windowError = '窗口隐藏失败。请通过退出按钮结束应用。';
      _changed();
    }
  }

  Future<void> showWindow() async {
    if (_exiting) return;
    try {
      await desktop.showWindow();
    } catch (_) {
      windowError = '窗口显示失败。请通过托盘退出后重新打开应用。';
      _changed();
    }
  }

  void _trayAction(TrayAction action) {
    if (_exiting) return;
    switch (action) {
      case TrayAction.show:
        unawaited(showWindow());
      case TrayAction.check:
        unawaited(check(OperationSource.tray));
      case TrayAction.authenticate:
        unawaited(authenticate(OperationSource.tray));
      case TrayAction.configure:
        unawaited(
          showWindow().then((_) {
            if (!_exiting) onConfigureRequest?.call();
          }),
        );
      case TrayAction.automaticRecovery:
        unawaited(setAutomaticRecovery(!settings.automaticRecoveryEnabled));
      case TrayAction.launchAtStartup:
        unawaited(setLaunchAtStartup(!settings.launchAtStartup));
      case TrayAction.exit:
        unawaited(exit());
    }
  }

  void _changed() {
    if (_disposed || _exiting) return;
    notifyListeners();
    if (trayAvailable) {
      final state = TrayState(
        status: recovery.busy
            ? stageMessage(recovery.stage)
            : recovery.failure != null
            ? failureMessage(recovery.failure!)
            : networkMessage(recovery.network),
        automaticRecovery: settings.automaticRecoveryEnabled,
        launchAtStartup: settings.launchAtStartup,
        settingsReady: settingsReady && !settingsSaving,
        startupReady:
            settingsReady &&
            startupReady &&
            startupAvailable &&
            !settingsSaving,
      );
      _trayTail = _trayTail.then((_) async {
        if (_exiting) return;
        try {
          await desktop.updateTray(state);
        } catch (_) {
          trayAvailable = false;
          trayError = desktop.trayAdvice ?? '托盘不可用，关闭窗口将退出应用。';
          if (!_disposed) notifyListeners();
          if (background) unawaited(showWindow());
        }
      });
    }
  }

  Future<void> flushDiagnostics() => _diagnosticTail;
  Future<void> clearDiagnostics() {
    _diagnosticTail = _diagnosticTail.then((_) async {
      try {
        await diagnosticStore.clear();
        records = const [];
        diagnosticsError = null;
      } catch (_) {
        diagnosticsError = '诊断记录清空失败。请检查应用目录权限后重试。';
      }
      _changed();
    });
    return _diagnosticTail;
  }

  Future<void> exit() => _exitFuture ??= _exit();
  Future<void> _exit() async {
    _exiting = true;
    _timer?.cancel();
    _timer = null;
    recovery.shutdown();
    try {
      await desktop.disposeTray();
    } catch (_) {}
    await desktop.exit();
  }

  @override
  void dispose() {
    _exiting = true;
    _disposed = true;
    _timer?.cancel();
    recovery.removeListener(_recoveryChanged);
    super.dispose();
  }
}

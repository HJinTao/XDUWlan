import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/domain.dart';
import '../core/presentation.dart';
import 'background_tasks.dart';
import 'desktop_host.dart';
import 'diagnostics.dart';
import 'recovery_controller.dart';
import 'runtime_host.dart';
import 'settings.dart';

/// 首帧后的能力初始化、唯一调度计时器和桌面生命周期。
class AppRuntimeController extends ChangeNotifier {
  AppRuntimeController({
    required this.recovery,
    DesktopHost? desktop,
    RuntimeHost? host,
    required this.settingsStore,
    required this.diagnosticStore,
    this.background = false,
    this.backgroundScheduler,
  }) : desktop = desktop ?? (host is DesktopHost ? host : null),
       host = host ?? desktop ?? NoopRuntimeHost() {
    recovery.addListener(_recoveryChanged);
  }
  final RecoveryController recovery;
  final RuntimeHost host;
  final DesktopHost? desktop;
  final SettingsStore settingsStore;
  final DiagnosticStore diagnosticStore;
  final bool background;
  final BackgroundTaskScheduler? backgroundScheduler;
  bool get isDesktop => desktop != null;
  AppSettings settings = const AppSettings();
  bool initialized = false;
  bool settingsReady = false;
  bool trayReady = false;
  bool trayAvailable = false;
  bool notificationReady = false;
  bool notificationsAvailable = false;
  NotificationAuthorizationStatus notificationAuthorizationStatus =
      NotificationAuthorizationStatus.unavailable;
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
  FailureCode? _lastFailureType;
  String? _lastNotificationEventKey;
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
    final currentDesktop = desktop;
    if (currentDesktop == null) {
      await Future.wait([_loadSettings(), _initializeNotifications()]);
      await _initializeBackgroundScheduler();
    } else {
      await Future.wait([
        _loadSettings(),
        _initializeWindow(currentDesktop),
        _initializeTray(currentDesktop),
        _initializeNotifications(),
        _initializeStartup(currentDesktop),
      ]);
    }
    if (_exiting) return;
    initialized = true;
    _changed();
    if (settings.automaticRecoveryEnabled && !_suspended) await _cycle();
    if (currentDesktop == null && settings.automaticRecoveryEnabled) {
      await backgroundScheduler?.schedule();
    }
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

  Future<void> _initializeWindow(DesktopHost currentDesktop) async {
    try {
      await currentDesktop.initializeWindow(
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

  Future<void> _initializeTray(DesktopHost currentDesktop) async {
    try {
      await currentDesktop.initializeTray(_trayAction);
      trayAvailable = true;
      if (_exiting) await currentDesktop.disposeTray();
    } catch (_) {
      trayError = currentDesktop.trayAdvice ?? '托盘不可用，关闭窗口将退出应用。';
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
      await desktop?.showWindow();
    } catch (_) {
      windowError = '窗口显示失败。请退出后重新打开应用。';
    }
  }

  Future<void> _initializeNotifications() async {
    try {
      await host.initializeNotifications();
      notificationsAvailable = true;
      await _refreshNotificationStatus(requestIfUndecided: true);
    } catch (_) {
      notificationError = '系统通知不可用，结果仍可在主界面和托盘查看。';
    }
    notificationReady = true;
    _changed();
  }

  Future<void> _refreshNotificationStatus({
    bool requestIfUndecided = false,
  }) async {
    try {
      var status = await host.notificationStatus();
      if (requestIfUndecided &&
          status == NotificationAuthorizationStatus.notDetermined) {
        status = await host.requestNotificationPermission();
      }
      notificationAuthorizationStatus = status;
    } catch (_) {
      notificationAuthorizationStatus =
          NotificationAuthorizationStatus.unavailable;
    }
    _changed();
  }

  Future<void> requestNotificationPermission() async {
    if (_exiting || !notificationsAvailable) return;
    try {
      if (notificationAuthorizationStatus ==
          NotificationAuthorizationStatus.notDetermined) {
        notificationAuthorizationStatus = await host
            .requestNotificationPermission();
        _changed();
      }
    } catch (_) {
      notificationAuthorizationStatus =
          NotificationAuthorizationStatus.unavailable;
      _changed();
    }
  }

  bool _actualStartup = false;
  Future<void> _initializeStartup(DesktopHost currentDesktop) async {
    try {
      _actualStartup = await currentDesktop.initializeStartup();
      settings = settings.copyWith(launchAtStartup: _actualStartup);
      startupAvailable = true;
    } catch (_) {
      startupAvailable = false;
      startupError = '登录启动状态未能确认。请检查同名启动项内容或目录权限后重新打开应用。';
    }
    startupReady = true;
    _changed();
  }

  Future<void> _initializeBackgroundScheduler() async {
    try {
      await backgroundScheduler?.initialize(_runBackgroundTask);
    } catch (_) {
      diagnosticsError = '后台检查未能注册，打开应用时仍可手动检查。';
    }
  }

  Future<void> _runBackgroundTask() async {
    if (_exiting || !settings.automaticRecoveryEnabled || recovery.busy) {
      return;
    }
    await recovery.run(
      OperationKind.check,
      OperationSource.background,
      allowAuthentication: !authenticationPaused,
    );
    if (!_exiting && settings.automaticRecoveryEnabled) {
      await backgroundScheduler?.schedule();
    }
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
        if (desktop == null) await backgroundScheduler?.schedule();
        if (initialized && !recovery.busy && !_suspended) unawaited(_cycle());
      } else {
        _timer?.cancel();
        _timer = null;
        await backgroundScheduler?.cancel();
      }
    } catch (_) {
      settingsError = '设置保存失败，开关已恢复。请检查应用目录权限后重试。';
    } finally {
      settingsSaving = false;
      _changed();
    }
  }

  Future<void> setLaunchAtStartup(bool enabled) async {
    if (desktop == null ||
        !settingsReady ||
        !startupReady ||
        !startupAvailable ||
        settingsSaving ||
        _exiting) {
      return;
    }
    settingsSaving = true;
    _changed();
    try {
      _actualStartup = await desktop!.setLaunchAtStartup(enabled);
      startupAvailable = true;
      startupError = _actualStartup == enabled ? null : '登录启动未能切换，已恢复实际状态。';
    } catch (_) {
      try {
        _actualStartup = await desktop!.initializeStartup();
        startupAvailable = true;
        startupError = '登录启动操作失败，已显示查询到的实际状态。请检查同名启动项内容或目录权限后重试。';
      } catch (_) {
        startupAvailable = false;
        startupError = '登录启动操作失败，当前状态未能确认，开关已禁用。请检查同名启动项内容或目录权限后重新打开应用。';
      }
    }
    settings = settings.copyWith(launchAtStartup: _actualStartup);
    try {
      await settingsStore.save(settings);
      settingsError = null;
    } catch (_) {
      settingsError = startupAvailable
          ? '设置保存失败；登录启动开关显示系统中的实际状态。'
          : '设置保存失败；登录启动状态仍未能确认，请检查应用目录权限后重试。';
    }
    settingsSaving = false;
    _changed();
  }

  Future<OperationReport?> check(OperationSource source) =>
      recovery.run(OperationKind.check, source);

  /// 网络路径变化只在前台进入检查；挂起或检查进行中时合并到下一轮。
  void onNetworkPathUpdate() {
    if (_exiting) return;
    if (!initialized || _suspended || recovery.busy) {
      _immediatePending = true;
      return;
    }
    unawaited(check(OperationSource.automatic));
  }

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
      } else if (desktop != null) {
        _schedule();
      }
    }
    _changed();
  }

  void _consume(OperationReport report) {
    if (report.source != OperationSource.automatic &&
        report.source != OperationSource.background) {
      _lastNotificationEventKey = null;
    }
    if (report.failure != null && report.failure != _lastFailureType) {
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
    if (report.source == OperationSource.automatic ||
        report.source == OperationSource.background) {
      final eventKey = _notificationEventKey(report);
      if (eventKey != null && eventKey != _lastNotificationEventKey) {
        _lastNotificationEventKey = eventKey;
        if (notificationsAvailable) unawaited(_notify(report));
      }
    }
  }

  String? _notificationEventKey(OperationReport report) {
    if (desktop != null && report.kind != OperationKind.authenticate) {
      return null;
    }
    final link = report.link ?? NetworkLink.unknown;
    final campus = report.campus ?? CampusNetworkState.unknown;
    if (report.outcome != RecoveryOutcome.restored &&
        (link == NetworkLink.unknown || campus == CampusNetworkState.unknown)) {
      return null;
    }
    if (report.outcome == RecoveryOutcome.restored) {
      return 'restored:${link.name}:${campus.name}';
    }
    if (report.failure != null) {
      return 'failure:${link.name}:${campus.name}:${report.failure!.name}';
    }
    return 'network:${link.name}:${campus.name}:${report.network.name}';
  }

  Future<void> _notify(OperationReport report) async {
    try {
      await _refreshNotificationStatus();
      if (notificationAuthorizationStatus !=
          NotificationAuthorizationStatus.authorized) {
        return;
      }
      await host.notifyAuthentication(report);
    } catch (_) {
      _lastNotificationEventKey = null;
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
    unawaited(_refreshNotificationStatus());
    _immediatePending = true;
    if (initialized && settings.automaticRecoveryEnabled) unawaited(_cycle());
  }

  Future<void> closeWindow() async {
    if (_exiting) return;
    final currentDesktop = desktop;
    if (currentDesktop == null) return;
    if (!trayAvailable || !windowReady) {
      await exit();
      return;
    }
    try {
      await currentDesktop.hideWindow();
    } catch (_) {
      windowError = '窗口隐藏失败。请通过退出按钮结束应用。';
      _changed();
    }
  }

  Future<void> showWindow() async {
    if (_exiting) return;
    final currentDesktop = desktop;
    if (currentDesktop == null) return;
    try {
      await currentDesktop.showWindow();
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
    final currentDesktop = desktop;
    if (trayAvailable && currentDesktop != null) {
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
          await currentDesktop.updateTray(state);
        } catch (_) {
          trayAvailable = false;
          trayError = currentDesktop.trayAdvice ?? '托盘不可用，关闭窗口将退出应用。';
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
    await backgroundScheduler?.cancel();
    try {
      await desktop?.disposeTray();
    } catch (_) {}
    await host.exit();
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

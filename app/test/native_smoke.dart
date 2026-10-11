import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:local_notifier/local_notifier.dart';
import 'package:window_manager/window_manager.dart';
import 'package:xduwlan_app/application/app_runtime_controller.dart';
import 'package:xduwlan_app/application/diagnostics.dart';
import 'package:xduwlan_app/application/recovery_controller.dart';
import 'package:xduwlan_app/application/recovery_service.dart';
import 'package:xduwlan_app/core/domain.dart';
import 'package:xduwlan_app/main.dart';
import 'package:xduwlan_app/platform/credential_store.dart';
import 'package:xduwlan_app/platform/desktop_host.dart';

import 'application/runtime_fakes.dart' show TestSettings;

/// 原生离线验收入口：只用虚构账号、临时目录，不注册真实登录启动项。
void main(List<String> args) {
  final directory = Directory(
    '${Directory.systemTemp.path}/xduwlan-native-${DateTime.now().microsecondsSinceEpoch}',
  );
  final store = LocalCredentialStore(directory: directory);
  final controller = RecoveryController(
    service: RecoveryService(
      probe: _OfflineProbe(),
      portal: _UnusedPortal(),
      store: store,
    ),
    store: store,
  );
  final host = _SmokeDesktop();
  final runtime = AppRuntimeController(
    recovery: controller,
    desktop: host,
    settingsStore: TestSettings(),
    diagnosticStore: LocalDiagnosticStore(directory: directory),
    background:
        args.contains('--background') ||
        Platform.executableArguments.contains('--background'),
  );
  runApp(XduwlanApp(runtime: runtime, ownsRuntime: true));
  WidgetsBinding.instance.addPostFrameCallback(
    (_) => unawaited(
      _verify(
        runtime,
        store,
        directory,
        reopen:
            args.contains('--reopen-smoke') ||
            Platform.executableArguments.contains('--reopen-smoke'),
      ),
    ),
  );
}

Future<void> _verify(
  AppRuntimeController runtime,
  LocalCredentialStore store,
  Directory directory, {
  bool reopen = false,
}) async {
  try {
    await runtime.initialize();
    await store.save(const Credentials('test-only-user', 'test-only-password'));
    final value = await store.load();
    _result(
      'STORAGE',
      value?.username == 'test-only-user' &&
          value?.password == 'test-only-password',
    );
    _result('TRAY', runtime.trayAvailable);
    _result('NOTIFICATIONS_SETUP', runtime.notificationsAvailable);
    if (runtime.notificationsAvailable) {
      _result('NOTIFICATION_DELIVERY', await _notificationDelivered());
    }
    _result('INITIAL_VISIBILITY', await _visible(!runtime.background));
    await runtime.closeWindow();
    _result('CLOSE_HIDE', await _visible(false));
    if (reopen) {
      debugPrint('XDUWLAN_NATIVE_REOPEN_READY');
      _result('DOCK_REOPEN', await _visible(true));
    } else {
      await runtime.showWindow();
      _result('RESTORE', await _visible(true));
    }
    await runtime.flushDiagnostics();
    _result('DIAGNOSTICS', runtime.records.length == 1);
  } catch (_) {
    _result('LIFECYCLE', false);
  } finally {
    try {
      await directory.delete(recursive: true);
    } catch (_) {}
    // 此标记之后由真实窗口销毁结束进程；退出不提交网络请求。
    debugPrint('XDUWLAN_NATIVE_EXIT_BEGIN');
    await runtime.exit();
  }
}

Future<bool> _notificationDelivered() async {
  final delivered = Completer<bool>();
  final notification = LocalNotification(
    identifier: 'xduwlan.native-smoke',
    title: 'XDUWlan 离线通知测试',
    body: '此通知用于验证系统展示，使用虚构数据。',
  );
  notification.onShow = () {
    if (!delivered.isCompleted) delivered.complete(true);
  };
  try {
    await notification.show();
    return await delivered.future.timeout(
      const Duration(seconds: 3),
      onTimeout: () => false,
    );
  } catch (_) {
    return false;
  } finally {
    try {
      await notification.destroy();
    } catch (_) {}
  }
}

/// window_manager 的 macOS 展示与隐藏在主队列执行，等待实际状态而非方法回包。
Future<bool> _visible(bool expected) async {
  final deadline = Stopwatch()..start();
  while (deadline.elapsed < const Duration(seconds: 2)) {
    if (await windowManager.isVisible() == expected) return true;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  return false;
}

void _result(String name, bool passed) =>
    debugPrint('XDUWLAN_NATIVE_${name}_${passed ? 'OK' : 'FAILED'}');

class _SmokeDesktop extends PluginDesktopHost {
  @override
  Future<bool> initializeStartup() async => false;
  @override
  Future<bool> setLaunchAtStartup(bool enabled) async => false;
}

class _OfflineProbe implements NetworkProbe {
  @override
  Future<NetworkObservation> check(OperationScope scope) async =>
      const NetworkObservation(
        link: NetworkLink.none,
        campus: CampusNetworkState.unknown,
        portal: NetworkState.unknown,
        authenticationAllowed: false,
      );
}

class _UnusedPortal implements PortalClient {
  @override
  Future<PortalContext> prepare(OperationScope scope) async =>
      throw const AppFailure(FailureCode.protocol);
  @override
  Future<void> authenticate(
    PortalContext context,
    Credentials credentials,
    OperationScope scope, {
    required Future<void> Function() beforeSubmit,
  }) async => throw const AppFailure(FailureCode.protocol);
}

import 'package:flutter_test/flutter_test.dart';
import 'package:xduwlan_app/application/app_runtime_controller.dart';
import 'package:xduwlan_app/application/background_tasks.dart';
import 'package:xduwlan_app/application/recovery_controller.dart';
import 'package:xduwlan_app/application/recovery_service.dart';
import 'package:xduwlan_app/application/runtime_host.dart';
import 'package:xduwlan_app/core/domain.dart';

import 'runtime_fakes.dart';

void main() {
  test('移动运行时不初始化桌面能力并安排一次后台任务', () async {
    final accounts = TestAccounts();
    final recovery = RecoveryController(
      service: RecoveryService(
        probe: TestProbe(),
        portal: TestPortal(),
        store: accounts,
      ),
      store: accounts,
    );
    final host = _MobileHost();
    final scheduler = _Scheduler();
    final runtime = AppRuntimeController(
      recovery: recovery,
      host: host,
      backgroundScheduler: scheduler,
      settingsStore: TestSettings(),
      diagnosticStore: TestDiagnostics(),
    );

    await runtime.initialize();

    expect(host.notificationsInitialized, isTrue);
    expect(runtime.isDesktop, isFalse);
    expect(runtime.trayReady, isFalse);
    expect(runtime.startupReady, isFalse);
    expect(scheduler.initialized, isTrue);
    expect(scheduler.scheduled, 1);

    runtime.dispose();
    recovery.dispose();
  });

  test('后台任务来源进入诊断并只执行一轮', () async {
    final accounts = TestAccounts();
    final probe = TestProbe()..state = NetworkState.online;
    final recovery = RecoveryController(
      service: RecoveryService(
        probe: probe,
        portal: TestPortal(),
        store: accounts,
      ),
      store: accounts,
    );
    final scheduler = _Scheduler();
    final runtime = AppRuntimeController(
      recovery: recovery,
      host: _MobileHost(),
      backgroundScheduler: scheduler,
      settingsStore: TestSettings(),
      diagnosticStore: TestDiagnostics(),
    );

    await runtime.initialize();
    final initialCalls = probe.calls;
    await scheduler.run();
    await runtime.flushDiagnostics();

    expect(probe.calls, initialCalls + 1);
    expect(runtime.records.first.source, OperationSource.background);

    runtime.dispose();
    recovery.dispose();
  });

  test('移动端重新打开自动恢复时重新登记后台任务', () async {
    final accounts = TestAccounts();
    final recovery = RecoveryController(
      service: RecoveryService(
        probe: TestProbe(),
        portal: TestPortal(),
        store: accounts,
      ),
      store: accounts,
    );
    final scheduler = _Scheduler();
    final runtime = AppRuntimeController(
      recovery: recovery,
      host: _MobileHost(),
      backgroundScheduler: scheduler,
      settingsStore: TestSettings(),
      diagnosticStore: TestDiagnostics(),
    );

    await runtime.initialize();
    final initialSchedules = scheduler.scheduled;
    await runtime.setAutomaticRecovery(false);
    await runtime.setAutomaticRecovery(true);

    expect(scheduler.cancelled, 1);
    expect(scheduler.scheduled, greaterThan(initialSchedules));

    runtime.dispose();
    recovery.dispose();
  });

  test('首次初始化只在未决定时请求通知权限，并保留已拒绝状态', () async {
    final host = _MobileHost()
      ..status = NotificationAuthorizationStatus.notDetermined;
    final runtime = _mobileRuntime(host: host);

    await runtime.initialize();

    expect(host.permissionRequests, 1);
    expect(
      runtime.notificationAuthorizationStatus,
      NotificationAuthorizationStatus.denied,
    );
    await runtime.requestNotificationPermission();
    expect(host.permissionRequests, 1);

    runtime.dispose();
    runtime.recovery.dispose();
  });

  test('后台通知按安全事件键连续去重，未知状态不发送', () async {
    final host = _MobileHost()
      ..status = NotificationAuthorizationStatus.authorized;
    final runtime = _mobileRuntime(host: host);
    await runtime.initialize();
    await runtime.setAutomaticRecovery(false);

    final probe = runtime.recovery.service.probe as TestProbe;
    probe.state = NetworkState.portalRequired;
    await runtime.recovery.run(
      OperationKind.authenticate,
      OperationSource.background,
      allowAuthentication: true,
    );
    await Future<void>.delayed(Duration.zero);
    expect(host.notifications, hasLength(1));

    await runtime.recovery.run(
      OperationKind.authenticate,
      OperationSource.background,
      allowAuthentication: true,
    );
    await Future<void>.delayed(Duration.zero);
    expect(host.notifications, hasLength(1));

    probe.state = NetworkState.unknown;
    await runtime.recovery.run(OperationKind.check, OperationSource.background);
    await Future<void>.delayed(Duration.zero);
    expect(host.notifications, hasLength(1));

    runtime.dispose();
    runtime.recovery.dispose();
  });

  test('挂起时网络路径更新只排队，恢复后执行一次检查', () async {
    final host = _MobileHost();
    final runtime = _mobileRuntime(host: host);
    await runtime.initialize();
    final probe = runtime.recovery.service.probe as TestProbe;
    final initialCalls = probe.calls;

    runtime.suspend();
    runtime.onNetworkPathUpdate();
    expect(probe.calls, initialCalls);
    runtime.resume();
    await Future<void>.delayed(Duration.zero);

    expect(probe.calls, greaterThan(initialCalls));
    runtime.dispose();
    runtime.recovery.dispose();
  });

  test('非 iOS 移动端没有路径来源时仍可安全初始化', () async {
    final runtime = _mobileRuntime(host: _MobileHost());

    await runtime.initialize();

    expect(runtime.isDesktop, isFalse);
    expect(runtime.notificationReady, isTrue);
    runtime.dispose();
    runtime.recovery.dispose();
  });
}

AppRuntimeController _mobileRuntime({required _MobileHost host}) {
  final accounts = TestAccounts();
  final recovery = RecoveryController(
    service: RecoveryService(
      probe: TestProbe(),
      portal: TestPortal(),
      store: accounts,
    ),
    store: accounts,
  );
  return AppRuntimeController(
    recovery: recovery,
    host: host,
    backgroundScheduler: _Scheduler(),
    settingsStore: TestSettings(),
    diagnosticStore: TestDiagnostics(),
  );
}

class _MobileHost implements RuntimeHost {
  bool notificationsInitialized = false;
  NotificationAuthorizationStatus status =
      NotificationAuthorizationStatus.authorized;
  int permissionRequests = 0;
  final notifications = <OperationReport>[];

  @override
  Future<void> initializeNotifications() async {
    notificationsInitialized = true;
  }

  @override
  Future<NotificationAuthorizationStatus> notificationStatus() async => status;

  @override
  Future<NotificationAuthorizationStatus>
  requestNotificationPermission() async {
    permissionRequests++;
    status = NotificationAuthorizationStatus.denied;
    return status;
  }

  @override
  Future<void> notifyAuthentication(OperationReport report) async {
    notifications.add(report);
  }

  @override
  Future<void> exit() async {}
}

class _Scheduler implements BackgroundTaskScheduler {
  Future<void> Function()? callback;
  bool initialized = false;
  int scheduled = 0;
  int cancelled = 0;

  @override
  Future<void> initialize(Future<void> Function() onRun) async {
    initialized = true;
    callback = onRun;
  }

  @override
  Future<void> schedule() async {
    scheduled++;
  }

  @override
  Future<void> cancel() async {
    cancelled++;
  }

  Future<void> run() async {
    await callback?.call();
  }
}

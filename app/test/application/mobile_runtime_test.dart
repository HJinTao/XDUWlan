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
}

class _MobileHost implements RuntimeHost {
  bool notificationsInitialized = false;

  @override
  Future<void> initializeNotifications() async {
    notificationsInitialized = true;
  }

  @override
  Future<void> notifyAuthentication(OperationReport report) async {}

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

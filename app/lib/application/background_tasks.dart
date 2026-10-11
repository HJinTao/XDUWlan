import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';

import 'diagnostics.dart';
import 'recovery_controller.dart';
import 'recovery_service.dart';
import 'runtime_host.dart';
import '../core/domain.dart';
import '../platform/credential_store.dart';
import '../platform/http_transport.dart';
import '../platform/network_probe.dart';
import '../platform/mobile_host.dart';
import '../platform/srun_client.dart';

/// 平台决定实际运行时间的后台任务入口。
abstract interface class BackgroundTaskScheduler {
  Future<void> initialize(Future<void> Function() onRun);
  Future<void> schedule();
  Future<void> cancel();
}

class NoopBackgroundTaskScheduler implements BackgroundTaskScheduler {
  @override
  Future<void> initialize(Future<void> Function() onRun) async {}

  @override
  Future<void> schedule() async {}

  @override
  Future<void> cancel() async {}
}

const mobileRecoveryTask = 'cn.xduwlan.mobile.recovery';

/// Workmanager 的顶层入口；移动系统可能在没有主 Flutter 实例时调用它。
@pragma('vm:entry-point')
void mobileBackgroundDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task != mobileRecoveryTask) return false;
    return runMobileBackgroundRecovery();
  });
}

class WorkmanagerBackgroundTaskScheduler implements BackgroundTaskScheduler {
  WorkmanagerBackgroundTaskScheduler({Workmanager? workmanager})
    : _workmanager = workmanager ?? Workmanager();

  final Workmanager _workmanager;
  bool _initialized = false;

  @override
  Future<void> initialize(Future<void> Function() onRun) async {
    await _workmanager.initialize(mobileBackgroundDispatcher);
    _initialized = true;
  }

  @override
  Future<void> schedule() async {
    if (!_initialized) return;
    await _workmanager.registerPeriodicTask(
      mobileRecoveryTask,
      mobileRecoveryTask,
      frequency: const Duration(minutes: 15),
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
    );
  }

  @override
  Future<void> cancel() => _workmanager.cancelByUniqueName(mobileRecoveryTask);
}

/// 后台任务只执行一轮检查/认证，并把安全报告追加到移动端诊断文件。
Future<bool> runMobileBackgroundRecovery() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = LocalCredentialStore();
  final transport = IoPortalTransport();
  final recovery = RecoveryController(
    service: RecoveryService(
      probe: IoNetworkProbe(transport: transport, allowLegacyPath: false),
      portal: SrunPortalClient(transport: transport),
      store: store,
    ),
    store: store,
  );
  try {
    final report = await recovery.run(
      OperationKind.check,
      OperationSource.background,
      allowAuthentication: true,
    );
    if (report == null) return false;
    await LocalDiagnosticStore().append(DiagnosticRecord.fromReport(report));
    if (report.kind == OperationKind.authenticate) {
      final notifications = LocalNotificationsMobileHostBridge();
      try {
        await notifications.initializeNotifications(requestPermission: false);
        if (await notifications.notificationStatus() ==
            NotificationAuthorizationStatus.authorized) {
          await notifications.notifyAuthentication(report);
        }
      } catch (_) {
        // 后台通知不可用时，安全诊断记录仍然保留。
      }
    }
    return report.failure == null ||
        report.failure == FailureCode.verificationFailed;
  } catch (_) {
    return false;
  } finally {
    recovery.dispose();
  }
}

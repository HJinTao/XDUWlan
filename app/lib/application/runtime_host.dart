import '../core/domain.dart';

/// 应用运行时依赖的最小平台能力。
abstract interface class RuntimeHost {
  Future<void> initializeNotifications();
  Future<void> notifyAuthentication(OperationReport report);
  Future<void> exit();
}

class NoopRuntimeHost implements RuntimeHost {
  @override
  Future<void> initializeNotifications() async {}

  @override
  Future<void> notifyAuthentication(OperationReport report) async {}

  @override
  Future<void> exit() async {}
}

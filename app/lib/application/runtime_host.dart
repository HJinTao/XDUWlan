import '../core/domain.dart';

enum NotificationAuthorizationStatus {
  authorized,
  notDetermined,
  denied,
  unavailable,
}

/// 应用运行时依赖的最小平台能力。
abstract interface class RuntimeHost {
  Future<void> initializeNotifications();
  Future<NotificationAuthorizationStatus> notificationStatus();
  Future<NotificationAuthorizationStatus> requestNotificationPermission();
  Future<void> notifyAuthentication(OperationReport report);
  Future<void> exit();
}

class NoopRuntimeHost implements RuntimeHost {
  @override
  Future<void> initializeNotifications() async {}

  @override
  Future<NotificationAuthorizationStatus> notificationStatus() async =>
      NotificationAuthorizationStatus.unavailable;

  @override
  Future<NotificationAuthorizationStatus>
  requestNotificationPermission() async =>
      NotificationAuthorizationStatus.unavailable;

  @override
  Future<void> notifyAuthentication(OperationReport report) async {}

  @override
  Future<void> exit() async {}
}

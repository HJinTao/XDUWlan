import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'dart:io';

import '../application/runtime_host.dart';
import '../core/domain.dart';

abstract interface class MobileHostBridge {
  Future<void> initializeNotifications({bool requestPermission = true});
  Future<NotificationAuthorizationStatus> notificationStatus();
  Future<NotificationAuthorizationStatus> requestNotificationPermission();
  Future<void> notifyAuthentication(OperationReport report);
}

class MethodChannelMobileHostBridge implements MobileHostBridge {
  MethodChannelMobileHostBridge({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('cn.xduwlan/mobile');

  final MethodChannel _channel;

  @override
  Future<void> initializeNotifications({bool requestPermission = true}) =>
      _channel.invokeMethod<void>('initializeNotifications');

  @override
  Future<NotificationAuthorizationStatus> notificationStatus() async =>
      _notificationStatus(
        await _channel.invokeMethod<String>('notificationStatus'),
      );

  @override
  Future<NotificationAuthorizationStatus>
  requestNotificationPermission() async => _notificationStatus(
    await _channel.invokeMethod<String>('requestNotificationPermission'),
  );

  @override
  Future<void> notifyAuthentication(OperationReport report) =>
      _channel.invokeMethod<void>('notifyAuthentication', {
        'outcome': report.outcome?.name,
        'failure': report.failure?.name,
      });
}

class LocalNotificationsMobileHostBridge implements MobileHostBridge {
  LocalNotificationsMobileHostBridge({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  final MethodChannel _channel = const MethodChannel('cn.xduwlan/mobile');
  bool _initialized = false;

  @override
  Future<void> initializeNotifications({bool requestPermission = true}) async {
    final settings = InitializationSettings(
      android: const AndroidInitializationSettings('ic_launcher'),
      iOS: const DarwinInitializationSettings(
        requestAlertPermission: false,
        requestSoundPermission: false,
        requestBadgePermission: false,
      ),
    );
    final initialized = await _plugin.initialize(settings: settings) ?? false;
    if (!initialized) throw StateError('移动端通知初始化失败');
    if (requestPermission) {
      await requestNotificationPermission();
    }
    _initialized = true;
  }

  @override
  Future<NotificationAuthorizationStatus> notificationStatus() async {
    if (Platform.isIOS) {
      return _notificationStatus(
        await _channel.invokeMethod<String>('notificationStatus'),
      );
    }
    final enabled = await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.areNotificationsEnabled();
    return enabled == true
        ? NotificationAuthorizationStatus.authorized
        : NotificationAuthorizationStatus.denied;
  }

  @override
  Future<NotificationAuthorizationStatus>
  requestNotificationPermission() async {
    if (Platform.isIOS) {
      return _notificationStatus(
        await _channel.invokeMethod<String>('requestNotificationPermission'),
      );
    }
    final requested = await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();
    await _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >()
        ?.requestPermissions(alert: true, sound: true);
    final enabled = await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.areNotificationsEnabled();
    return requested == false || enabled == false
        ? NotificationAuthorizationStatus.denied
        : enabled == true
        ? NotificationAuthorizationStatus.authorized
        : NotificationAuthorizationStatus.unavailable;
  }

  @override
  Future<void> notifyAuthentication(OperationReport report) async {
    if (!_initialized) return;
    final restored = report.outcome == RecoveryOutcome.restored;
    final link = switch (report.link) {
      NetworkLink.cellular => '蜂窝网络',
      NetworkLink.wifi => 'Wi-Fi',
      NetworkLink.wired => '有线网络',
      NetworkLink.other => '其他网络',
      NetworkLink.none => '无网络',
      _ => '未知链路',
    };
    final campus = switch (report.campus) {
      CampusNetworkState.authenticationRequired => '需要校园认证',
      CampusNetworkState.online => '校园网已确认',
      CampusNetworkState.unconfirmed => '校园身份未确认',
      CampusNetworkState.unavailable => '校园网络不可用',
      _ => '校园状态未知',
    };
    await _plugin.show(
      id: 1001,
      title: 'XDUWlan',
      body: restored
          ? '校园网已恢复联网（$link，$campus）。'
          : '校园网认证未完成（$link，$campus），请打开应用查看安全提示。',
      notificationDetails: NotificationDetails(
        android: const AndroidNotificationDetails(
          'xduwlan_recovery',
          '校园网恢复',
          channelDescription: '校园网认证与恢复结果',
          importance: Importance.defaultImportance,
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentSound: true,
        ),
      ),
    );
  }
}

/// 移动端没有窗口、托盘和登录启动项，只提供通知能力。
class MobileHost implements RuntimeHost {
  MobileHost({MobileHostBridge? bridge})
    : _bridge = bridge ?? LocalNotificationsMobileHostBridge();

  final MobileHostBridge _bridge;

  @override
  Future<void> initializeNotifications() => _bridge.initializeNotifications();

  @override
  Future<NotificationAuthorizationStatus> notificationStatus() =>
      _bridge.notificationStatus();

  @override
  Future<NotificationAuthorizationStatus> requestNotificationPermission() =>
      _bridge.requestNotificationPermission();

  @override
  Future<void> notifyAuthentication(OperationReport report) =>
      _bridge.notifyAuthentication(report);

  @override
  Future<void> exit() async {}
}

NotificationAuthorizationStatus _notificationStatus(String? value) =>
    switch (value) {
      'authorized' => NotificationAuthorizationStatus.authorized,
      'notDetermined' => NotificationAuthorizationStatus.notDetermined,
      'denied' => NotificationAuthorizationStatus.denied,
      _ => NotificationAuthorizationStatus.unavailable,
    };

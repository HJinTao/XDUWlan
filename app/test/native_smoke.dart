import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:xduwlan_app/application/recovery_controller.dart';
import 'package:xduwlan_app/application/recovery_service.dart';
import 'package:xduwlan_app/core/domain.dart';
import 'package:xduwlan_app/main.dart';
import 'package:xduwlan_app/platform/credential_store.dart';

/// 独立测试服务仅保存虚构记录，完成后删除；不访问生产凭据。
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final directory = await Directory.systemTemp.createTemp('xduwlan-native-');
  final store = LocalCredentialStore(directory: directory);
  var passed = false;
  try {
    await store.save(const Credentials('test-only-user', 'test-only-password'));
    final value = await store.load();
    passed =
        value?.username == 'test-only-user' &&
        value?.password == 'test-only-password';
  } catch (_) {
    passed = false;
  } finally {
    await directory.delete(recursive: true);
  }
  // 只输出结论，不输出测试记录、插件错误或存储位置。
  debugPrint(
    passed ? 'XDUWLAN_NATIVE_STORAGE_OK' : 'XDUWLAN_NATIVE_STORAGE_FAILED',
  );
  final controller = RecoveryController(
    service: RecoveryService(
      probe: _OfflineProbe(),
      portal: _UnusedPortal(),
      store: store,
    ),
    store: store,
  );
  runApp(XduwlanApp(controller: controller));
}

class _OfflineProbe implements NetworkProbe {
  @override
  Future<NetworkState> check(OperationScope scope) async =>
      NetworkState.unknown;
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

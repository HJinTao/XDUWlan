import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:xduwlan_app/core/domain.dart';
import 'package:xduwlan_app/platform/desktop_host.dart';

class MemoryStartup implements LaunchAtStartup {
  bool enabled = false;
  bool rejectChange = false;
  String? path;
  List<String>? arguments;

  @override
  void setup({
    required String appName,
    required String appPath,
    String? packageName,
    List<String> args = const [],
  }) {
    path = appPath;
    arguments = args;
  }

  @override
  Future<bool> isEnabled() async => enabled;
  @override
  Future<bool> enable() async {
    if (!rejectChange) enabled = true;
    return true;
  }

  @override
  Future<bool> disable() async {
    if (!rejectChange) enabled = false;
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const windows = MethodChannel('window_manager');
  const lifecycle = MethodChannel('xduwlan/lifecycle');
  const notifications = MethodChannel('local_notifier');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    messenger.setMockMethodCallHandler(windows, (call) async {
      calls.add(call);
      if (call.method.startsWith('is')) return false;
      return true;
    });
    messenger.setMockMethodCallHandler(lifecycle, (call) async {
      calls.add(call);
      return true;
    });
    messenger.setMockMethodCallHandler(notifications, (call) async {
      calls.add(call);
      return true;
    });
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(windows, null);
    messenger.setMockMethodCallHandler(lifecycle, null);
    messenger.setMockMethodCallHandler(notifications, null);
  });

  Future<void> emit(MethodChannel channel, MethodCall call) async {
    await messenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(call),
      (_) {},
    );
  }

  test('后台初始化保留关闭拦截并将睡眠和唤醒交给运行时', () async {
    final host = PluginDesktopHost(targetPlatform: TargetPlatform.macOS);
    var closed = 0;
    var suspended = 0;
    var resumed = 0;
    expect(calls, isEmpty);
    await host.initializeWindow(
      background: true,
      onClose: () => closed++,
      onSuspend: () => suspended++,
      onResume: () => resumed++,
    );
    expect(calls.any((call) => call.method == 'show'), isFalse);
    expect(
      calls.lastWhere((call) => call.method == 'setPreventClose').arguments,
      {'isPreventClose': true},
    );
    await emit(windows, const MethodCall('onEvent', {'eventName': 'close'}));
    await emit(lifecycle, const MethodCall('suspend'));
    await emit(lifecycle, const MethodCall('resume'));
    expect((closed, suspended, resumed), (1, 1, 1));
    await host.exit();
    await emit(lifecycle, const MethodCall('resume'));
    expect(resumed, 1);
  });

  test('退出先于窗口初始化完成时不会重新展示窗口', () async {
    final entered = Completer<void>();
    final release = Completer<void>();
    messenger.setMockMethodCallHandler(windows, (call) async {
      calls.add(call);
      if (call.method == 'ensureInitialized') {
        entered.complete();
        await release.future;
      }
      if (call.method.startsWith('is')) return false;
      return true;
    });
    final host = PluginDesktopHost(targetPlatform: TargetPlatform.macOS);
    final initialization = host.initializeWindow(
      background: false,
      onClose: () {},
      onSuspend: () {},
      onResume: () {},
    );
    await entered.future;
    await host.exit();
    release.complete();
    await initialization;
    expect(calls.any((call) => call.method == 'show'), isFalse);
  });

  test('没有托盘面板 host 时返回失败和 AppIndicator 建议', () async {
    messenger.setMockMethodCallHandler(lifecycle, (call) async => false);
    final host = PluginDesktopHost(targetPlatform: TargetPlatform.linux);
    await expectLater(
      host.initializeTray((_) {}),
      throwsA(isA<PlatformException>()),
    );
    expect(host.trayAdvice, contains('AppIndicator'));
    await host.exit();
  });

  test('macOS 退出经先回包的原生通道终止应用', () async {
    final host = PluginDesktopHost(targetPlatform: TargetPlatform.macOS);
    await host.exit();
    expect(calls.where((call) => call.method == 'terminate'), hasLength(1));
    expect(calls.any((call) => call.method == 'destroy'), isFalse);
  });

  test('Windows 退出保持使用窗口插件销毁', () async {
    final host = PluginDesktopHost(targetPlatform: TargetPlatform.windows);
    await host.exit();
    expect(calls.where((call) => call.method == 'destroy'), hasLength(1));
    expect(calls.any((call) => call.method == 'terminate'), isFalse);
  });

  test('登录启动总是传后台参数并返回读回的真实状态', () async {
    final startup = MemoryStartup();
    final host = PluginDesktopHost(
      startup: startup,
      targetPlatform: TargetPlatform.windows,
      executable: r'C:\Program Files\XDUWlan\xduwlan.exe',
    );
    expect(startup.path, isNull);
    expect(await host.initializeStartup(), isFalse);
    expect(startup.path, r'"C:\Program Files\XDUWlan\xduwlan.exe"');
    expect(startup.arguments, ['--background']);
    expect(await host.setLaunchAtStartup(true), isTrue);
    startup.rejectChange = true;
    await expectLater(
      host.setLaunchAtStartup(false),
      throwsA(isA<PlatformException>()),
    );
  });

  test('Linux Exec 对路径中的字段码和保留字符安全编码', () async {
    final startup = MemoryStartup();
    final host = PluginDesktopHost(
      startup: startup,
      targetPlatform: TargetPlatform.linux,
      executable: '/opt/XDU Wlan/100%/\$tool',
    );
    await host.initializeStartup();
    expect(startup.path, r'"/opt/XDU Wlan/100%%/\\$tool"');
  });

  test('认证通知仅包含安全结果并复用同一通知', () async {
    final host = PluginDesktopHost(targetPlatform: TargetPlatform.macOS);
    await host.initializeNotifications();
    final report = OperationReport(
      kind: OperationKind.authenticate,
      source: OperationSource.tray,
      network: NetworkState.online,
      outcome: RecoveryOutcome.restored,
      failure: null,
      elapsed: const Duration(seconds: 1),
      completedAt: DateTime(2026),
    );
    await host.notifyAuthentication(report);
    await host.notifyAuthentication(report);
    final sent = calls.where((call) => call.method == 'notify').toList();
    expect(sent, hasLength(2));
    expect((sent.first.arguments as Map)['body'], '校园网认证成功。');
    expect(
      (sent.first.arguments as Map)['identifier'],
      (sent.last.arguments as Map)['identifier'],
    );
    await host.exit();
  });
}

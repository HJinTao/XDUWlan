import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xduwlan_app/application/settings.dart';
import 'package:xduwlan_app/core/domain.dart';

import 'runtime_fakes.dart';

void main() {
  test('同步装配无外部操作，初始化任务并行挂起且账号仍可保存', () async {
    final h = RuntimeHarness();
    addTearDown(h.dispose);
    h.settings.pending = Completer<AppSettings>();
    for (final name in ['tray', 'startup', 'notifications', 'window']) {
      h.desktop.pending[name] = Completer<void>();
    }
    expect(h.desktop.started, isEmpty);
    expect(h.probe.calls, 0);
    final initialized = h.runtime.initialize();
    expect(h.desktop.started.toSet(), {
      'tray',
      'startup',
      'notifications',
      'window',
    });
    expect(h.runtime.settingsReady, isFalse);
    expect(
      await h.recovery.saveAccount(
        const Credentials('new-user', 'new-password'),
      ),
      isTrue,
    );
    expect(h.probe.calls, 0);
    h.settings.pending!.complete(const AppSettings());
    for (final task in h.desktop.pending.values) {
      task.complete();
    }
    await initialized;
    expect(h.runtime.initialized, isTrue);
    expect(h.probe.calls, 1);
  });

  test('在线每60秒一轮，空闲只有一个一次性计时器，关闭后仅手动工作', () {
    fakeAsync((time) {
      final h = RuntimeHarness();
      h.runtime.initialize();
      time.flushMicrotasks();
      expect(h.probe.calls, 1);
      expect(time.nonPeriodicTimerCount, 1);
      expect(time.periodicTimerCount, 0);
      time.elapse(const Duration(seconds: 59));
      time.flushMicrotasks();
      expect(h.probe.calls, 1);
      time.elapse(const Duration(seconds: 1));
      time.flushMicrotasks();
      expect(h.probe.calls, 2);
      expect(time.nonPeriodicTimerCount, 1);
      h.runtime.setAutomaticRecovery(false);
      time.flushMicrotasks();
      expect(h.settings.value.automaticRecoveryEnabled, isFalse);
      expect(time.nonPeriodicTimerCount, 0);
      time.elapse(const Duration(minutes: 10));
      time.flushMicrotasks();
      expect(h.probe.calls, 2);
      h.runtime.check(OperationSource.tray);
      time.flushMicrotasks();
      expect(h.probe.calls, 3);
      expect(h.recovery.lastReport!.source, OperationSource.tray);
      h.dispose();
    });
  });

  test('临时失败按30/60/300秒退避，联网后重置', () {
    fakeAsync((time) {
      final h = RuntimeHarness();
      h.probe.state = NetworkState.unavailable;
      h.runtime.initialize();
      time.flushMicrotasks();
      for (final seconds in [30, 60, 300, 300]) {
        final calls = h.probe.calls;
        time.elapse(Duration(seconds: seconds - 1));
        time.flushMicrotasks();
        expect(h.probe.calls, calls);
        time.elapse(const Duration(seconds: 1));
        time.flushMicrotasks();
        expect(h.probe.calls, calls + 1);
      }
      h.probe.state = NetworkState.online;
      time.elapse(const Duration(minutes: 5));
      time.flushMicrotasks();
      h.probe.state = NetworkState.unavailable;
      time.elapse(const Duration(seconds: 60));
      time.flushMicrotasks();
      final calls = h.probe.calls;
      time.elapse(const Duration(seconds: 30));
      time.flushMicrotasks();
      expect(h.probe.calls, calls + 1);
      h.dispose();
    });
  });

  for (final code in [
    FailureCode.credentialsMissing,
    FailureCode.authRejected,
  ]) {
    test('账号错误${code.name}暂停自动认证，保存后立即恢复', () {
      fakeAsync((time) {
        final h = RuntimeHarness();
        h.probe.state = NetworkState.portalRequired;
        if (code == FailureCode.credentialsMissing) {
          h.accounts.value = null;
        } else {
          h.portal.failure = code;
        }
        h.runtime.initialize();
        time.flushMicrotasks();
        expect(h.runtime.authenticationPaused, isTrue);
        final reads = h.accounts.reads;
        time.elapse(const Duration(minutes: 5));
        time.flushMicrotasks();
        expect(h.accounts.reads, reads);
        expect(h.recovery.lastReport!.kind, OperationKind.check);
        h.portal.failure = null;
        h.portal.restoreProbe = h.probe;
        h.recovery.saveAccount(
          const Credentials('fixed-user', 'fixed-password'),
        );
        time.flushMicrotasks();
        time.elapse(Duration.zero);
        time.flushMicrotasks();
        expect(h.runtime.authenticationPaused, isFalse);
        expect(h.recovery.network, NetworkState.online);
        expect(h.portal.calls, code == FailureCode.credentialsMissing ? 1 : 2);
        h.dispose();
      });
    });
  }

  test('隐藏不取消任务，休眠不补跑，恢复立即检查，显式退出释放并取消', () {
    fakeAsync((time) {
      final h = RuntimeHarness(background: true);
      h.runtime.initialize();
      time.flushMicrotasks();
      expect(h.desktop.background, isTrue);
      expect(h.desktop.shows, 0);
      h.desktop.close!();
      time.flushMicrotasks();
      expect(h.desktop.hides, 1);
      h.desktop.suspend!();
      expect(time.nonPeriodicTimerCount, 0);
      time.elapse(const Duration(hours: 6));
      time.flushMicrotasks();
      expect(h.probe.calls, 1);
      h.desktop.resume!();
      time.flushMicrotasks();
      expect(h.probe.calls, 2);
      h.probe.pending = Completer<NetworkState>();
      h.runtime.authenticate(OperationSource.manual);
      time.flushMicrotasks();
      h.desktop.close!();
      time.flushMicrotasks();
      expect(h.probe.scope!.isCancelled, isFalse);
      h.runtime.exit();
      time.flushMicrotasks();
      expect(h.probe.scope!.isCancelled, isTrue);
      expect(h.desktop.disposed, ['tray', 'exit']);
      expect(time.nonPeriodicTimerCount, 0);
      h.probe.pending!.complete(NetworkState.online);
      time.flushMicrotasks();
      h.dispose();
    });
  });

  test('托盘失败关闭退出，通知与设置损坏不妨碍恢复，启动项失败回退实际状态', () async {
    final h = RuntimeHarness(background: true);
    addTearDown(h.dispose);
    h.desktop.failures.addAll(['tray', 'notifications', 'startupChange']);
    h.settings.failLoad = true;
    await h.runtime.initialize();
    expect(h.runtime.trayAvailable, isFalse);
    expect(h.runtime.trayError, isNotNull);
    expect(h.runtime.notificationError, isNotNull);
    expect(h.runtime.settingsError, isNotNull);
    expect(h.probe.calls, 1);
    expect(h.desktop.shows, 1);
    await h.runtime.setLaunchAtStartup(true);
    expect(h.runtime.settings.launchAtStartup, isFalse);
    expect(h.runtime.startupError, isNotNull);
    await h.runtime.closeWindow();
    expect(h.desktop.disposed, ['tray', 'exit']);
  });

  test('失败通知去重、失败类别改变或联网恢复后允许再通知，普通检查不通知', () {
    fakeAsync((time) {
      final h = RuntimeHarness();
      h.probe.state = NetworkState.portalRequired;
      h.portal.failure = FailureCode.protocol;
      h.runtime.initialize();
      time.flushMicrotasks();
      expect(h.desktop.notifications, hasLength(1));
      time.elapse(const Duration(seconds: 30));
      time.flushMicrotasks();
      expect(h.desktop.notifications, hasLength(1));
      h.portal.failure = FailureCode.authRejected;
      time.elapse(const Duration(seconds: 60));
      time.flushMicrotasks();
      expect(h.desktop.notifications, hasLength(2));
      time.elapse(const Duration(minutes: 5));
      time.flushMicrotasks();
      expect(h.desktop.notifications, hasLength(2));
      h.probe.state = NetworkState.online;
      h.runtime.check(OperationSource.manual);
      time.flushMicrotasks();
      h.probe.state = NetworkState.portalRequired;
      h.portal.failure = null;
      h.portal.restoreProbe = h.probe;
      h.runtime.authenticate(OperationSource.manual);
      time.flushMicrotasks();
      expect(h.desktop.notifications, hasLength(2));
      h.probe.state = NetworkState.portalRequired;
      time.elapse(const Duration(seconds: 60));
      time.flushMicrotasks();
      expect(h.desktop.notifications, hasLength(3));
      expect(h.desktop.notifications.last.outcome, RecoveryOutcome.restored);
      expect(h.diagnostics.records.length, 7);
      h.dispose();
    });
  });

  test('通知不可用时托盘仍显示自动认证的安全失败原因', () async {
    final h = RuntimeHarness();
    addTearDown(h.dispose);
    h.desktop.failures.add('notifications');
    h.probe.state = NetworkState.portalRequired;
    h.portal.failure = FailureCode.authRejected;
    await h.runtime.initialize();
    await Future<void>.delayed(Duration.zero);
    expect(h.desktop.menu.last.status, contains('认证未通过'));
    expect(h.desktop.menu.last.status, isNot(contains('test-user')));
    expect(h.desktop.notifications, isEmpty);
  });

  test('普通检查改变失败类别不通知，下一次自动认证相同旧失败可再次通知', () {
    fakeAsync((time) {
      final h = RuntimeHarness();
      h.probe.state = NetworkState.portalRequired;
      h.portal.failure = FailureCode.protocol;
      h.runtime.initialize();
      time.flushMicrotasks();
      expect(h.desktop.notifications, hasLength(1));
      h.probe.state = NetworkState.unavailable;
      h.runtime.check(OperationSource.manual);
      time.flushMicrotasks();
      expect(h.desktop.notifications, hasLength(1));
      h.probe.state = NetworkState.portalRequired;
      time.elapse(const Duration(seconds: 60));
      time.flushMicrotasks();
      expect(h.desktop.notifications, hasLength(2));
      h.dispose();
    });
  });

  test('诊断失败不阻塞认证，记录每轮一次并能清空', () async {
    final h = RuntimeHarness();
    addTearDown(h.dispose);
    h.diagnostics.fail = true;
    h.probe.state = NetworkState.portalRequired;
    h.portal.restoreProbe = h.probe;
    await h.runtime.initialize();
    await Future<void>.delayed(Duration.zero);
    expect(h.recovery.network, NetworkState.online);
    expect(h.runtime.diagnosticsError, isNotNull);
    h.diagnostics.fail = false;
    await h.runtime.check(OperationSource.manual);
    await h.runtime.flushDiagnostics();
    expect(h.runtime.records, hasLength(1));
    await h.runtime.clearDiagnostics();
    expect(h.runtime.records, isEmpty);
    expect(h.diagnostics.records, isEmpty);
  });

  test('托盘先失败且窗口晚初始化，后台启动最终保留可见窗口', () async {
    final h = RuntimeHarness(background: true);
    addTearDown(h.dispose);
    h.desktop.failures.add('tray');
    h.desktop.pending['window'] = Completer<void>();
    final initialized = h.runtime.initialize();
    await Future<void>.delayed(Duration.zero);
    h.desktop.pending['window']!.complete();
    await initialized;
    expect(h.runtime.trayAvailable, isFalse);
    expect(h.desktop.visible, isTrue);
  });

  test('自动拒绝之后排队的手动认证成功解除暂停并继续自动恢复', () {
    fakeAsync((time) {
      final h = RuntimeHarness();
      h.probe.state = NetworkState.portalRequired;
      h.portal.pendingAuthentication = Completer<void>();
      h.portal.firstFailure = FailureCode.authRejected;
      h.portal.restoreProbe = h.probe;
      h.runtime.initialize();
      time.flushMicrotasks();
      h.runtime.authenticate(OperationSource.manual);
      time.flushMicrotasks();
      h.portal.pendingAuthentication!.complete();
      time.flushMicrotasks();
      expect(h.recovery.network, NetworkState.online);
      expect(h.runtime.authenticationPaused, isFalse);
      h.probe.state = NetworkState.portalRequired;
      time.elapse(const Duration(seconds: 60));
      time.flushMicrotasks();
      expect(h.portal.calls, 3);
      h.dispose();
    });
  });

  test('自动设置保存挂起时启动项读回实际状态，两个状态仍准确持久化', () async {
    final h = RuntimeHarness();
    addTearDown(h.dispose);
    h.desktop.enabled = true;
    h.desktop.pending['startup'] = Completer<void>();
    final initialized = h.runtime.initialize();
    await Future<void>.delayed(Duration.zero);
    h.settings.pendingSave = Completer<void>();
    final saving = h.runtime.setAutomaticRecovery(false);
    h.desktop.pending['startup']!.complete();
    await Future<void>.delayed(Duration.zero);
    h.settings.pendingSave!.complete();
    await saving;
    await initialized;
    expect(h.runtime.settings.automaticRecoveryEnabled, isFalse);
    expect(h.runtime.settings.launchAtStartup, isTrue);
    expect(h.settings.value.launchAtStartup, isTrue);
  });

  test('启动项先准备完但设置仍挂起时不能用默认值覆盖旧自动恢复开关', () async {
    final h = RuntimeHarness();
    addTearDown(h.dispose);
    h.settings.value = const AppSettings(automaticRecoveryEnabled: false);
    h.settings.pending = Completer<AppSettings>();
    final initialized = h.runtime.initialize();
    await Future<void>.delayed(Duration.zero);
    expect(h.runtime.startupReady, isTrue);
    await h.runtime.setLaunchAtStartup(true);
    expect(h.desktop.enabled, isFalse);
    expect(h.settings.value.automaticRecoveryEnabled, isFalse);
    h.settings.pending!.complete(h.settings.value);
    await initialized;
    expect(h.probe.calls, 0);
  });

  test('启动项以真实系统状态显示，保存失败自动恢复开关回退', () async {
    final h = RuntimeHarness();
    addTearDown(h.dispose);
    h.desktop.enabled = true;
    await h.runtime.initialize();
    expect(h.runtime.settings.launchAtStartup, isTrue);
    h.settings.failSave = true;
    await h.runtime.setAutomaticRecovery(false);
    expect(h.runtime.settings.automaticRecoveryEnabled, isTrue);
    expect(h.runtime.settingsError, isNotNull);
  });
}

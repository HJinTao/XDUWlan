import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:xduwlan_app/application/recovery_controller.dart';
import 'package:xduwlan_app/application/recovery_service.dart';
import 'package:xduwlan_app/core/domain.dart';

import 'recovery_service_test.dart' as fakes;

class PendingProbe implements NetworkProbe {
  int calls = 0;
  final pending = Completer<NetworkState>();
  @override
  Future<NetworkState> check(OperationScope scope) {
    calls++;
    return pending.future;
  }
}

void main() {
  test('旧在线结果不能冒充失败或取消后的当前联网状态', () async {
    final store = fakes.Store();
    final probe = _ChangingProbe();
    final controller = RecoveryController(
      service: RecoveryService(
        probe: probe,
        portal: fakes.Portal(),
        store: store,
      ),
      store: store,
    );
    await controller.refresh();
    expect(controller.network, NetworkState.online);
    probe.fail = true;
    await controller.refresh();
    expect(controller.network, NetworkState.unknown);
    expect(controller.failure, FailureCode.networkUnavailable);
    probe.fail = false;
    await controller.refresh();
    probe.pending = Completer<NetworkState>();
    final request = controller.refresh();
    controller.setForeground(false);
    await request;
    expect(controller.network, NetworkState.unknown);
    probe.pending!.complete(NetworkState.online);
    controller.dispose();
  });

  test('重复触发只执行一轮，迟到结果不覆盖取消后的状态', () async {
    final probe = PendingProbe();
    final store = fakes.Store();
    final controller = RecoveryController(
      service: RecoveryService(
        probe: probe,
        portal: fakes.Portal(),
        store: store,
      ),
      store: store,
    );
    final first = controller.login();
    await controller.login();
    expect(controller.busy, isTrue);
    expect(probe.calls, 1);
    controller.setForeground(false);
    await first;
    probe.pending.complete(NetworkState.online);
    await Future<void>.delayed(Duration.zero);
    expect(controller.busy, isFalse);
    expect(controller.network, NetworkState.unknown);
    expect(store.reads, 0);
    controller.dispose();
  });

  test('保存时校验账号并保留密码两侧空格', () async {
    final store = fakes.Store();
    final controller = RecoveryController(
      service: RecoveryService(
        probe: fakes.Probe([]),
        portal: fakes.Portal(),
        store: store,
      ),
      store: store,
    );
    expect(
      await controller.saveAccount(const Credentials('', 'value')),
      isFalse,
    );
    expect(controller.failure, FailureCode.credentialsInvalid);
    expect(
      await controller.saveAccount(
        const Credentials(' fake-user ', ' spaced-password '),
      ),
      isTrue,
    );
    expect(store.value!.username, 'fake-user');
    expect(store.value!.password, ' spaced-password ');
    controller.dispose();
  });

  test('读取已配置账号不触发网络检查', () async {
    final store = fakes.Store()
      ..value = const Credentials('fake-user', 'fake-password');
    final probe = fakes.Probe([]);
    final controller = RecoveryController(
      service: RecoveryService(
        probe: probe,
        portal: fakes.Portal(),
        store: store,
      ),
      store: store,
    );

    expect(await controller.loadAccount(), store.value);
    controller.dispose();
  });
}

class _ChangingProbe implements NetworkProbe {
  bool fail = false;
  Completer<NetworkState>? pending;
  @override
  Future<NetworkState> check(OperationScope scope) async {
    if (fail) throw const AppFailure(FailureCode.networkUnavailable);
    if (pending != null) return pending!.future;
    return NetworkState.online;
  }
}

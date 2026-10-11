import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:xduwlan_app/application/recovery_controller.dart';
import 'package:xduwlan_app/application/recovery_service.dart';
import 'package:xduwlan_app/core/domain.dart';

import 'recovery_service_test.dart' as fakes;

void main() {
  test('检查返回独立安全报告，失败不能沿用旧在线状态', () async {
    final probe = _Probe();
    final controller = _controller(probe);
    addTearDown(controller.dispose);
    final report = await controller.run(
      OperationKind.check,
      OperationSource.tray,
    );
    expect(report!.network, NetworkState.online);
    expect(report.kind, OperationKind.check);
    expect(report.source, OperationSource.tray);
    expect(report.outcome, isNull);
    expect(controller.lastCheckAt, report.completedAt);
    probe.fail = true;
    final failed = await controller.run(
      OperationKind.check,
      OperationSource.manual,
    );
    expect(failed!.failure, FailureCode.networkUnavailable);
    expect(controller.network, NetworkState.unknown);
    expect(report.network, NetworkState.online);
  });

  test('自动检查后认证只执行一次初始探测并生成一条报告', () async {
    final probe = _Probe()
      ..states.addAll([NetworkState.portalRequired, NetworkState.online]);
    final store = fakes.Store();
    final portal = fakes.Portal();
    final controller = _controller(probe, store: store, portal: portal);
    addTearDown(controller.dispose);
    final reports = <OperationReport>[];
    controller.addListener(() {
      final report = controller.lastReport;
      if (report != null && !reports.contains(report)) reports.add(report);
    });
    final report = await controller.run(
      OperationKind.check,
      OperationSource.automatic,
      allowAuthentication: true,
    );
    expect(report!.kind, OperationKind.authenticate);
    expect(report.outcome, RecoveryOutcome.restored);
    expect(probe.calls, 2);
    expect(reports, hasLength(1));
    expect(portal.calls, ['prepare', 'authenticate']);
    expect(controller.lastCheckAt, report.completedAt);
    expect(controller.lastAuthenticateAt, report.completedAt);
  });

  test('自动操作期间手动与托盘意图合并排队，保留请求种类并立即执行', () async {
    final probe = _Probe()..pending = Completer<NetworkState>();
    final controller = _controller(probe);
    addTearDown(controller.dispose);
    final first = controller.run(
      OperationKind.check,
      OperationSource.automatic,
    );
    final second = controller.run(OperationKind.check, OperationSource.tray);
    final third = controller.run(
      OperationKind.authenticate,
      OperationSource.manual,
    );
    expect(probe.calls, 1);
    expect(controller.manualPending, isTrue);
    probe.pending!.complete(NetworkState.online);
    final firstReport = await first;
    final queuedReport = await third;
    expect(firstReport!.kind, OperationKind.check);
    expect(firstReport.source, OperationSource.automatic);
    expect(queuedReport!.kind, OperationKind.authenticate);
    expect(queuedReport.source, OperationSource.manual);
    expect(await second, same(queuedReport));
    expect(probe.calls, 2);
    expect(probe.maxConcurrent, 1);
    expect(controller.busy, isFalse);
  });

  test('隐藏窗口不取消或禁止认证，退出取消并消费迟到结果', () async {
    final probe = _Probe()..pending = Completer<NetworkState>();
    final store = fakes.Store();
    final controller = _controller(probe, store: store);
    final first = controller.run(
      OperationKind.authenticate,
      OperationSource.manual,
    );
    controller.setForeground(false);
    expect(controller.busy, isTrue);
    expect(probe.scope!.isCancelled, isFalse);
    final queued = controller.run(OperationKind.check, OperationSource.tray);
    controller.shutdown();
    expect(probe.scope!.isCancelled, isTrue);
    expect((await first)!.failure, FailureCode.cancelled);
    expect(await queued, isNull);
    probe.pending!.complete(NetworkState.online);
    await Future<void>.delayed(Duration.zero);
    expect(store.reads, 0);
    expect(controller.network, NetworkState.unknown);
    controller.dispose();
  });

  test('保存账号可在自动操作中执行，账号改变只在保存成功后发布', () async {
    final probe = _Probe()..pending = Completer<NetworkState>();
    final store = fakes.Store();
    final controller = _controller(probe, store: store);
    addTearDown(controller.dispose);
    final first = controller.run(
      OperationKind.check,
      OperationSource.automatic,
    );
    expect(
      await controller.saveAccount(const Credentials('', 'value')),
      isFalse,
    );
    expect(controller.accountRevision, 0);
    expect(
      await controller.saveAccount(
        const Credentials(' fake-user ', ' spaced-password '),
      ),
      isTrue,
    );
    expect(store.value!.username, 'fake-user');
    expect(store.value!.password, ' spaced-password ');
    expect(controller.accountRevision, 1);
    expect(controller.busy, isTrue);
    probe.pending!.complete(NetworkState.online);
    await first;
  });

  test('读取账号不发起网络请求或更改操作结果', () async {
    final store = fakes.Store();
    final probe = _Probe();
    final controller = _controller(probe, store: store);
    addTearDown(controller.dispose);
    controller.failure = FailureCode.authRejected;
    expect(await controller.loadAccount(), same(store.value));
    expect(probe.calls, 0);
    expect(controller.failure, FailureCode.authRejected);
  });
}

RecoveryController _controller(
  _Probe probe, {
  fakes.Store? store,
  fakes.Portal? portal,
}) {
  final credentials = store ?? fakes.Store();
  return RecoveryController(
    service: RecoveryService(
      probe: probe,
      portal: portal ?? fakes.Portal(),
      store: credentials,
    ),
    store: credentials,
  );
}

class _Probe implements NetworkProbe {
  bool fail = false;
  Completer<NetworkState>? pending;
  OperationScope? scope;
  int calls = 0;
  int concurrent = 0;
  int maxConcurrent = 0;
  final states = <NetworkState>[];
  @override
  Future<NetworkObservation> check(OperationScope scope) async {
    this.scope = scope;
    calls++;
    concurrent++;
    if (concurrent > maxConcurrent) maxConcurrent = concurrent;
    try {
      if (fail) throw const AppFailure(FailureCode.networkUnavailable);
      final state = pending != null && calls == 1
          ? await pending!.future
          : states.isEmpty
              ? NetworkState.online
              : states.removeAt(0);
      return NetworkObservation(
        link: state == NetworkState.portalRequired
            ? NetworkLink.wifi
            : NetworkLink.unknown,
        campus: switch (state) {
          NetworkState.portalRequired =>
            CampusNetworkState.authenticationRequired,
          NetworkState.online => CampusNetworkState.online,
          NetworkState.unavailable => CampusNetworkState.unavailable,
          NetworkState.unknown => CampusNetworkState.unknown,
        },
        portal: state,
        authenticationAllowed: state == NetworkState.portalRequired,
      );
    } finally {
      concurrent--;
    }
  }
}

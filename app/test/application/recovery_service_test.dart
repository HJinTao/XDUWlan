import 'package:flutter_test/flutter_test.dart';
import 'package:xduwlan_app/application/recovery_service.dart';
import 'package:xduwlan_app/core/domain.dart';

class Probe implements NetworkProbe {
  final List<NetworkState> states;
  Probe(this.states);
  @override
  Future<NetworkObservation> check(OperationScope scope) async =>
      _observation(states.removeAt(0));
}

NetworkObservation _observation(NetworkState state) => NetworkObservation(
  link: state == NetworkState.portalRequired
      ? NetworkLink.wifi
      : NetworkLink.unknown,
  campus: switch (state) {
    NetworkState.portalRequired => CampusNetworkState.authenticationRequired,
    NetworkState.online => CampusNetworkState.online,
    NetworkState.unavailable => CampusNetworkState.unavailable,
    NetworkState.unknown => CampusNetworkState.unknown,
  },
  portal: state,
  authenticationAllowed: state == NetworkState.portalRequired,
);

class Store implements CredentialStore {
  int reads = 0;
  Credentials? value = const Credentials('fake-user', 'fake-password');
  @override
  Future<Credentials?> load() async {
    reads++;
    return value;
  }

  @override
  Future<void> save(Credentials credentials) async {
    value = credentials;
  }
}

class Portal implements PortalClient {
  final List<String> calls = [];
  AppFailure? error;
  bool cancelDuringPrepare = false;
  @override
  Future<PortalContext> prepare(OperationScope scope) async {
    calls.add('prepare');
    if (cancelDuringPrepare) scope.cancel();
    return PortalContext(Uri.parse('https://portal.invalid'), '192.0.2.1', '1');
  }

  @override
  Future<void> authenticate(
    PortalContext context,
    Credentials credentials,
    OperationScope scope, {
    required Future<void> Function() beforeSubmit,
  }) async {
    calls.add('authenticate');
    await beforeSubmit();
    if (error != null) throw error!;
  }
}

void main() {
  test('阶段通知中取消不会启动尚未创建的探测任务', () async {
    final probe = _CancelAwareProbe();
    final scope = OperationScope();
    final service = RecoveryService(
      probe: probe,
      portal: Portal(),
      store: Store(),
    );
    final result = await service.login(scope, onStage: (_) => scope.cancel());
    expect(result.outcome, RecoveryOutcome.cancelled);
    expect(probe.calls, 0);
    scope.finish();
  });

  test('已联网和未知状态均不读取凭据或请求认证', () async {
    for (final state in [NetworkState.online, NetworkState.unknown]) {
      final store = Store();
      final portal = Portal();
      final scope = OperationScope();
      final service = RecoveryService(
        probe: Probe([state]),
        portal: portal,
        store: store,
      );
      final result = await service.login(scope);
      expect(result.network, state);
      expect(
        result.outcome,
        state == NetworkState.online
            ? RecoveryOutcome.alreadyOnline
            : RecoveryOutcome.failed,
      );
      expect(store.reads, 0);
      expect(portal.calls, isEmpty);
      scope.finish();
    }
  });

  test('认证后必须独立联网验证才能报告恢复', () async {
    final store = Store();
    final portal = Portal();
    final stages = <RecoveryStage>[];
    final scope = OperationScope();
    final result = await RecoveryService(
      probe: Probe([NetworkState.portalRequired, NetworkState.online]),
      portal: portal,
      store: store,
    ).login(scope, onStage: stages.add);
    expect(result.outcome, RecoveryOutcome.restored);
    expect(store.reads, 1);
    expect(portal.calls, ['prepare', 'authenticate']);
    expect(scope.submitted, isTrue);
    expect(stages, [
      RecoveryStage.checking,
      RecoveryStage.preparing,
      RecoveryStage.authenticating,
      RecoveryStage.verifying,
    ]);
    scope.finish();
  });

  test('上下文获取时取消后不得读取密码', () async {
    final store = Store();
    final portal = Portal()..cancelDuringPrepare = true;
    final scope = OperationScope();
    final result = await RecoveryService(
      probe: Probe([NetworkState.portalRequired]),
      portal: portal,
      store: store,
    ).login(scope);
    expect(result.outcome, RecoveryOutcome.cancelled);
    expect(store.reads, 0);
    expect(portal.calls, ['prepare']);
    scope.finish();
  });

  test('缺失凭据不提交认证，服务拒绝不会自动重试', () async {
    final store = Store()..value = null;
    final portal = Portal();
    var scope = OperationScope();
    var result = await RecoveryService(
      probe: Probe([NetworkState.portalRequired]),
      portal: portal,
      store: store,
    ).login(scope);
    expect(result.failure, FailureCode.credentialsMissing);
    expect(portal.calls, ['prepare']);
    scope.finish();
    store.value = const Credentials('fake-user', 'fake-password');
    portal.calls.clear();
    portal.error = const AppFailure(FailureCode.authRejected);
    scope = OperationScope();
    result = await RecoveryService(
      probe: Probe([NetworkState.portalRequired]),
      portal: portal,
      store: store,
    ).login(scope);
    expect(result.failure, FailureCode.authRejected);
    expect(portal.calls, ['prepare', 'authenticate']);
    scope.finish();
  });

  test('提交后超时与复查失败保留未确认状态', () async {
    final store = Store();
    final portal = Portal()..error = const AppFailure(FailureCode.timeout);
    var scope = OperationScope();
    var result = await RecoveryService(
      probe: Probe([NetworkState.portalRequired]),
      portal: portal,
      store: store,
    ).login(scope);
    expect(result.failure, FailureCode.submittedUnconfirmed);
    scope.finish();
    portal.error = null;
    scope = OperationScope();
    result = await RecoveryService(
      probe: Probe([NetworkState.portalRequired, NetworkState.unknown]),
      portal: portal,
      store: store,
    ).login(scope);
    expect(result.failure, FailureCode.verificationFailed);
    expect(result.outcome, RecoveryOutcome.failed);
    scope.finish();
  });

  authenticationGateTests();
}

class _CancelAwareProbe implements NetworkProbe {
  int calls = 0;
  @override
  Future<NetworkObservation> check(OperationScope scope) async {
    calls++;
    scope.ensureActive();
    return _observation(NetworkState.online);
  }
}

class ObservationProbe implements NetworkProbe {
  ObservationProbe(this.observation);
  final NetworkObservation observation;
  int calls = 0;

  @override
  Future<NetworkObservation> check(OperationScope scope) async {
    calls++;
    return observation;
  }
}

void authenticationGateTests() {
  test('认证门在读取凭据前拒绝非校园 Wi-Fi', () async {
    final store = Store();
    final portal = Portal();
    final probe = ObservationProbe(
      const NetworkObservation(
        link: NetworkLink.cellular,
        campus: CampusNetworkState.authenticationRequired,
        portal: NetworkState.portalRequired,
        authenticationAllowed: false,
      ),
    );
    final scope = OperationScope();
    final result = await RecoveryService(
      probe: probe,
      portal: portal,
      store: store,
    ).login(scope);
    expect(result.failure, FailureCode.authenticationNotAllowed);
    expect(store.reads, 0);
    expect(portal.calls, isEmpty);
    scope.finish();
  });

  test('认证门不信任与链路状态矛盾的允许标志', () async {
    final store = Store();
    final portal = Portal();
    final scope = OperationScope();
    final result = await RecoveryService(
      probe: ObservationProbe(
        const NetworkObservation(
          link: NetworkLink.cellular,
          campus: CampusNetworkState.authenticationRequired,
          portal: NetworkState.portalRequired,
          authenticationAllowed: true,
        ),
      ),
      portal: portal,
      store: store,
    ).login(scope);
    expect(result.failure, FailureCode.authenticationNotAllowed);
    expect(store.reads, 0);
    expect(portal.calls, isEmpty);
    scope.finish();
  });
}

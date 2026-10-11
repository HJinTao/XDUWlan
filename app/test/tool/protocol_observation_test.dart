import 'package:flutter_test/flutter_test.dart';
import 'package:xduwlan_app/core/domain.dart';
import 'package:xduwlan_app/core/srun_protocol.dart';
import 'package:xduwlan_app/platform/network_probe.dart';

import '../../tool/recovery_validation_support.dart';

void main() {
  test('观察结果只包含固定脱敏字段', () {
    const result = ProtocolObservation(
      candidateAccepted: true,
      encodingRulePassed: true,
      verificationState: ProtocolVerificationState.verified,
      requests: 4,
      submissions: 1,
      credentialReads: 1,
      elapsedMilliseconds: 12,
      failure: ProtocolObservationFailure.none,
    );
    expect(result.toJson(), {
      'candidateAccepted': true,
      'encodingRulePassed': true,
      'verificationState': 'verified',
      'requests': 4,
      'submissions': 1,
      'credentialReads': 1,
      'elapsedMilliseconds': 12,
      'failure': 'none',
    });
    expect(result.toString(), isNot(contains('fictional')));
  });

  test('观察结果的候选摘要和运行标识不进入 JSON', () {
    const result = ProtocolObservation(
      candidateAccepted: true,
      encodingRulePassed: true,
      verificationState: ProtocolVerificationState.verified,
      requests: 1,
      submissions: 1,
      credentialReads: 1,
      elapsedMilliseconds: 1,
      failure: ProtocolObservationFailure.none,
      candidateIdentity: 'candidate-digest',
      runIdentity: 'run-1',
    );
    expect(result.toJson(), isNot(contains('candidate-digest')));
    expect(result.toJson(), isNot(contains('run-1')));
  });

  test('内存 sink 校验同一有效用户名且不保留请求值', () {
    final sink = InMemoryProtocolObservationSink();
    final credentials = const Credentials(
      'fictional-user@campus',
      'fictional-password',
    );
    final context = PortalContext(
      Uri.parse('https://portal.example.test'),
      '192.0.2.10',
      '8',
    );
    final params = buildLoginParams(
      credentials,
      context,
      'fictional-challenge',
      'cb',
      1,
    );
    sink.inspectLoginRequest(params, credentials, context);
    expect(sink.encodingRulePassed, isTrue);
    expect(sink.toString(), isNot(contains('fictional-password')));
    expect(sink.toString(), isNot(contains('fictional-user')));
  });

  test('观察器需要 ThinkPad、单候选和独立联网复查', () async {
    final sink = InMemoryProtocolObservationSink();
    final observer = ProtocolObserver(
      probe: _Probe(),
      portal: _Portal(sink),
      store: _Credentials(),
      sink: sink,
      thinkPad: true,
    );
    final result = await observer.observe(
      candidateReader: () async => '@campus',
    );
    expect(result.candidateAccepted, isTrue);
    expect(result.verificationState, ProtocolVerificationState.verified);
    expect(result.requests, 0);
    expect(result.submissions, 1);
    expect(result.credentialReads, 1);
  });

  test('两次独立成功且至少一次 down/up 才允许提升规则', () {
    final gate = ProtocolPromotionGate();
    final reset = ProtocolResetEvidenceBuilder();
    const success = ProtocolObservation(
      candidateAccepted: true,
      encodingRulePassed: true,
      verificationState: ProtocolVerificationState.verified,
      requests: 4,
      submissions: 1,
      credentialReads: 1,
      elapsedMilliseconds: 1,
      failure: ProtocolObservationFailure.none,
      candidateIdentity: 'candidate-a',
      runIdentity: 'run-1',
    );
    gate.record(success);
    expect(gate.promotable, isFalse);
    reset.recordDownCompleted();
    final evidence = reset.recordUpCompleted();
    gate.record(
      const ProtocolObservation(
        candidateAccepted: true,
        encodingRulePassed: true,
        verificationState: ProtocolVerificationState.verified,
        requests: 4,
        submissions: 1,
        credentialReads: 1,
        elapsedMilliseconds: 1,
        failure: ProtocolObservationFailure.none,
        candidateIdentity: 'candidate-a',
        runIdentity: 'run-2',
      ),
      resetEvidence: evidence,
    );
    expect(gate.promotable, isTrue);
  });

  test('不同候选、重复运行和无 down/up 证据不能提升规则', () {
    final gate = ProtocolPromotionGate();
    const first = ProtocolObservation(
      candidateAccepted: true,
      encodingRulePassed: true,
      verificationState: ProtocolVerificationState.verified,
      requests: 1,
      submissions: 1,
      credentialReads: 1,
      elapsedMilliseconds: 1,
      failure: ProtocolObservationFailure.none,
      candidateIdentity: 'candidate-a',
      runIdentity: 'run-1',
    );
    gate.record(first);
    gate.record(first);
    gate.record(
      const ProtocolObservation(
        candidateAccepted: true,
        encodingRulePassed: true,
        verificationState: ProtocolVerificationState.verified,
        requests: 1,
        submissions: 1,
        credentialReads: 1,
        elapsedMilliseconds: 1,
        failure: ProtocolObservationFailure.none,
        candidateIdentity: 'candidate-b',
        runIdentity: 'run-2',
      ),
    );
    expect(gate.promotable, isFalse);
  });

  test('网络探测回退按真实 transport 请求计数', () async {
    final transport = _ProbeTransport();
    final sink = InMemoryProtocolObservationSink();
    final counters = ValidationCounters();
    final scope = OperationScope();
    addTearDown(scope.finish);
    final result = await IoNetworkProbe(
      transport: CountingTransport(transport, counters, observationSink: sink),
    ).check(scope);
    expect(result.portal, NetworkState.unavailable);
    expect(sink.requests, 2);
    expect(counters.requests, 2);
    expect(transport.calls, 2);
  });
}

class _Probe implements NetworkProbe {
  int calls = 0;
  @override
  Future<NetworkObservation> check(OperationScope scope) async {
    calls++;
    final state = calls == 1
        ? NetworkState.portalRequired
        : NetworkState.online;
    return NetworkObservation(
      link: state == NetworkState.portalRequired
          ? NetworkLink.wifi
          : NetworkLink.unknown,
      campus: state == NetworkState.portalRequired
          ? CampusNetworkState.authenticationRequired
          : CampusNetworkState.online,
      portal: state,
      authenticationAllowed: state == NetworkState.portalRequired,
    );
  }
}

class _Credentials implements CredentialStore {
  @override
  Future<Credentials?> load() async =>
      const Credentials('fictional-user', 'fictional-password');
  @override
  Future<void> save(Credentials credentials) async {}
}

class _Portal implements PortalClient {
  _Portal(this.sink);
  final ProtocolObservationSink sink;
  @override
  Future<PortalContext> prepare(OperationScope scope) async => PortalContext(
    Uri.parse('https://portal.example.test'),
    '192.0.2.10',
    '8',
  );
  @override
  Future<void> authenticate(
    PortalContext context,
    Credentials credentials,
    OperationScope scope, {
    required Future<void> Function() beforeSubmit,
  }) async {
    final params = buildLoginParams(
      credentials,
      context,
      'fictional-challenge',
      'cb',
      1,
    );
    sink.inspectLoginRequest(params, credentials, context);
    await beforeSubmit();
    sink.submission();
  }
}

class _ProbeTransport implements PortalTransport {
  int calls = 0;
  @override
  Future<PortalResponse> request(
    String method,
    Uri url,
    OperationScope scope,
  ) async {
    calls++;
    throw const AppFailure(FailureCode.networkUnavailable);
  }
}

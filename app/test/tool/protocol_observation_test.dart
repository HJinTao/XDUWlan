import 'package:flutter_test/flutter_test.dart';
import 'package:xduwlan_app/core/domain.dart';
import 'package:xduwlan_app/core/srun_protocol.dart';

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
    expect(result.requests, 4);
    expect(result.submissions, 1);
    expect(result.credentialReads, 1);
  });

  test('两次独立成功且至少一次 down/up 才允许提升规则', () {
    final gate = ProtocolPromotionGate();
    const success = ProtocolObservation(
      candidateAccepted: true,
      encodingRulePassed: true,
      verificationState: ProtocolVerificationState.verified,
      requests: 4,
      submissions: 1,
      credentialReads: 1,
      elapsedMilliseconds: 1,
      failure: ProtocolObservationFailure.none,
    );
    gate.record(success, afterNetworkReset: false);
    expect(gate.promotable, isFalse);
    gate.record(success, afterNetworkReset: true);
    expect(gate.promotable, isTrue);
  });
}

class _Probe implements NetworkProbe {
  int calls = 0;
  @override
  Future<NetworkState> check(OperationScope scope) async {
    calls++;
    return calls == 1 ? NetworkState.portalRequired : NetworkState.online;
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
    sink.request();
    sink.request();
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

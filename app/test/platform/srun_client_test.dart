import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:xduwlan_app/core/domain.dart';
import 'package:xduwlan_app/platform/srun_client.dart';

final portal = Uri.parse('https://portal.example.test');
final entry = Uri.parse('http://probe.example.test/generate_204');
final context = PortalContext(portal, '192.0.2.10', '8');
const credentials = Credentials('student@example.test', 'fictional-password');

class RecordingTransport implements PortalTransport {
  RecordingTransport(List<Object> replies) : replies = List.of(replies);
  final List<Object> replies;
  final List<(String, Uri)> calls = [];
  void Function(int, OperationScope)? onRequest;

  @override
  Future<PortalResponse> request(
    String method,
    Uri url,
    OperationScope scope,
  ) async {
    calls.add((method, url));
    onRequest?.call(calls.length, scope);
    final reply = replies.removeAt(0);
    if (reply is AppFailure) throw reply;
    if (reply is Future<PortalResponse>) return reply;
    if (reply is PortalResponse) return reply;
    return PortalResponse(
      200,
      '${url.queryParameters['callback']}(${jsonEncode(reply)});',
    );
  }
}

Map<String, Object> challengeReply() => {
  'error': 'ok',
  'challenge': '0123456789abcdef0123456789abcdef',
  'client_ip': '192.0.2.10',
};

SrunPortalClient client(RecordingTransport transport) => SrunPortalClient(
  transport: transport,
  portalUri: portal,
  entryUri: entry,
  clock: () => DateTime.fromMillisecondsSinceEpoch(1234),
);

Matcher failure(FailureCode code) =>
    throwsA(isA<AppFailure>().having((e) => e.code, 'code', code));

void main() {
  late OperationScope scope;
  setUp(() => scope = OperationScope());
  tearDown(() => scope.finish());

  test('初始发现入口拒绝内嵌凭据与编码控制字符', () {
    for (final value in [
      'http://user:secret@probe.example.test/',
      'http://probe.example.test/path%0a',
    ]) {
      expect(
        () => SrunPortalClient(
          transport: RecordingTransport([]),
          portalUri: portal,
          entryUri: Uri.parse(value),
        ),
        failure(FailureCode.protocol),
      );
    }
  });

  test('prepare 只沿可信空 POST 与 refresh 导航且不发送凭据', () async {
    final transport = RecordingTransport([
      const PortalResponse(
        200,
        '<form method="post" action="http://portal.example.test/index_8.html"></form>',
      ),
      const PortalResponse(
        200,
        '<meta http-equiv="refresh" content="0;url=/srun_portal_pc?ac_id=8">',
      ),
      const PortalResponse(200, 'var CONFIG={ip:"192.0.2.10",acid:"8"};'),
    ]);
    final result = await client(transport).prepare(scope);
    expect(result.origin, portal);
    expect(result.ip, '192.0.2.10');
    expect(transport.calls, [
      ('GET', entry),
      ('POST', Uri.parse('https://portal.example.test/index_8.html')),
      ('GET', Uri.parse('https://portal.example.test/srun_portal_pc?ac_id=8')),
    ]);
  });

  test('prepare 处理可信重定向且限制初始请求在内的六次导航', () async {
    final transport = RecordingTransport(
      List.filled(
        7,
        const PortalResponse(
          302,
          '',
          location: 'https://portal.example.test/loop',
        ),
      ),
    );
    await expectLater(
      client(transport).prepare(scope),
      failure(FailureCode.protocol),
    );
    expect(transport.calls.length, 6);
  });

  for (final response in [
    const PortalResponse(
      302,
      '',
      location: 'https://attacker.test/?private-marker',
    ),
    const PortalResponse(302, ''),
    const PortalResponse(
      200,
      '<form method="post" action="https://attacker.test/"></form>',
    ),
    const PortalResponse(200, 'var CONFIG={ip:"192.0.2.10",acid:"8"};'),
  ]) {
    test('prepare 不信任入口直接提供的上下文或未知目标 ${response.hashCode}', () async {
      final transport = RecordingTransport([response]);
      await expectLater(
        client(transport).prepare(scope),
        failure(FailureCode.protocol),
      );
      expect(transport.calls.length, 1);
    });
  }

  test('认证依次执行 challenge 提交门闩和一次 login', () async {
    final transport = RecordingTransport([
      challengeReply(),
      {'code': 0},
    ]);
    var gateCalls = 0;
    await client(transport).authenticate(
      context,
      credentials,
      scope,
      beforeSubmit: () async {
        gateCalls++;
        expect(transport.calls.length, 1);
        expect(transport.calls.single.$2.path, '/cgi-bin/get_challenge');
      },
    );
    expect(gateCalls, 1);
    expect(transport.calls.length, 2);
    final challenge = transport.calls[0].$2;
    final login = transport.calls[1].$2;
    expect(challenge.queryParameters.keys.toList(), [
      'callback',
      'username',
      'ip',
      '_',
    ]);
    expect(login.host, 'portal.example.test');
    expect(login.scheme, 'https');
    expect(login.path, '/cgi-bin/srun_portal');
    expect(login.queryParameters.keys.toList(), [
      'callback',
      'action',
      'username',
      'password',
      'os',
      'name',
      'double_stack',
      'chksum',
      'info',
      'ac_id',
      'ip',
      'n',
      'type',
      '_',
    ]);
    expect(
      login.queryParameters['password'],
      '{MD5}81628c8f4e98d2df1521b38a550640e6',
    );
    expect(
      login.queryParameters['chksum'],
      '6a95659402292a854dc5de275221747671d62754',
    );
    expect(login.toString(), isNot(contains(credentials.password)));
  });

  for (final badChallenge in [
    {...challengeReply(), 'challenge': ''},
    {...challengeReply(), 'challenge': 123},
    {...challengeReply(), 'challenge': '含中文'},
    {...challengeReply(), 'challenge': 'with space'},
    {...challengeReply(), 'challenge': 'x' * 1025},
    {...challengeReply(), 'client_ip': '192.0.2.11'},
    {'challenge': 'fictional-token'},
  ]) {
    test('无效 challenge 不到提交门闩或 login ${badChallenge.hashCode}', () async {
      final transport = RecordingTransport([badChallenge]);
      var gateCalls = 0;
      await expectLater(
        client(transport).authenticate(
          context,
          credentials,
          scope,
          beforeSubmit: () async {
            gateCalls++;
          },
        ),
        failure(FailureCode.protocol),
      );
      expect(gateCalls, 0);
      expect(transport.calls.length, 1);
    });
  }

  for (final (reply, code) in <(Object, FailureCode)>[
    (
      {'error': 'fictional-rejection', 'error_msg': 'private-marker'},
      FailureCode.authRejected,
    ),
    ({'code': 1, 'message': 'private-marker'}, FailureCode.authRejected),
    ({'code': true}, FailureCode.protocol),
    ({'code': 0.0}, FailureCode.protocol),
    ({'unknown': 'private-marker'}, FailureCode.protocol),
    (
      const PortalResponse(302, '', location: 'https://attacker.test/'),
      FailureCode.protocol,
    ),
    (
      const PortalResponse(503, 'private-marker'),
      FailureCode.networkUnavailable,
    ),
  ]) {
    test('login 失败安全分类且不重试 ${reply.hashCode}', () async {
      final transport = RecordingTransport([challengeReply(), reply]);
      try {
        await client(
          transport,
        ).authenticate(context, credentials, scope, beforeSubmit: () async {});
        fail('必须拒绝失败响应');
      } on AppFailure catch (error) {
        expect(error.code, code);
        expect(error.toString(), isNot(contains('private-marker')));
      }
      expect(transport.calls.length, 2);
    });
  }

  test('异源上下文在任何网络操作前拒绝', () async {
    final transport = RecordingTransport([]);
    await expectLater(
      client(transport).authenticate(
        PortalContext(Uri.parse('https://attacker.test'), context.ip, '8'),
        credentials,
        scope,
        beforeSubmit: () async {},
      ),
      failure(FailureCode.protocol),
    );
    expect(transport.calls, isEmpty);
  });

  test('提交门闩失败不发送 login', () async {
    final transport = RecordingTransport([challengeReply()]);
    await expectLater(
      client(transport).authenticate(
        context,
        credentials,
        scope,
        beforeSubmit: () async {
          throw const AppFailure(FailureCode.credentialStoreUnavailable);
        },
      ),
      failure(FailureCode.credentialStoreUnavailable),
    );
    expect(transport.calls.length, 1);
  });

  test('提交门闩取消后不发送 login', () async {
    final transport = RecordingTransport([challengeReply()]);
    await expectLater(
      client(transport).authenticate(
        context,
        credentials,
        scope,
        beforeSubmit: () async {
          scope.cancel();
        },
      ),
      failure(FailureCode.cancelled),
    );
    expect(transport.calls.length, 1);
  });

  test('challenge 返回时已取消不调用提交门闩', () async {
    final transport = RecordingTransport([challengeReply()]);
    transport.onRequest = (_, operation) => operation.cancel();
    var gateCalls = 0;
    await expectLater(
      client(transport).authenticate(
        context,
        credentials,
        scope,
        beforeSubmit: () async {
          gateCalls++;
        },
      ),
      failure(FailureCode.cancelled),
    );
    expect(gateCalls, 0);
    expect(transport.calls.length, 1);
  });

  test('提交门闩等待可由 scope 中断', () async {
    final transport = RecordingTransport([challengeReply()]);
    final waiting = Completer<void>();
    final entered = Completer<void>();
    final task = client(transport).authenticate(
      context,
      credentials,
      scope,
      beforeSubmit: () {
        entered.complete();
        return waiting.future;
      },
    );
    final expectation = expectLater(task, failure(FailureCode.cancelled));
    await entered.future;
    scope.cancel();
    await expectation;
    waiting.complete();
    await Future<void>.delayed(Duration.zero);
    expect(transport.calls.length, 1);
  });
}

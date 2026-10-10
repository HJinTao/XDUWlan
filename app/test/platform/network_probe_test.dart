import 'package:flutter_test/flutter_test.dart';
import 'package:xduwlan_app/core/domain.dart';
import 'package:xduwlan_app/platform/network_probe.dart';

class _Responses implements PortalTransport {
  _Responses(this.responses);
  final List<Object> responses;
  final requested = <Uri>[];

  @override
  Future<PortalResponse> request(
    String method,
    Uri url,
    OperationScope scope,
  ) async {
    scope.ensureActive();
    requested.add(url);
    expect(method, 'GET');
    final response = responses.removeAt(0);
    if (response is PortalResponse) return response;
    throw response;
  }
}

void main() {
  test('主 HTTPS 204 确认在线并停止回退', () async {
    final transport = _Responses([const PortalResponse(204, '')]);
    final scope = OperationScope();
    addTearDown(scope.finish);
    expect(
      await IoNetworkProbe(transport: transport).check(scope),
      NetworkState.online,
    );
    expect(transport.requested.single.scheme, 'https');
  });

  test('HTTP 204 不能覆盖主 HTTPS 的 TLS 失败', () async {
    final transport = _Responses([
      const AppFailure(FailureCode.networkUnavailable),
      const PortalResponse(204, ''),
    ]);
    final scope = OperationScope();
    addTearDown(scope.finish);
    expect(
      await IoNetworkProbe(transport: transport).check(scope),
      NetworkState.unavailable,
    );
    expect(transport.requested.map((url) => url.scheme), ['https', 'http']);
  });

  final cases = <(String, PortalResponse, NetworkState)>[
    (
      '可信重定向',
      const PortalResponse(302, '', location: 'http://w.xidian.edu.cn/index'),
      NetworkState.portalRequired,
    ),
    (
      '未知主机',
      const PortalResponse(302, '', location: 'https://untrusted.invalid/'),
      NetworkState.unknown,
    ),
    (
      '内嵌身份',
      const PortalResponse(
        302,
        '',
        location: 'https://user:secret@w.xidian.edu.cn/',
      ),
      NetworkState.unknown,
    ),
    (
      '错误协议',
      const PortalResponse(302, '', location: 'javascript://w.xidian.edu.cn/'),
      NetworkState.unknown,
    ),
    (
      '损坏目标',
      const PortalResponse(302, '', location: 'https://[invalid'),
      NetworkState.unknown,
    ),
    (
      '错误端口',
      const PortalResponse(302, '', location: 'https://w.xidian.edu.cn:444/'),
      NetworkState.unknown,
    ),
    (
      'Portal 特征',
      const PortalResponse(200, '<script src="srun_portal.js"></script>'),
      NetworkState.portalRequired,
    ),
    (
      '唯一空 POST',
      const PortalResponse(
        200,
        '<form method="post" action="http://w.xidian.edu.cn/index_8.html"></form>',
      ),
      NetworkState.portalRequired,
    ),
    (
      '可信 meta',
      const PortalResponse(
        200,
        '<meta http-equiv="refresh" content="0;url=https://w.xidian.edu.cn/srun_portal_pc">',
      ),
      NetworkState.portalRequired,
    ),
    (
      '普通网页',
      const PortalResponse(200, '<html>普通响应</html>'),
      NetworkState.unknown,
    ),
    (
      '有输入表单',
      const PortalResponse(
        200,
        '<form method="post" action="http://w.xidian.edu.cn/"><input name="x"></form>',
      ),
      NetworkState.unknown,
    ),
  ];
  for (final (name, response, expected) in cases) {
    test('探测分类：$name', () async {
      final transport = _Responses([response]);
      final scope = OperationScope();
      addTearDown(scope.finish);
      expect(
        await IoNetworkProbe(
          transport: transport,
          enableHttpFallback: false,
        ).check(scope),
        expected,
      );
    });
  }

  test('HTTP 回退的可信 Portal 可确认需要认证', () async {
    final transport = _Responses([
      const PortalResponse(200, '未知响应'),
      const PortalResponse(302, '', location: 'http://w.xidian.edu.cn/index'),
    ]);
    final scope = OperationScope();
    addTearDown(scope.finish);
    expect(
      await IoNetworkProbe(transport: transport).check(scope),
      NetworkState.portalRequired,
    );
  });

  test('主探测必须为 HTTPS，非法配置不发出请求', () async {
    final transport = _Responses([]);
    final scope = OperationScope();
    addTearDown(scope.finish);
    expect(
      await IoNetworkProbe(
        transport: transport,
        probeUrl: Uri.parse('http://probe.invalid/'),
      ).check(scope),
      NetworkState.unknown,
    );
    expect(transport.requested, isEmpty);
  });

  test('取消不能被 HTTP 回退吞掉', () async {
    final transport = _Responses([const AppFailure(FailureCode.cancelled)]);
    final scope = OperationScope();
    addTearDown(scope.finish);
    await expectLater(
      IoNetworkProbe(transport: transport).check(scope),
      throwsA(
        isA<AppFailure>().having(
          (error) => error.code,
          '安全类别',
          FailureCode.cancelled,
        ),
      ),
    );
    expect(transport.requested, hasLength(1));
  });
}

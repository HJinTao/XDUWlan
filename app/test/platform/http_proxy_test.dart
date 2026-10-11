import 'package:flutter_test/flutter_test.dart';
import 'package:xduwlan_app/core/domain.dart';
import 'package:xduwlan_app/platform/http_transport.dart';

Matcher failure(FailureCode code) =>
    throwsA(isA<AppFailure>().having((error) => error.code, '安全类别', code));

void main() {
  test('默认传输保持 DIRECT', () {
    expect(
      IoPortalTransport().proxyFor(Uri.parse('http://example.test')),
      'DIRECT',
    );
  });

  test('回环代理为 HTTP 请求生成 PROXY PAC', () {
    final proxy = HttpProxy('127.0.0.1', 8080);
    final transport = IoPortalTransport(testProxy: proxy);
    expect(
      transport.proxyFor(Uri.parse('http://example.test/fixture')),
      'PROXY 127.0.0.1:8080',
    );
  });

  test('回环代理对 HTTPS 请求也生成 PROXY PAC', () {
    final transport = IoPortalTransport(testProxy: HttpProxy('::1', 8081));
    expect(
      transport.proxyFor(Uri.parse('https://example.test/fixture')),
      'PROXY [::1]:8081',
    );
  });

  test('代理输入拒绝非回环主机和非数字端口', () {
    expect(
      () => HttpProxy('proxy.example.test', 8080),
      throwsA(isA<AppFailure>()),
    );
    expect(() => HttpProxy('127.0.0.1', 0), throwsA(isA<AppFailure>()));
    expect(() => HttpProxy('127.0.0.1', 65536), throwsA(isA<AppFailure>()));
    expect(() => HttpProxy('127.0.0.1', -1), throwsA(isA<AppFailure>()));
  });

  test('非回环目标保持 DIRECT', () {
    final transport = IoPortalTransport(
      testProxy: HttpProxy('127.0.0.1', 8080),
    );
    expect(
      transport.proxyFor(Uri.parse('ftp://example.test/fixture')),
      'DIRECT',
    );
  });

  test('代理值不出现在对象和错误文本中', () {
    final proxy = HttpProxy('127.0.0.1', 49152);
    expect(proxy.toString(), isNot(contains('49152')));
    expect(proxy.toString(), isNot(contains('127.0.0.1')));
    expect(() => HttpProxy('127.0.0.1', 0), throwsA(isA<AppFailure>()));
    expect(
      () => IoPortalTransport(testProxy: proxy, requestTimeout: Duration.zero),
      failure(FailureCode.protocol),
    );
  });

  test('Release 路径不接受代理注入', () {
    // The production constructor remains the default direct path; this test
    // also documents that callers must opt in through the test-only parameter.
    expect(
      IoPortalTransport().proxyFor(Uri.parse('http://127.0.0.1')),
      'DIRECT',
    );
  });
}

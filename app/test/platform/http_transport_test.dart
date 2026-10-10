import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xduwlan_app/core/domain.dart';
import 'package:xduwlan_app/platform/http_transport.dart';

Matcher failure(FailureCode code) =>
    throwsA(isA<AppFailure>().having((error) => error.code, '安全类别', code));

class _AmbientProxy extends HttpOverrides {
  _AmbientProxy(this.proxyPort);
  final int proxyPort;

  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context)
        ..findProxy = (_) => 'PROXY 127.0.0.1:$proxyPort';
}

void main() {
  test('直连请求读取严格 UTF-8，且不附带认证信息', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final observed = Completer<HttpRequest>();
    server.listen((request) async {
      observed.complete(request);
      request.response.write('虚构响应');
      await request.response.close();
    });
    final scope = OperationScope();
    addTearDown(scope.finish);
    final response = await IoPortalTransport().request(
      'POST',
      Uri.parse('http://127.0.0.1:${server.port}/fixture'),
      scope,
    );
    expect(response.statusCode, 200);
    expect(response.body, '虚构响应');
    final request = await observed.future;
    expect(request.method, 'POST');
    expect(request.headers.value(HttpHeaders.authorizationHeader), isNull);
    expect(request.headers.value(HttpHeaders.cookieHeader), isNull);
    expect(await request.toList(), isEmpty);
  });

  test('返回重定向但从不访问其目标', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    var followed = 0;
    server.listen((request) async {
      if (request.uri.path == '/start') {
        request.response.statusCode = 302;
        request.response.headers.set(
          HttpHeaders.locationHeader,
          '/must-not-follow',
        );
      } else {
        followed++;
      }
      await request.response.close();
    });
    final scope = OperationScope();
    addTearDown(scope.finish);
    final response = await IoPortalTransport().request(
      'GET',
      Uri.parse('http://127.0.0.1:${server.port}/start'),
      scope,
    );
    expect(response.statusCode, 302);
    expect(response.location, '/must-not-follow');
    expect(followed, 0);
  });

  for (final compressed in [false, true]) {
    test('拒绝超过正文上限的${compressed ? '解压' : '原始'}响应', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        final bytes = List<int>.filled(65537, 65);
        if (compressed) {
          request.response.headers.set(
            HttpHeaders.contentEncodingHeader,
            'gzip',
          );
          request.response.add(gzip.encode(bytes));
        } else {
          request.response.add(bytes);
        }
        await request.response.close();
      });
      final scope = OperationScope();
      addTearDown(scope.finish);
      await expectLater(
        IoPortalTransport().request(
          'GET',
          Uri.parse('http://127.0.0.1:${server.port}/oversize'),
          scope,
        ),
        failure(FailureCode.protocol),
      );
    });
  }

  test('完整读取恰好到达上限的响应', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      request.response.add(List<int>.filled(65536, 65));
      await request.response.close();
    });
    final scope = OperationScope();
    addTearDown(scope.finish);
    final response = await IoPortalTransport().request(
      'GET',
      Uri.parse('http://127.0.0.1:${server.port}/limit'),
      scope,
    );
    expect(response.body.length, 65536);
  });

  test('损坏压缩正文返回安全协议错误', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      request.response.headers.set(HttpHeaders.contentEncodingHeader, 'gzip');
      request.response.add([1, 2, 3, 4]);
      await request.response.close();
    });
    final scope = OperationScope();
    addTearDown(scope.finish);
    await expectLater(
      IoPortalTransport().request(
        'GET',
        Uri.parse('http://127.0.0.1:${server.port}/invalid-gzip'),
        scope,
      ),
      failure(FailureCode.protocol),
    );
  });

  test('损坏 UTF-8 不替换字符也不泄露响应', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      request.response.add([0xff, 0xfe]);
      await request.response.close();
    });
    final scope = OperationScope();
    addTearDown(scope.finish);
    await expectLater(
      IoPortalTransport().request(
        'GET',
        Uri.parse('http://127.0.0.1:${server.port}/malformed'),
        scope,
      ),
      failure(FailureCode.protocol),
    );
  });

  test('单请求超时关闭沉默连接，同时整轮仍可继续', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close());
    final disconnected = Completer<void>();
    final received = Completer<void>();
    server.listen((socket) {
      addTearDown(socket.destroy);
      socket.listen(
        (_) {
          if (!received.isCompleted) received.complete();
        },
        onDone: () {
          if (!disconnected.isCompleted) disconnected.complete();
        },
      );
    });
    final scope = OperationScope();
    addTearDown(scope.finish);
    await expectLater(
      IoPortalTransport(requestTimeout: const Duration(milliseconds: 100))
          .request(
            'GET',
            Uri.parse('http://127.0.0.1:${server.port}/silent'),
            scope,
          ),
      failure(FailureCode.timeout),
    );
    await received.future;
    await disconnected.future.timeout(const Duration(seconds: 2));
    expect(scope.isCancelled, isFalse);
  });

  test('取消正文读取会断开连接，且不会取消相邻操作', () async {
    final pendingServer = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => pendingServer.close());
    addTearDown(() => server.close(force: true));
    final started = Completer<void>();
    final disconnected = Completer<void>();
    // 响应的 done 只表示发送端关闭；直接读取 socket 的 FIN 才验证客户端断开。
    pendingServer.listen((socket) {
      addTearDown(socket.destroy);
      var sent = false;
      socket.listen(
        (_) async {
          if (sent) return;
          sent = true;
          socket.write(
            'HTTP/1.1 200 OK\r\nContent-Length: 1000\r\n\r\nfictional-body',
          );
          await socket.flush();
          started.complete();
        },
        onDone: () {
          if (!disconnected.isCompleted) disconnected.complete();
        },
        onError: (Object _) {
          if (!disconnected.isCompleted) disconnected.complete();
        },
      );
    });
    server.listen((request) async {
      request.response.write('相邻操作完成');
      await request.response.close();
    });
    final cancelled = OperationScope();
    final active = OperationScope();
    addTearDown(cancelled.finish);
    addTearDown(active.finish);
    final transport = IoPortalTransport();
    final pending = transport.request(
      'GET',
      Uri.parse('http://127.0.0.1:${pendingServer.port}/pending'),
      cancelled,
    );
    final expectation = expectLater(pending, failure(FailureCode.cancelled));
    await started.future.timeout(const Duration(seconds: 2));
    cancelled.cancel();
    await expectation;
    final completed = await transport.request(
      'GET',
      Uri.parse('http://127.0.0.1:${server.port}/complete'),
      active,
    );
    expect(completed.body, '相邻操作完成');
    await disconnected.future.timeout(const Duration(seconds: 2));
  });

  test('整体截止时间会释放挂起的请求', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close());
    final disconnected = Completer<void>();
    server.listen((socket) {
      addTearDown(socket.destroy);
      socket.listen(
        (_) {},
        onDone: () {
          if (!disconnected.isCompleted) disconnected.complete();
        },
      );
    });
    final scope = OperationScope(budget: const Duration(milliseconds: 100));
    addTearDown(scope.finish);
    await expectLater(
      IoPortalTransport().request(
        'GET',
        Uri.parse('http://127.0.0.1:${server.port}/deadline'),
        scope,
      ),
      failure(FailureCode.timeout),
    );
    await disconnected.future.timeout(const Duration(seconds: 2));
  });

  test('发送前已取消的操作不会触达服务', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    var requests = 0;
    server.listen((request) async {
      requests++;
      await request.response.close();
    });
    final scope = OperationScope()..cancel();
    addTearDown(scope.finish);
    await expectLater(
      IoPortalTransport().request(
        'GET',
        Uri.parse('http://127.0.0.1:${server.port}/cancelled'),
        scope,
      ),
      failure(FailureCode.cancelled),
    );
    expect(requests, 0);
  });

  test('忽略外部代理选择并直连，虚构 URL 不进入代理', () async {
    final direct = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final proxy = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => direct.close(force: true));
    addTearDown(() => proxy.close(force: true));
    var proxyRequests = 0;
    proxy.listen((request) async {
      proxyRequests++;
      request.response.write('错误代理');
      await request.response.close();
    });
    direct.listen((request) async {
      request.response.write('直连');
      await request.response.close();
    });
    await HttpOverrides.runWithHttpOverrides(() async {
      final scope = OperationScope();
      addTearDown(scope.finish);
      final response = await IoPortalTransport().request(
        'GET',
        Uri.parse('http://127.0.0.1:${direct.port}/fixture?secret=fake'),
        scope,
      );
      expect(response.body, '直连');
      expect(proxyRequests, 0);
    }, _AmbientProxy(proxy.port));
  });

  for (final trusted in [false, true]) {
    test('TLS ${trusted ? '独立信任虚构本地证书' : '默认拒绝未受信任证书'}', () async {
      // 全部材料为本地测试生成，只有 localhost/回环地址；CA 私钥不进仓库。
      // macOS SSL 策略拒绝超长有效期的叶证书，测试叶证书有效期为 365 天。
      // 到期后重新生成虚构证书；禁止用 badCertificateCallback 放宽校验。
      final serverContext = SecurityContext()
        ..useCertificateChain('test/fixtures/tls/test-only-cert.pem')
        ..usePrivateKey('test/fixtures/tls/test-only-key.pem');
      final server = await HttpServer.bindSecure(
        InternetAddress.loopbackIPv4,
        0,
        serverContext,
      );
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        request.response.write('虚构安全响应');
        await request.response.close();
      }, onError: (Object _) {});
      final clientContext = trusted
          ? (SecurityContext(withTrustedRoots: false)
              ..setTrustedCertificates('test/fixtures/tls/test-only-ca.pem'))
          : null;
      final scope = OperationScope();
      addTearDown(scope.finish);
      final response = IoPortalTransport(securityContext: clientContext)
          .request(
            'GET',
            Uri.parse('https://localhost:${server.port}/tls'),
            scope,
          );
      if (trusted) {
        expect((await response).body, '虚构安全响应');
      } else {
        await expectLater(response, failure(FailureCode.networkUnavailable));
      }
    });
  }
}

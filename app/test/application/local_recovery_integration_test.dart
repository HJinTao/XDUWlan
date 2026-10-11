import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xduwlan_app/application/recovery_service.dart';
import 'package:xduwlan_app/core/domain.dart';
import 'package:xduwlan_app/platform/http_transport.dart';
import 'package:xduwlan_app/platform/network_probe.dart';
import 'package:xduwlan_app/platform/srun_client.dart';

/// 只在测试边界把逻辑可信主机映射到 loopback，生产解析仍看到原始目标。
class _MappedTransport implements PortalTransport {
  _MappedTransport(this.actual, this.httpPort, this.httpsPort);
  final PortalTransport actual;
  final int httpPort;
  final int httpsPort;
  final List<(String, String, String)> calls = [];

  @override
  Future<PortalResponse> request(String method, Uri url, OperationScope scope) {
    if (!{'portal.invalid', 'probe.invalid'}.contains(url.host) ||
        !{'http', 'https'}.contains(url.scheme)) {
      throw const AppFailure(FailureCode.protocol);
    }
    calls.add((url.scheme, method, url.path));
    return actual.request(
      method,
      url.replace(
        host: InternetAddress.loopbackIPv4.address,
        port: url.scheme == 'https' ? httpsPort : httpPort,
      ),
      scope,
    );
  }
}

class _MemoryCredentials implements CredentialStore {
  _MemoryCredentials(this.value);
  Credentials value;
  int reads = 0;

  @override
  Future<Credentials?> load() async {
    reads++;
    return value;
  }

  @override
  Future<void> save(Credentials credentials) async => value = credentials;
}

class _WifiProbe implements NetworkProbe {
  _WifiProbe(this.inner);
  final IoNetworkProbe inner;

  @override
  Future<NetworkObservation> check(OperationScope scope) async {
    final state = await inner.check(scope);
    return NetworkObservation(
      link: NetworkLink.wifi,
      campus: state == NetworkState.portalRequired
          ? CampusNetworkState.authenticationRequired
          : state == NetworkState.online
              ? CampusNetworkState.online
              : state == NetworkState.unavailable
                  ? CampusNetworkState.unavailable
                  : CampusNetworkState.unknown,
      portal: state,
      authenticationAllowed: state == NetworkState.portalRequired,
    );
  }
}

void main() {
  final vector =
      (jsonDecode(
            File('test/fixtures/srun_vectors.json')
                .readAsStringSync(encoding: utf8),
          ) as List<dynamic>).first
          as Map<String, dynamic>;

  for (final accepted in [true, false]) {
    test(accepted ? '真实本地 HTTP/TLS 纵向恢复后再次认证跳过凭据与 Portal' : '真实本地 HTTP/TLS 明确拒绝不重试或复查为成功', () async {
      final serverContext = SecurityContext()
        ..useCertificateChain('test/fixtures/tls/test-only-cert.pem')
        ..usePrivateKey('test/fixtures/tls/test-only-key.pem');
      final http = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => http.close(force: true));
      final https = await HttpServer.bindSecure(
        InternetAddress.loopbackIPv4,
        0,
        serverContext,
      );
      addTearDown(() => https.close(force: true));

      var online = false;
      var challengeRequests = 0;
      var loginRequests = 0;
      var emptyPosts = 0;
      var encodedRequestCorrect = false;
      var noCredentialsOnEntry = true;

      Future<void> handle(HttpRequest request, {required bool secure}) async {
        final path = request.uri.path;
        final query = request.uri.queryParameters;
        final response = request.response;
        response.headers.contentType = ContentType(
          'text',
          'html',
          charset: 'utf-8',
        );
        if (!path.startsWith('/cgi-bin/')) {
          noCredentialsOnEntry =
              noCredentialsOnEntry &&
              !query.containsKey('username') &&
              !query.containsKey('password') &&
              request.headers.value(HttpHeaders.authorizationHeader) == null &&
              request.headers.value(HttpHeaders.cookieHeader) == null;
        }

        if (path == '/check' && request.method == 'GET') {
          if (secure) {
            response.statusCode = online ? 204 : 503;
          } else {
            response.write(
              '<form method="post" action="http://portal.invalid/index_8.html"></form>',
            );
          }
        } else if (secure &&
            path == '/index_8.html' &&
            request.method == 'POST') {
          final body = await request.fold<List<int>>(
            [],
            (bytes, chunk) => bytes..addAll(chunk),
          );
          if (body.isEmpty) emptyPosts++;
          response.write(
            '<meta http-equiv="refresh" content="0;url=/srun_portal_pc?ac_id=8">',
          );
        } else if (secure &&
            path == '/srun_portal_pc' &&
            request.method == 'GET') {
          response.write(
            '<script>var CONFIG={ip:"192.0.2.10",acid:"8"};</script>',
          );
        } else if (secure &&
            path == '/cgi-bin/get_challenge' &&
            request.method == 'GET') {
          challengeRequests++;
          response.write(
            '${query['callback']}(${jsonEncode({'code': 0, 'challenge': vector['challenge'], 'client_ip': vector['ip']})});',
          );
        } else if (secure &&
            path == '/cgi-bin/srun_portal' &&
            request.method == 'GET') {
          loginRequests++;
          encodedRequestCorrect =
              query['username'] == vector['username'] &&
              query['password'] == '{MD5}${vector['hmd5']}' &&
              query['info'] == vector['info'] &&
              query['chksum'] == vector['checksum'] &&
              query['ac_id'] == vector['acid'] &&
              query['ip'] == vector['ip'];
          online = accepted;
          response.write(
            '${query['callback']}(${jsonEncode({'code': accepted ? 0 : 1})});',
          );
        } else {
          response.statusCode = 404;
        }
        await response.close();
      }

      http.listen((request) => handle(request, secure: false));
      https.listen((request) => handle(request, secure: true));
      final clientContext = SecurityContext(withTrustedRoots: false)
        ..setTrustedCertificates('test/fixtures/tls/test-only-ca.pem');
      final transport = _MappedTransport(
        IoPortalTransport(securityContext: clientContext),
        http.port,
        https.port,
      );
      final portalOrigin = Uri.parse('https://portal.invalid');
      final probeUri = Uri.parse('https://probe.invalid/check');
      final entryUri = Uri.parse('http://probe.invalid/check');
      final store = _MemoryCredentials(
        Credentials(vector['username'] as String, vector['password'] as String),
      );
      final service = RecoveryService(
        probe: _WifiProbe(IoNetworkProbe(
          transport: transport,
          probeUrl: probeUri,
          portalUrl: portalOrigin,
          fallbackUrl: entryUri,
        )),
        portal: SrunPortalClient(
          transport: transport,
          portalUri: portalOrigin,
          entryUri: entryUri,
          clock: () => DateTime.fromMillisecondsSinceEpoch(1234),
        ),
        store: store,
      );
      final scope = OperationScope();
      addTearDown(scope.finish);
      final stages = <RecoveryStage>[];
      final result = await service.login(scope, onStage: stages.add);

      expect(
        result.outcome,
        accepted ? RecoveryOutcome.restored : RecoveryOutcome.failed,
      );
      expect(
        result.network,
        accepted ? NetworkState.online : NetworkState.portalRequired,
      );
      expect(result.failure, accepted ? isNull : FailureCode.authRejected);
      expect(scope.submitted, isTrue);
      expect(store.reads, 1);
      expect(challengeRequests, 1);
      expect(loginRequests, 1);
      expect(emptyPosts, 1);
      expect(encodedRequestCorrect, isTrue);
      expect(noCredentialsOnEntry, isTrue);
      expect(transport.calls, [
        ('https', 'GET', '/check'),
        ('http', 'GET', '/check'),
        ('http', 'GET', '/check'),
        ('https', 'POST', '/index_8.html'),
        ('https', 'GET', '/srun_portal_pc'),
        ('https', 'GET', '/cgi-bin/get_challenge'),
        ('https', 'GET', '/cgi-bin/srun_portal'),
        if (accepted) ('https', 'GET', '/check'),
      ]);
      expect(stages, [
        RecoveryStage.checking,
        RecoveryStage.preparing,
        RecoveryStage.authenticating,
        if (accepted) RecoveryStage.verifying,
      ]);

      if (accepted) {
        final secondScope = OperationScope();
        addTearDown(secondScope.finish);
        final second = await service.login(secondScope);
        expect(second.outcome, RecoveryOutcome.alreadyOnline);
        expect(second.network, NetworkState.online);
        expect(second.failure, isNull);
        expect(secondScope.submitted, isFalse);
        expect(store.reads, 1);
        expect(challengeRequests, 1);
        expect(loginRequests, 1);
        expect(transport.calls.length, 9);
        expect(transport.calls.last, ('https', 'GET', '/check'));
      }
    });
  }
}

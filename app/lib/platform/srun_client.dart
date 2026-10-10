import '../core/domain.dart';
import '../core/portal_pages.dart';
import '../core/srun_protocol.dart';

/// 无凭据入口发现与一次认证分离，所有后续导航及认证目标均受同源约束。
class SrunPortalClient implements PortalClient {
  SrunPortalClient({
    required this.transport,
    Uri? portalUri,
    Uri? entryUri,
    DateTime Function()? clock,
  }) : _portal = _portalOrigin(
         portalUri ?? Uri.parse('https://w.xidian.edu.cn'),
       ),
       _entry = _entryUri(
         entryUri ?? Uri.parse('http://connect.rom.miui.com/generate_204'),
       ),
       _clock = clock ?? DateTime.now;

  final PortalTransport transport;
  final Uri _portal;
  final Uri _entry;
  final DateTime Function() _clock;

  @override
  Future<PortalContext> prepare(OperationScope scope) async {
    var method = 'GET';
    var uri = _entry;
    for (var request = 0; request < 6; request++) {
      scope.ensureActive();
      final response = await scope.run(
        () => transport.request(method, uri, scope),
      );
      scope.ensureActive();
      if (response.statusCode >= 300 && response.statusCode < 400) {
        final location = response.location;
        if (location == null || location.isEmpty) {
          throw const AppFailure(FailureCode.protocol);
        }
        uri = trustedPortalUri(location, uri, _portal);
        method = 'GET';
        continue;
      }
      if (response.statusCode != 200) {
        throw const AppFailure(FailureCode.networkUnavailable);
      }
      if (uri.scheme == 'https' &&
          uri.host == _portal.host &&
          uri.port == 443 &&
          RegExp(r'\b(?:var|let|const)\s+CONFIG\s*=').hasMatch(response.body)) {
        return parsePortalContext(response.body, _portal);
      }
      final navigation = findPortalNavigation(response.body, uri, _portal);
      if (navigation == null) throw const AppFailure(FailureCode.protocol);
      method = navigation.method;
      uri = navigation.uri;
    }
    throw const AppFailure(FailureCode.protocol);
  }

  @override
  Future<void> authenticate(
    PortalContext context,
    Credentials credentials,
    OperationScope scope, {
    required Future<void> Function() beforeSubmit,
  }) async {
    scope.ensureActive();
    if (context.origin != _portal) throw const AppFailure(FailureCode.protocol);
    final timestamp = _clock().millisecondsSinceEpoch;
    final callback = 'xduwlan_cb_$timestamp';
    final response = await _requestJsonp('/cgi-bin/get_challenge', {
      'callback': callback,
      'username': credentials.username,
      'ip': context.ip,
      '_': timestamp,
    }, scope);
    _requireSuccess(response);
    final challenge = response['challenge'];
    if (challenge is! String ||
        challenge.isEmpty ||
        challenge.length > 1024 ||
        challenge.codeUnits.any((unit) => unit < 33 || unit > 127) ||
        response['client_ip'] != context.ip) {
      throw const AppFailure(FailureCode.protocol);
    }
    final params = buildLoginParams(
      credentials,
      context,
      challenge,
      callback,
      _clock().millisecondsSinceEpoch,
    );
    scope.ensureActive();
    await scope.run(beforeSubmit);
    scope.ensureActive();
    _requireSuccess(await _requestJsonp('/cgi-bin/srun_portal', params, scope));
  }

  Future<Map<String, dynamic>> _requestJsonp(
    String path,
    Map<String, Object> params,
    OperationScope scope,
  ) async {
    scope.ensureActive();
    final uri = _portal.replace(
      path: path,
      queryParameters: {
        for (final entry in params.entries) entry.key: entry.value.toString(),
      },
    );
    final response = await scope.run(
      () => transport.request('GET', uri, scope),
    );
    scope.ensureActive();
    if (response.statusCode >= 300 && response.statusCode < 400) {
      throw const AppFailure(FailureCode.protocol);
    }
    if (response.statusCode != 200) {
      throw const AppFailure(FailureCode.networkUnavailable);
    }
    return parseJsonp(response.body, params['callback'] as String);
  }
}

Uri _portalOrigin(Uri portal) =>
    trustedPortalUri('/', portal, portal).replace(path: '');

Uri _entryUri(Uri entry) {
  final text = entry.toString();
  try {
    final forbidden = RegExp(r'[\s\\\x00-\x20\x7f]');
    if (!['http', 'https'].contains(entry.scheme) ||
        entry.host.isEmpty ||
        entry.userInfo.isNotEmpty ||
        entry.authority.contains('@') ||
        entry.hasFragment ||
        forbidden.hasMatch(text) ||
        forbidden.hasMatch(Uri.decodeFull(text))) {
      throw const AppFailure(FailureCode.protocol);
    }
  } on FormatException {
    throw const AppFailure(FailureCode.protocol);
  }
  return entry;
}

void _requireSuccess(Map<String, dynamic> response) {
  final bool succeeded;
  if (response.containsKey('code')) {
    final code = response['code'];
    if (code is! int) throw const AppFailure(FailureCode.protocol);
    succeeded = code == 0;
  } else {
    final error = response['error'];
    if (error is! String || error.isEmpty) {
      throw const AppFailure(FailureCode.protocol);
    }
    succeeded = error == 'ok';
  }
  if (!succeeded) throw const AppFailure(FailureCode.authRejected);
}

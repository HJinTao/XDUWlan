import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../core/domain.dart';

/// 每次请求独立管理连接，取消不会影响其他操作。
class IoPortalTransport implements PortalTransport {
  IoPortalTransport({
    this.requestTimeout = const Duration(seconds: 5),
    this.maxBodyBytes = 65536,
    this.securityContext,
  }) {
    if (requestTimeout <= Duration.zero || maxBodyBytes < 1) {
      throw const AppFailure(FailureCode.protocol);
    }
  }

  final Duration requestTimeout;
  final int maxBodyBytes;
  final SecurityContext? securityContext;

  @override
  Future<PortalResponse> request(
    String method,
    Uri url,
    OperationScope scope,
  ) async {
    scope.ensureActive();
    if ((method != 'GET' && method != 'POST') ||
        (url.scheme != 'http' && url.scheme != 'https') ||
        url.host.isEmpty ||
        url.userInfo.isNotEmpty ||
        url.hasFragment) {
      throw const AppFailure(FailureCode.protocol);
    }

    final client = HttpClient(context: securityContext)
      ..findProxy = ((_) => 'DIRECT')
      ..autoUncompress = false;
    HttpClientRequest? outgoing;
    AppFailure? stopped;
    final requestDeadline = Completer<PortalResponse>();

    void release() {
      outgoing?.abort();
      client.close(force: true);
    }

    void ensureActive() {
      scope.ensureActive();
      if (stopped != null) throw stopped!;
    }

    final unregister = scope.onCancel(release);
    final timer = Timer(requestTimeout, () {
      stopped = const AppFailure(FailureCode.timeout);
      release();
      if (!requestDeadline.isCompleted) {
        requestDeadline.completeError(stopped!);
      }
    });

    Future<PortalResponse> perform() async {
      ensureActive();
      final request = await client.openUrl(method, url);
      outgoing = request;
      ensureActive();
      request.followRedirects = false;
      request.headers.set(HttpHeaders.acceptEncodingHeader, 'gzip');
      request.headers.set(HttpHeaders.acceptHeader, '*/*');
      // 空 POST 导航不携带 Cookie、身份信息或表单数据。
      if (method == 'POST') request.contentLength = 0;
      ensureActive();
      final response = await request.close();
      ensureActive();
      final encoding = response.headers.value(
        HttpHeaders.contentEncodingHeader,
      );
      if (encoding != null && encoding != 'identity' && encoding != 'gzip') {
        throw const AppFailure(FailureCode.protocol);
      }
      if (response.contentLength > maxBodyBytes) {
        throw const AppFailure(FailureCode.protocol);
      }

      final body = _BoundedBytesSink(maxBodyBytes, ensureActive);
      final decoded = encoding == 'gzip'
          ? gzip.decoder.startChunkedConversion(body)
          : body;
      var receivedBytes = 0;
      await for (final chunk in response) {
        ensureActive();
        receivedBytes += chunk.length;
        if (receivedBytes > maxBodyBytes) {
          throw const AppFailure(FailureCode.protocol);
        }
        decoded.add(chunk);
      }
      ensureActive();
      decoded.close();
      ensureActive();
      final text = utf8.decode(body.bytes.takeBytes(), allowMalformed: false);
      ensureActive();
      return PortalResponse(
        response.statusCode,
        text,
        location: response.headers.value(HttpHeaders.locationHeader),
      );
    }

    try {
      return await scope.run(
        () => Future.any([perform(), requestDeadline.future]),
      );
    } on AppFailure {
      rethrow;
    } on FormatException {
      throw const AppFailure(FailureCode.protocol);
    } catch (_) {
      // 底层异常可能包含认证 URL，只向调用者返回安全类别。
      scope.ensureActive();
      if (stopped != null) throw stopped!;
      throw const AppFailure(FailureCode.networkUnavailable);
    } finally {
      timer.cancel();
      unregister();
      stopped ??= const AppFailure(FailureCode.cancelled);
      release();
    }
  }
}

/// 同时限制解压后的数据，避免小压缩响应扩大为无界正文。
class _BoundedBytesSink extends ByteConversionSinkBase {
  _BoundedBytesSink(this.limit, this.ensureActive);
  final int limit;
  final void Function() ensureActive;
  final BytesBuilder bytes = BytesBuilder(copy: false);
  int _length = 0;

  @override
  void add(List<int> chunk) {
    ensureActive();
    _length += chunk.length;
    if (_length > limit) throw const AppFailure(FailureCode.protocol);
    bytes.add(chunk);
  }

  @override
  void close() => ensureActive();
}

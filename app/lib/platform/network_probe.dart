import '../core/domain.dart';
import '../core/portal_pages.dart';

/// HTTPS 验证联网，HTTP 回退仅用于发现认证入口。
class IoNetworkProbe implements NetworkProbe {
  IoNetworkProbe({
    required this.transport,
    Uri? probeUrl,
    Uri? portalUrl,
    Uri? fallbackUrl,
    this.enableHttpFallback = true,
  }) : probeUrl =
           probeUrl ?? Uri.parse('https://connect.rom.miui.com/generate_204'),
       portalUrl = portalUrl ?? Uri.parse('https://w.xidian.edu.cn'),
       fallbackUrl =
           fallbackUrl ??
           (probeUrl ?? Uri.parse('https://connect.rom.miui.com/generate_204'))
               .replace(scheme: 'http', port: 80);

  final PortalTransport transport;
  final Uri probeUrl;
  final Uri portalUrl;
  final Uri fallbackUrl;
  final bool enableHttpFallback;

  @override
  Future<NetworkState> check(OperationScope scope) async {
    scope.ensureActive();
    if (!_validEndpoint(probeUrl, 'https') ||
        !_validEndpoint(portalUrl, 'https') ||
        portalUrl.port != 443 ||
        (enableHttpFallback && !_validEndpoint(fallbackUrl, 'http'))) {
      return NetworkState.unknown;
    }
    final primary = await _checkOnce(probeUrl, scope);
    scope.ensureActive();
    if (primary == NetworkState.online ||
        primary == NetworkState.portalRequired ||
        !enableHttpFallback) {
      return primary;
    }
    final fallback = await _checkOnce(fallbackUrl, scope);
    scope.ensureActive();
    return fallback == NetworkState.portalRequired ? fallback : primary;
  }

  Future<NetworkState> _checkOnce(Uri url, OperationScope scope) async {
    try {
      scope.ensureActive();
      final response = await transport.request('GET', url, scope);
      scope.ensureActive();
      return _classify(response, url);
    } on AppFailure catch (error) {
      scope.ensureActive();
      if (error.code == FailureCode.cancelled || scope.isCancelled) rethrow;
      // 传输没有独立验证链路或局域网状态，无法进一步宣称本地网络断开。
      return error.code == FailureCode.networkUnavailable ||
              error.code == FailureCode.timeout
          ? NetworkState.unavailable
          : NetworkState.unknown;
    }
  }

  NetworkState _classify(PortalResponse response, Uri base) {
    if (response.statusCode == 204) return NetworkState.online;
    if (response.statusCode >= 300 && response.statusCode < 400) {
      final location = response.location;
      if (location == null || location.isEmpty) return NetworkState.unknown;
      try {
        trustedPortalUri(location, base, portalUrl);
        return NetworkState.portalRequired;
      } on AppFailure {
        return NetworkState.unknown;
      } on FormatException {
        return NetworkState.unknown;
      }
    }
    if (response.statusCode == 200) {
      if (response.body.toLowerCase().contains('srun_portal')) {
        return NetworkState.portalRequired;
      }
      try {
        if (findPortalNavigation(response.body, base, portalUrl) != null) {
          return NetworkState.portalRequired;
        }
      } on AppFailure {
        return NetworkState.unknown;
      } on FormatException {
        return NetworkState.unknown;
      }
    }
    return NetworkState.unknown;
  }

  bool _validEndpoint(Uri url, String scheme) =>
      url.scheme == scheme &&
      url.host.isNotEmpty &&
      url.userInfo.isEmpty &&
      !url.hasFragment;
}

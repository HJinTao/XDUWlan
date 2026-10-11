import '../core/domain.dart';
import '../core/portal_pages.dart';
import 'ios_network_path.dart';

/// HTTPS 验证联网，HTTP 回退仅用于发现认证入口。
class IoNetworkProbe implements NetworkProbe {
  IoNetworkProbe({
    required this.transport,
    Uri? probeUrl,
    Uri? portalUrl,
    Uri? fallbackUrl,
    this.enableHttpFallback = true,
    this.pathSource,
    this.allowLegacyPath = false,
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
  final NetworkPathSource? pathSource;

  /// 桌面/授权 Linux 验证入口沿用既有系统网络事实；移动端保持关闭。
  final bool allowLegacyPath;

  @override
  Future<NetworkObservation> check(OperationScope scope) async {
    scope.ensureActive();
    final path = await _pathSnapshot();
    if (!allowLegacyPath &&
        (!path.available || path.link != NetworkLink.wifi)) {
      return _observation(NetworkState.unknown, path);
    }
    if (!_validEndpoint(probeUrl, 'https') ||
        !_validEndpoint(portalUrl, 'https') ||
        portalUrl.port != 443 ||
        (enableHttpFallback && !_validEndpoint(fallbackUrl, 'http'))) {
      return _observation(NetworkState.unknown, path);
    }
    final primary = await _checkOnce(probeUrl, scope);
    scope.ensureActive();
    if (primary == NetworkState.online ||
        primary == NetworkState.portalRequired ||
        !enableHttpFallback) {
      return _observation(primary, path);
    }
    final fallback = await _checkOnce(fallbackUrl, scope);
    scope.ensureActive();
    return _observation(
      fallback == NetworkState.portalRequired ? fallback : primary,
      path,
    );
  }

  Future<NetworkPathSnapshot> _pathSnapshot() async {
    final source = pathSource;
    if (source == null) return NetworkPathSnapshot.unavailable;
    try {
      return await source.current();
    } catch (_) {
      return NetworkPathSnapshot.unavailable;
    }
  }

  NetworkObservation _observation(
    NetworkState state,
    NetworkPathSnapshot path,
  ) {
    final campus = !path.available
        ? CampusNetworkState.unknown
        : switch (state) {
            NetworkState.portalRequired =>
              CampusNetworkState.authenticationRequired,
            NetworkState.online => CampusNetworkState.unconfirmed,
            NetworkState.unavailable => CampusNetworkState.unavailable,
            NetworkState.unknown => CampusNetworkState.unknown,
          };
    return NetworkObservation(
      link:
          allowLegacyPath &&
              !path.available &&
              state == NetworkState.portalRequired
          ? NetworkLink.wifi
          : path.link,
      campus:
          allowLegacyPath &&
              !path.available &&
              state == NetworkState.portalRequired
          ? CampusNetworkState.authenticationRequired
          : campus,
      portal: state,
      authenticationAllowed:
          (allowLegacyPath &&
              !path.available &&
              state == NetworkState.portalRequired) ||
          (path.available &&
              path.link == NetworkLink.wifi &&
              state == NetworkState.portalRequired),
    );
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

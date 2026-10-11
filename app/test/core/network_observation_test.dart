import 'package:flutter_test/flutter_test.dart';
import 'package:xduwlan_app/core/domain.dart';
import 'package:xduwlan_app/core/presentation.dart';

void main() {
  test('认证门只允许 Wi-Fi 加可信 Portal 认证证据', () {
    final cases = <NetworkObservation>[
      const NetworkObservation(
        link: NetworkLink.cellular,
        campus: CampusNetworkState.authenticationRequired,
        portal: NetworkState.portalRequired,
        authenticationAllowed: false,
      ),
      const NetworkObservation(
        link: NetworkLink.wifi,
        campus: CampusNetworkState.authenticationRequired,
        portal: NetworkState.portalRequired,
        authenticationAllowed: true,
      ),
      const NetworkObservation(
        link: NetworkLink.wifi,
        campus: CampusNetworkState.unconfirmed,
        portal: NetworkState.online,
        authenticationAllowed: false,
      ),
      const NetworkObservation(
        link: NetworkLink.none,
        campus: CampusNetworkState.unavailable,
        portal: NetworkState.unavailable,
        authenticationAllowed: false,
      ),
      const NetworkObservation(
        link: NetworkLink.unknown,
        campus: CampusNetworkState.unknown,
        portal: NetworkState.unknown,
        authenticationAllowed: false,
      ),
    ];

    expect(cases.where((item) => item.authenticationAllowed), hasLength(1));
    expect(cases[1].authenticationAllowed, isTrue);
  });

  test('认证门失败文案不暴露底层网络信息', () {
    expect(
      failureMessage(FailureCode.authenticationNotAllowed),
      '当前网络不允许认证。请连接已确认的校园 Wi-Fi 后重试。',
    );
  });
}

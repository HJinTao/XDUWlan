import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:xduwlan_app/application/app_runtime_controller.dart';
import 'package:xduwlan_app/application/recovery_controller.dart';
import 'package:xduwlan_app/application/recovery_service.dart';
import 'package:xduwlan_app/core/domain.dart';
import 'package:xduwlan_app/platform/network_probe.dart';
import 'package:xduwlan_app/platform/srun_client.dart';

import 'runtime_fakes.dart';

void main() {
  test('真实探测和认证适配器在启动检查认证保存流程均不调用查询门户', () async {
    final transport = _InMemoryTransport();
    final accounts = TestAccounts();
    final recovery = RecoveryController(
      service: RecoveryService(
        probe: IoNetworkProbe(transport: transport),
        portal: SrunPortalClient(transport: transport),
        store: accounts,
      ),
      store: accounts,
    );
    final runtime = AppRuntimeController(
      recovery: recovery,
      desktop: TestDesktop(),
      settingsStore: TestSettings(),
      diagnosticStore: TestDiagnostics(),
    );
    addTearDown(() {
      runtime.dispose();
      recovery.dispose();
    });
    await recovery.saveAccount(
      const Credentials('virtual-user', 'virtual-password'),
    );
    expect(transport.requests, 0);
    await runtime.initialize();
    expect(recovery.lastReport!.outcome, RecoveryOutcome.restored);
    await runtime.check(OperationSource.manual);
    transport.online = false;
    await runtime.authenticate(OperationSource.tray);
    expect(recovery.lastReport!.outcome, RecoveryOutcome.restored);
    await recovery.saveAccount(
      const Credentials('changed-user', 'changed-password'),
    );
    await runtime.flushDiagnostics();
    expect(transport.authentications, 2);
    expect(transport.queryRequests, 0);
    expect(transport.otherRequests, 0);
  });
}

/// 逻辑主机与生产默认值一致，传输完全在内存中完成，不创建真实连接。
class _InMemoryTransport implements PortalTransport {
  bool online = false;
  int requests = 0;
  int queryRequests = 0;
  int otherRequests = 0;
  int authentications = 0;
  @override
  Future<PortalResponse> request(
    String method,
    Uri url,
    OperationScope scope,
  ) async {
    requests++;
    if (url.host == 'zfw.xidian.edu.cn') {
      queryRequests++;
      throw const AppFailure(FailureCode.protocol);
    }
    if (url.host == 'connect.rom.miui.com') {
      if (url.scheme == 'https') {
        return PortalResponse(online ? 204 : 200, online ? '' : 'srun_portal');
      }
      return const PortalResponse(
        302,
        '',
        location: 'https://w.xidian.edu.cn/srun_portal_pc',
      );
    }
    if (url.host != 'w.xidian.edu.cn') {
      otherRequests++;
      throw const AppFailure(FailureCode.protocol);
    }
    if (url.path == '/srun_portal_pc') {
      return const PortalResponse(
        200,
        '<script>var CONFIG={ip:"192.0.2.1",acid:"1"};</script>',
      );
    }
    final Map<String, dynamic> reply;
    if (url.path == '/cgi-bin/get_challenge') {
      reply = {
        'code': 0,
        'challenge': 'virtual-challenge',
        'client_ip': '192.0.2.1',
      };
    } else if (url.path == '/cgi-bin/srun_portal') {
      online = true;
      authentications++;
      reply = {'code': 0};
    } else {
      otherRequests++;
      throw const AppFailure(FailureCode.protocol);
    }
    return PortalResponse(
      200,
      '${url.queryParameters['callback']}(${jsonEncode(reply)});',
    );
  }
}

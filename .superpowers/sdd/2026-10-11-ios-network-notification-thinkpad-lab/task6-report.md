# Task 6 报告

## Status

已完成 Simulator 代理注入的离线实现与边界测试。默认、Release 和后台传输保持 `DIRECT`；未执行真实 SSH、ThinkPad 代理或校园网请求。

## 改动

- `IoPortalTransport` 增加内存中的 `testProxy` 注入和安全 PAC 解析。`HttpProxy` 只接受 `localhost`/IPv4 或 IPv6 回环地址及 1--65535 端口，`toString` 不显示地址；Release 构造拒绝代理注入。
- 产品入口只在非 Release、非后台且显式 `XDUWLAN_TEST_PROXY_*` dart-define 下注入代理；后台任务仍使用默认构造。代理不进入设置、界面、诊断或业务报告。
- 新增 `http_proxy_test.dart`，覆盖默认直连、HTTP/HTTPS PAC、输入拒绝、非 HTTP 目标直连和脱敏文本。
- 新增 `simulator_proxy_smoke.sh`，限制 RFC1918 SSH 目标和数字端口，固定执行 `ssh -N -L local:127.0.0.1:thinkpad-port`、Debug dart-define 和一次无凭据 HTTPS 探测，不接受远端命令或凭据参数。
- 更新 `docs/current.md` 与 `docs/protocol.md`，记录代理边界、脚本约束和未执行的真实验证。

## Tests

- `flutter test --no-pub test/platform/http_proxy_test.dart test/platform/http_transport_test.dart`：21 项通过。
- `flutter analyze lib/platform/http_transport.dart lib/main.dart test/platform/http_proxy_test.dart`：通过。
- `bash -n app/test/tool/simulator_proxy_smoke.sh`：通过。
- `git diff --check`：通过。

## 限制

Simulator/ThinkPad HTTP CONNECT 链路尚未在授权设备执行；脚本只提供固定的手动入口，不能证明代理命中或真实 Portal 行为。共享工作区含其他任务来源不明的改动，本任务未回滚这些改动。

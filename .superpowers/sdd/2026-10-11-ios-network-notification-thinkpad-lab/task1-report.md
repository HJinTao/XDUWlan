# Task 1 完成报告

## 状态

已完成共享链路观察值、认证安全门、操作报告字段、诊断兼容和安全文案。

## 实现

- `NetworkLink` 覆盖 cellular、wifi、wired、other、none、unknown。
- `CampusNetworkState` 覆盖 unconfirmed、authenticationRequired、online、unavailable、unknown。
- `NetworkObservation` 携带链路、校园身份、Portal 状态和 `authenticationAllowed`，并提供旧 `NetworkState` 观察结果适配。
- `OperationReport`、`DiagnosticRecord` 和控制器状态携带链路与校园状态；诊断 JSON 只写枚举名和布尔值，不写地址。
- 缺少新诊断字段的旧 JSON 解码为 `unknown` 和 `false`。
- 新增 `FailureCode.authenticationNotAllowed` 及固定中文文案。
- `RecoveryService.login` 在读取凭据、获取认证上下文和发起认证前检查观察结果；未通过时不读取凭据、不调用 Portal。
- 旧 `NetworkState` fake 的迁移测试现在显式构造 `NetworkObservation`；`fromLegacy` 保持安全默认，不会凭 Portal 状态伪造 Wi-Fi 或放行认证。
- 服务层同时校验链路、校园状态、Portal 状态和允许标志，拒绝互相矛盾的观察结果。

## TDD 证据

先添加 `network_observation_test.dart` 与认证门测试并运行，测试因类型、失败枚举和文案尚不存在而失败。完成实现后，以下 focused 命令通过：

```text
cd app && flutter test test/core/network_observation_test.dart test/application/recovery_service_test.dart test/platform/diagnostic_store_test.dart
34 tests passed
```

相关回归也通过：

```text
cd app && flutter test test/platform/network_probe_test.dart test/application/recovery_controller_test.dart test/application/app_runtime_controller_test.dart test/application/local_recovery_integration_test.dart
45 tests passed
```

`flutter analyze` 对本任务改动无错误；当前工作区仍有其他任务文件的既有警告。

## 限制

链路来源和 Wi-Fi 可信 Portal 的真实组合由后续 Task 2 接入；当前 `IoNetworkProbe` 没有原生链路来源时返回未知链路，因此不会自行放行认证。测试 fake 必须显式提供允许认证的 Wi-Fi observation。

## 审查修复

审查指出旧 `NetworkState.portalRequired` 适配会伪造 Wi-Fi 并放行认证。已将 `fromLegacy` 改为未知链路和禁止认证，并更新 recovery、controller、runtime、UI、协议观察、集成和原生 smoke 测试 fake，在需要认证的场景显式返回 Wi-Fi + `authenticationRequired` + `authenticationAllowed`。新增矛盾观察回归，确保蜂窝链路即使携带 `true` 也不读取凭据。

## 审查发现

- **高风险：旧探测器适配会在缺少链路事实时放行认证。** `NetworkObservation.fromLegacy(NetworkState.portalRequired)` 将旧结果转换为 `wifi`、`authenticationRequired` 和 `authenticationAllowed: true`（`app/lib/core/domain.dart:141-159`）。当前 `IoNetworkProbe.check` 仍返回 `NetworkState`（`app/lib/platform/network_probe.dart:27-45`），因此 `RecoveryService._observation` 会把生产环境的 Portal 探测结果转换成允许认证的 Wi-Fi 观察结果（`app/lib/application/recovery_service.dart:135-139`），随后通过认证门并读取凭据（`app/lib/application/recovery_service.dart:48-62`）。这违背“没有链路来源或未知接口不得认证”的安全要求；报告中关于当前实现不会放行认证的限制描述不成立。应在 Task 2 的链路事实接入完成前禁止该旧路径放行，或将两项变更作为同一发布门槛。

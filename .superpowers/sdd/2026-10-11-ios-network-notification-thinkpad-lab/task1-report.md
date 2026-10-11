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
- 保留旧 fake 的 `NetworkState` 返回兼容迁移路径；新平台探测仍可逐步切换为完整观察结果。

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

链路来源和 Wi-Fi 可信 Portal 的真实组合由后续 Task 2 接入；当前 `IoNetworkProbe` 没有原生链路来源时返回未知链路，因此不会自行放行认证。`NetworkProbe.check` 保留 `Future<Object>` 兼容旧 fake，服务层集中归一化为 `NetworkObservation`，后续迁移完成后可收紧静态返回类型。

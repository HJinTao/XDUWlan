# Task 2 完成报告

## 状态

已完成 iOS 原生链路事实、Dart MethodChannel 映射、Portal 探测组合和首帧后路径更新检查。

## 实现

- 新增 `app/lib/platform/ios_network_path.dart`，固定使用 `cn.xduwlan/iosNetwork`，只接受 `link` 枚举名和 `available` 布尔值。
- 原生路径值覆盖 `cellular`、`wifi`、`wired`、`other`、`none`、`unknown`；缺失插件、平台异常、关闭后的 source 或畸形 payload 都安全降级为 `unknown`/不可用。
- iOS `AppDelegate` 使用私有队列上的 `NWPathMonitor`，`currentPath` 返回当前脱敏值，路径变化通过 `pathUpdates` 回调 Dart；未传递 SSID、IP、MAC、原始 `NWPath` 或底层文本，engine 销毁时停止 monitor 并移除 handler。
- `IoNetworkProbe` 在同一轮 HTTPS/Portal 探测中读取路径事实并返回 `NetworkObservation`：Wi-Fi + 可信 Portal 重定向才设置 `authenticationAllowed`；Wi-Fi 普通 204 标记 `unconfirmed`；蜂窝、不可用、未知路径均禁止认证。
- `main.dart` 仅在 iOS 装配原生 path source；路径变化监听注册在首帧之后并触发一次前台检查，source 在 widget 释放时销毁。Android 和桌面继续使用无路径源的安全未知默认。
- 迁移直接依赖旧 `NetworkState` 的测试适配器，显式注入虚构 Wi-Fi path source，不读取或写入真实网络标识。

## TDD 证据

先添加 `test/platform/ios_network_path_test.dart` 和 `network_probe_test.dart` 的路径映射、畸形输入、缺失 channel、Wi-Fi/Portal 组合矩阵；在生产实现创建前测试因缺少 `ios_network_path.dart` 和新 API 而失败。实现后 focused 测试通过：

```text
cd app && flutter test --no-pub test/platform/ios_network_path_test.dart test/platform/network_probe_test.dart test/application/local_recovery_integration_test.dart
27 tests passed
```

相关迁移回归通过：

```text
cd app && flutter test --no-pub test/application/query_portal_boundary_test.dart test/tool/protocol_observation_test.dart
8 tests passed
```

完整 Dart 测试已运行；迁移消费者后共 279 项通过。此前两项旧消费者因 `IoNetworkProbe.check` 返回观察值而失败，已更新为显式 Wi-Fi 测试源和 `.portal` 断言。`flutter analyze` 通过，`flutter build ios --no-codesign` 成功生成 `build/ios/iphoneos/Runner.app`。

## 限制

当前任务没有实现通知授权或通知发送；这些属于 Task 3。真实 iOS 链路和校园 Portal 认证仍需授权真机验收，离线测试不代表校园网事实。无原生路径源的平台保持未知并禁止认证。

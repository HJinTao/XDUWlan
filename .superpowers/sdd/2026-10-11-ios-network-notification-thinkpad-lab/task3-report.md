# Task 3 完成报告

## 实现

- `RuntimeHost` 与 `MobileHostBridge` 增加固定的通知授权状态枚举、状态查询和显式请求接口。首次初始化只在 `notDetermined` 时请求；已拒绝状态不会重复弹出系统授权框。
- iOS `AppDelegate` 使用 `UNUserNotificationCenter` 提供 `authorized`、`notDetermined`、`denied`、`unavailable` 四类脱敏状态，并返回固定 `permission_unavailable` 错误分类。保留 Task 2 的 `NWPathMonitor` 通道、引擎生命周期清理和 Workmanager 注册。
- `AppRuntimeController` 在启动、回前台和通知发送前刷新状态；通知权限错误只影响通知。自动/后台认证通知按链路、校园身份、结果和失败枚举形成事件键，连续重复事件和未知网络/校园状态不发送；手动操作会重置连续去重边界。
- 移动通知正文包含脱敏链路和校园身份状态；首页显示授权状态，未决定时提供一次显式请求入口，移动端网络门关闭时禁用认证按钮。
- 后台恢复发送前重新检查授权状态，Workmanager 仍使用既有唯一周期任务。

## TDD 与验证

先加入移动运行时与首页失败测试，覆盖首次授权请求、拒绝后不重复请求、成功/失败与链路事件连续去重、未知/重复后台回调，以及首页授权状态展示；实现后通过：

```text
cd app && flutter test --no-pub test/application/mobile_runtime_test.dart test/ui/runtime_home_test.dart test/application/app_runtime_controller_test.dart
31 tests passed
```

随后运行 `flutter analyze`，无问题；`flutter build ios --no-codesign` 成功生成 `build/ios/iphoneos/Runner.app`。

## 限制

通知授权状态、系统弹窗和本地通知送达仍需在授权的 iOS 真机上分别验收。离线 Flutter 测试、模拟器启动和无签名构建不替代真实设备证据；本任务未读取或记录凭据、SSID、IP、MAC、原始响应或底层异常。

# Task 2 Review

Verdict: **changes requested**. The payload mapping and Portal classification are conservative for unknown paths, but the native lifecycle and update handling leave two unsafe or incorrect runtime paths.

## Findings

### P1: Blocked interfaces still make Portal requests

`IoNetworkProbe.check` reads the path at [`app/lib/platform/network_probe.dart:30-50`](app/lib/platform/network_probe.dart:30), then performs the HTTPS/HTTP probes regardless of whether the path is cellular, unavailable, or unknown. `RecoveryService.login` applies `authenticationAllowed` only after that probe at [`app/lib/application/recovery_service.dart:26-56`](app/lib/application/recovery_service.dart:26), so a manual or automatic authentication attempt on cellular still sends Portal/probe requests before it is rejected. The Task 2 security gate requirement says disallowed operations must avoid Portal requests; short-circuit the probe for a known non-Wi-Fi path (and for unavailable/unknown path) with a blocked observation, while retaining the normal probe for an allowed Wi-Fi path.

### P1: NWPathMonitor/channel teardown is attached to AppDelegate lifetime, not engine lifetime

The monitor and channel are created in `didInitializeImplicitFlutterEngine` at [`app/ios/Runner/AppDelegate.swift:26-59`](app/ios/Runner/AppDelegate.swift:26), but teardown exists only in `AppDelegate.deinit` at [`app/ios/Runner/AppDelegate.swift:104-107`](app/ios/Runner/AppDelegate.swift:104). Releasing or recreating an implicit Flutter engine leaves the monitor running and the old method handler/messenger retained until the whole AppDelegate is destroyed; a later callback can target a stale channel, and a new engine overwrites `networkChannel` while the old monitor continues publishing. Implement the Flutter engine teardown callback (or an explicit engine-owned monitor object) to cancel the monitor and clear the handler for that engine, and make repeated engine initialization replace the previous instance safely.

### P2: Path updates can trigger checks while the app is suspended

The Dart listener is installed once after the first frame at [`app/lib/main.dart:75-81`](app/lib/main.dart:75) and calls `widget.runtime.check(...)` for every update at [`app/lib/main.dart:76-79`](app/lib/main.dart:76). `AppRuntimeController.suspend()` only stops its timer at [`app/lib/application/app_runtime_controller.dart:426-431`](app/lib/application/app_runtime_controller.dart:426); `check()` directly delegates to `recovery.run` at [`app/lib/application/app_runtime_controller.dart:290-291`](app/lib/application/app_runtime_controller.dart:290), so a network transition delivered while iOS is inactive or backgrounded still starts a probe. Gate the listener on foreground lifecycle (or route it through a runtime method that honors suspension), and coalesce updates while a check is active.

### P2: Tests do not cover the required update/lifecycle behavior

`ios_network_path_test.dart` covers payload conversion and `currentPath`, but has no `pathUpdates` stream test, disposal/late-callback test, or assertion that malformed update payloads cannot trigger a runtime check. There is also no widget/runtime test for first-frame registration, suspended updates, or Android's no-path-source fallback. Add focused tests for those contracts before treating the Task 2 lifecycle wiring as complete.

## Positive checks

- Dart malformed payloads, missing channel, and native exceptions map to `unknown`/unavailable in [`app/lib/platform/ios_network_path.dart:19-26`](app/lib/platform/ios_network_path.dart:19).
- `IoNetworkProbe` only sets `authenticationAllowed` for available Wi-Fi plus trusted Portal classification at [`app/lib/platform/network_probe.dart:77-84`](app/lib/platform/network_probe.dart:77).
- Android and other non-iOS foreground construction passes no path source, so the resulting unknown/unavailable observation does not grant authentication. The separate mobile background constructor also defaults safely, although it cannot authenticate without a native path source.

## 修复记录（2026-10-11）

- `IoNetworkProbe` 先检查路径；无路径、不可用、蜂窝、wired、other、none 和 unknown 均立即返回 unknown observation，不发出 HTTPS/HTTP Portal 请求。可用 Wi-Fi 仍执行原有 HTTPS 后 HTTP 回退；测试覆盖请求计数。
- iOS NWPathMonitor 与 method channel 收拢到 `NetworkEngineController`，以 engine messenger 为弱键的 map 持有。重复初始化会替换旧控制器，控制器释放时取消 monitor；Flutter 当前 headers 没有 engine teardown callback，因此采用 messenger 生命周期绑定；Workmanager、storage 与 notification channel 保持在 AppDelegate。
- 路径流只交给 `AppRuntimeController.onNetworkPathUpdate()`。挂起、未初始化或检查进行中时只置 pending，恢复或当前检查结束后由现有调度执行；前台更新不会绕过暂停状态。
- 增加路径流合法/非法 payload、dispose 后迟到回调、无路径来源不请求、挂起更新和 Android 无路径来源回退测试。

验证：`flutter test test/platform/network_probe_test.dart test/platform/ios_network_path_test.dart test/application/mobile_runtime_test.dart` 通过（35 tests）；`flutter analyze` 通过；`xcodebuild -workspace Runner.xcworkspace -scheme Runner -sdk iphonesimulator -configuration Debug -quiet build CODE_SIGNING_ALLOWED=NO` 通过。此前 `flutter build ios --simulator --no-codesign` 因共享 `background_tasks.dart` 缺少 `runtime_host.dart` import 在 Dart 编译阶段失败，该 import 已由共享改动补齐。

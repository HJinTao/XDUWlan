import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    // 是否隐藏或退出由 Dart 运行时根据托盘可用性决定。
    return false
  }

  override func applicationShouldHandleReopen(_ sender: NSApplication,
                                             hasVisibleWindows flag: Bool) -> Bool {
    if !flag {
      mainFlutterWindow?.makeKeyAndOrderFront(nil)
      sender.activate(ignoringOtherApps: true)
    }
    return true
  }

  override func applicationWillTerminate(_ notification: Notification) {
    (mainFlutterWindow as? MainFlutterWindow)?.releaseLifecycle()
    // NSApplicationDelegate 的可选回调不保证由 FlutterAppDelegate 实现。
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}

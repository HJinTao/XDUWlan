import Cocoa
import FlutterMacOS
import Darwin

class MainFlutterWindow: NSWindow {
  private var lifecycleChannel: FlutterMethodChannel?
  private var startupChannel: FlutterMethodChannel?
  private var workspaceObservers: [NSObjectProtocol] = []
  private var startupPresentationHeld = CommandLine.arguments.contains("--background")

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = frame
    contentViewController = flutterViewController
    setFrame(windowFrame, display: true)

    let messenger = flutterViewController.engine.binaryMessenger
    let lifecycle = FlutterMethodChannel(name: "xduwlan/lifecycle", binaryMessenger: messenger)
    lifecycleChannel = lifecycle
    lifecycle.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { result(nil); return }
      switch call.method {
      case "windowReady":
        // Dart 已注册 window_manager 关闭拦截；此后展示由运行时决定。
        self.startupPresentationHeld = false
        result(nil)
      case "terminate":
        // 先完成当前平台消息，避免引擎终止后插件才发送回包。
        result(nil)
        DispatchQueue.main.async { [weak self] in
          self?.releaseLifecycle()
          NSApp.terminate(nil)
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    let center = NSWorkspace.shared.notificationCenter
    workspaceObservers = [
      center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) {
        [weak self] _ in self?.lifecycleChannel?.invokeMethod("suspend", arguments: nil)
      },
      center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) {
        [weak self] _ in self?.lifecycleChannel?.invokeMethod("resume", arguments: nil)
      },
    ]

    let startup = FlutterMethodChannel(name: "launch_at_startup", binaryMessenger: messenger)
    startupChannel = startup
    startup.setMethodCallHandler { call, result in
      do {
        let agent = try LoginAgent.currentApplication()
        switch call.method {
        case "launchAtStartupIsEnabled":
          result(try agent.isEnabled())
        case "launchAtStartupSetEnabled":
          guard let arguments = call.arguments as? [String: Any],
                let enabled = arguments["setEnabledValue"] as? Bool else {
            result(FlutterError(code: "startup_invalid_request", message: nil, details: nil))
            return
          }
          try agent.setEnabled(enabled)
          result(nil)
        default:
          result(FlutterMethodNotImplemented)
        }
      } catch {
        // 不把用户路径、系统异常或现有 plist 内容传到 Dart。
        result(FlutterError(code: "startup_unavailable", message: nil, details: nil))
      }
    }

    RegisterGeneratedPlugins(registry: flutterViewController)
    super.awakeFromNib()
    if startupPresentationHeld {
      // 未展示的窗口不会触发 viewWillAppear，因此显式启动其已有引擎。
      // 先完成非零布局，run 会发送窗口尺寸；之后展示不会创建第二个 isolate。
      flutterViewController.view.setFrameSize(contentLayoutRect.size)
      flutterViewController.view.layoutSubtreeIfNeeded()
      flutterViewController.engine.run(withEntrypoint: nil)
      orderOut(nil)
    }
  }

  override func order(_ place: NSWindow.OrderingMode, relativeTo otherWin: Int) {
    if startupPresentationHeld && place != .out { return }
    super.order(place, relativeTo: otherWin)
  }

  override func makeKeyAndOrderFront(_ sender: Any?) {
    if startupPresentationHeld { return }
    super.makeKeyAndOrderFront(sender)
  }

  func releaseLifecycle() {
    // 退出时关闭窗口仍会产生 resize 事件，须先断开插件到引擎的回调。
    delegate = nil
    for observer in workspaceObservers {
      NSWorkspace.shared.notificationCenter.removeObserver(observer)
    }
    workspaceObservers.removeAll()
    lifecycleChannel?.setMethodCallHandler(nil)
    lifecycleChannel = nil
    startupChannel?.setMethodCallHandler(nil)
    startupChannel = nil
  }

  deinit { releaseLifecycle() }
}

/// 仅维护本应用的用户 LaunchAgent；保存配置不会立即启动另一个应用进程。
/// 独立路径注入使测试只使用临时目录，生产入口固定为当前用户和当前应用。
struct LoginAgent {
  let directory: URL
  let executable: URL
  let label: String
  private var file: URL { directory.appendingPathComponent(label + ".plist") }
  private var properties: [String: Any] {
    [
      "Label": label,
      "ProgramArguments": [executable.path, "--background"],
      "RunAtLoad": true,
      "LimitLoadToSessionType": "Aqua",
      "ProcessType": "Interactive",
    ]
  }

  enum Failure: Error { case unavailable, unexpectedEntry }

  static func currentApplication() throws -> LoginAgent {
    guard let executable = Bundle.main.executableURL,
          let identifier = Bundle.main.bundleIdentifier,
          identifier == "cn.xduwlan.desktop" else { throw Failure.unavailable }
    let directory = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
    return LoginAgent(directory: directory, executable: executable,
                      label: identifier + ".login")
  }

  func isEnabled() throws -> Bool {
    var directoryInformation = stat()
    if lstat(directory.path, &directoryInformation) == 0 {
      guard directoryInformation.st_uid == getuid(),
            (directoryInformation.st_mode & S_IFMT) == S_IFDIR else {
        throw Failure.unexpectedEntry
      }
    } else if errno != ENOENT {
      throw Failure.unavailable
    }
    var information = stat()
    if lstat(file.path, &information) != 0 {
      if errno == ENOENT { return false }
      throw Failure.unavailable
    }
    guard information.st_uid == getuid(),
          (information.st_mode & S_IFMT) == S_IFREG,
          information.st_size > 0, information.st_size < 65536 else {
      throw Failure.unexpectedEntry
    }
    let data = try Data(contentsOf: file)
    let decoded: Any
    do {
      decoded = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
    } catch {
      throw Failure.unexpectedEntry
    }
    guard let existing = decoded as? [String: Any],
      NSDictionary(dictionary: existing).isEqual(to: properties) else {
      throw Failure.unexpectedEntry
    }
    return true
  }

  func setEnabled(_ enabled: Bool) throws {
    // 异常或来源不明的同名文件不覆盖、不删除。
    let existing = try isEnabled()
    if !enabled {
      if existing { try FileManager.default.removeItem(at: file) }
      return
    }
    if existing { return }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                           attributes: [.posixPermissions: 0o700])
    let data = try PropertyListSerialization.data(fromPropertyList: properties,
                                                format: .xml, options: 0)
    let temporary = directory.appendingPathComponent(".xduwlan-" + UUID().uuidString)
    let descriptor = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
    guard descriptor >= 0 else { throw Failure.unavailable }
    defer {
      close(descriptor)
      try? FileManager.default.removeItem(at: temporary)
    }
    try data.withUnsafeBytes { bytes in
      guard let base = bytes.baseAddress else { throw Failure.unavailable }
      var written = 0
      while written < bytes.count {
        let count = write(descriptor, base.advanced(by: written), bytes.count - written)
        if count < 0 && errno == EINTR { continue }
        guard count > 0 else { throw Failure.unavailable }
        written += count
      }
    }
    // 同目录硬链接以原子方式发布；若校验后出现同名文件，拒绝替换。
    guard fsync(descriptor) == 0, link(temporary.path, file.path) == 0,
          try isEnabled() else { throw Failure.unavailable }
  }
}

import Flutter
import Network
import UIKit
import UserNotifications
import workmanager_apple

private final class NetworkEngineController {
  private let networkMonitor = NWPathMonitor()
  private let networkQueue = DispatchQueue(label: "cn.xduwlan.ios-network")
  private weak var messenger: FlutterBinaryMessenger?
  private let networkChannel: FlutterMethodChannel
  private var currentNetworkPath: [String: Any] = [
    "link": "unknown",
    "available": false,
  ]
  private var disposed = false

  init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
    networkChannel = FlutterMethodChannel(
      name: "cn.xduwlan/iosNetwork",
      binaryMessenger: messenger
    )
    networkChannel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterError(code: "unavailable", message: nil, details: nil))
        return
      }
      switch call.method {
      case "currentPath":
        self.networkQueue.async {
          result(self.currentNetworkPath)
        }
      case "pathUpdates":
        result(FlutterMethodNotImplemented)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    networkMonitor.pathUpdateHandler = { [weak self] path in
      self?.receive(path)
    }
    networkMonitor.start(queue: networkQueue)
  }

  private func receive(_ path: NWPath) {
    let payload = AppDelegate.networkPayload(for: path)
    networkQueue.async { [weak self] in
      guard let self, !self.disposed else { return }
      self.currentNetworkPath = payload
      DispatchQueue.main.async { [weak self] in
        guard let self, !self.disposed else { return }
        guard let messenger = self.messenger else { return }
        FlutterMethodChannel(
          name: "cn.xduwlan/iosNetwork",
          binaryMessenger: messenger
        ).invokeMethod("pathUpdates", arguments: payload)
      }
    }
  }

  deinit {
    disposed = true
    networkMonitor.cancel()
    networkChannel.setMethodCallHandler(nil)
  }
}

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var notificationChannel: FlutterMethodChannel?
  private static let networkControllers = NSMapTable<AnyObject, NetworkEngineController>.weakToStrongObjects()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    WorkmanagerPlugin.registerPeriodicTask(
      withIdentifier: "cn.xduwlan.mobile.recovery"
    )
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let messenger = engineBridge.applicationRegistrar.messenger()
    let networkController = NetworkEngineController(messenger: messenger)
    // FlutterImplicitEngineDelegate 当前只提供初始化回调。弱键 map 让控制器
    // 随引擎 messenger 释放，并在引擎重建时替换旧实例。
    Self.networkControllers.setObject(networkController, forKey: messenger)

    let notificationChannel = FlutterMethodChannel(
      name: "cn.xduwlan/mobile",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    self.notificationChannel = notificationChannel
    notificationChannel.setMethodCallHandler { call, result in
      switch call.method {
      case "notificationStatus":
        UNUserNotificationCenter.current().getNotificationSettings { settings in
          DispatchQueue.main.async {
            result(Self.notificationStatusName(settings.authorizationStatus))
          }
        }
      case "requestNotificationPermission":
        UNUserNotificationCenter.current().requestAuthorization(
          options: [.alert, .sound, .badge]
        ) { _, error in
          if error != nil {
            result(FlutterError(code: "permission_unavailable", message: nil, details: nil))
            return
          }
          UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
              result(Self.notificationStatusName(settings.authorizationStatus))
            }
          }
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    let storageChannel = FlutterMethodChannel(
      name: "cn.xduwlan/storage",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    storageChannel.setMethodCallHandler { call, result in
      guard call.method == "excludeFromBackup",
            let path = call.arguments as? String else {
        result(FlutterMethodNotImplemented)
        return
      }
      do {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var fileURL = URL(fileURLWithPath: path)
        try fileURL.setResourceValues(values)
        result(nil as Any?)
      } catch {
        result(FlutterError(code: "backup_exclusion_failed", message: nil, details: nil))
      }
    }
  }

  fileprivate static func networkPayload(for path: NWPath) -> [String: Any] {
    let link: String
    if path.usesInterfaceType(.wifi) {
      link = "wifi"
    } else if path.usesInterfaceType(.cellular) {
      link = "cellular"
    } else if path.usesInterfaceType(.wiredEthernet) {
      link = "wired"
    } else if path.usesInterfaceType(.loopback) || path.usesInterfaceType(.other) {
      link = "other"
    } else if path.status == .unsatisfied {
      link = "none"
    } else {
      link = "unknown"
    }
    return [
      "link": link,
      "available": path.status == .satisfied,
    ]
  }

  private static func notificationStatusName(
    _ status: UNAuthorizationStatus
  ) -> String {
    switch status {
    case .authorized, .provisional, .ephemeral:
      return "authorized"
    case .denied:
      return "denied"
    case .notDetermined:
      return "notDetermined"
    @unknown default:
      return "unavailable"
    }
  }

  deinit {
    notificationChannel?.setMethodCallHandler(nil)
  }
}

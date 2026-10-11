import Flutter
import Network
import UIKit
import workmanager_apple

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let networkMonitor = NWPathMonitor()
  private let networkQueue = DispatchQueue(label: "cn.xduwlan.ios-network")
  private var networkChannel: FlutterMethodChannel?
  private var currentNetworkPath: [String: Any] = [
    "link": "unknown",
    "available": false,
  ]

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
    let channel = FlutterMethodChannel(
      name: "cn.xduwlan/iosNetwork",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    networkChannel = channel
    channel.setMethodCallHandler { [weak self] call, result in
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
      guard let self else { return }
      let payload = Self.networkPayload(for: path)
      self.networkQueue.async {
        self.currentNetworkPath = payload
        DispatchQueue.main.async {
          self.networkChannel?.invokeMethod("pathUpdates", arguments: payload)
        }
      }
    }
    networkMonitor.start(queue: networkQueue)

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

  private static func networkPayload(for path: NWPath) -> [String: Any] {
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

  deinit {
    networkMonitor.cancel()
    networkChannel?.setMethodCallHandler(nil)
  }
}

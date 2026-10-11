import Flutter
import UIKit
import workmanager_apple

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
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
}

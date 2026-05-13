import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var liveActivityHandler: AnyObject?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // Register Live Activity platform channel
    if let messenger = engineBridge.pluginRegistry.registrar(forPlugin: "LiveActivityHandler")?.messenger() {
      registerLiveActivityChannel(messenger: messenger)
    }
  }

  private func registerLiveActivityChannel(messenger: FlutterBinaryMessenger) {
    if #available(iOS 16.2, *) {
      let handler = LiveActivityHandler()
      handler.register(with: messenger)
      liveActivityHandler = handler
    } else {
      let handler = LiveActivityHandlerLegacy()
      handler.register(with: messenger)
      liveActivityHandler = handler
    }
  }
}

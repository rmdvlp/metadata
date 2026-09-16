import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate {
  private let callObserverPlugin = CallObserverPlugin()
  // In-app VoIP (CallKit + PushKit). Held for the app's lifetime: PushKit
  // registration must survive independently of any Flutter view, since a VoIP
  // push can arrive while the app is terminated.
  private let voipCallPlugin = VoipCallPlugin()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self
    }
    GeneratedPluginRegistrant.register(with: self)
    if let registrar = self.registrar(forPlugin: "CallObserverPlugin") {
      callObserverPlugin.register(with: registrar)
    }
    if let registrar = self.registrar(forPlugin: "VoipCallPlugin") {
      voipCallPlugin.register(with: registrar)
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}

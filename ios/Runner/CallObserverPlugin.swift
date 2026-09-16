import CallKit
import Flutter
import Foundation

/// Wraps CXCallObserver purely for observation. Per the plan: iOS gives no
/// API for a 3rd-party app to control (answer/end) or even read the phone
/// number of a real cellular call it's merely observing — CXCall only
/// exposes a UUID and boolean state flags. So this always reports
/// `phoneNumber: nil`, and the method channel always errors out; the
/// answer/decline capability lives entirely in `IncomingCallEvent.canAnswer`
/// /`canDecline` on the Dart side (already false on iOS), not here.
class CallObserverPlugin: NSObject {
    static let methodChannelName = "com.metadata.calls/methods"
    static let eventChannelName = "com.metadata.calls/events"

    private let callObserver = CXCallObserver()
    private var eventSink: FlutterEventSink?

    func register(with registrar: FlutterPluginRegistrar) {
        let methodChannel = FlutterMethodChannel(
            name: CallObserverPlugin.methodChannelName,
            binaryMessenger: registrar.messenger()
        )
        methodChannel.setMethodCallHandler { _, result in
            result(FlutterError(code: "UNSUPPORTED", message: "Not supported on iOS", details: nil))
        }

        let eventChannel = FlutterEventChannel(
            name: CallObserverPlugin.eventChannelName,
            binaryMessenger: registrar.messenger()
        )
        eventChannel.setStreamHandler(self)

        callObserver.setDelegate(self, queue: nil)
    }

    private func emit(state: String, isOutgoing: Bool) {
        guard let sink = eventSink else { return }
        sink([
            "state": state,
            "phoneNumber": NSNull(),
            "isOutgoing": isOutgoing,
            "timestampMs": Int(Date().timeIntervalSince1970 * 1000),
        ])
    }
}

extension CallObserverPlugin: CXCallObserverDelegate {
    func callObserver(_ callObserver: CXCallObserver, callChanged call: CXCall) {
        let state: String
        if call.hasEnded {
            state = "disconnected"
        } else if call.hasConnected {
            state = "connected"
        } else {
            state = "ringing"
        }
        emit(state: state, isOutgoing: call.isOutgoing)
    }
}

extension CallObserverPlugin: FlutterStreamHandler {
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        eventSink = events
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil
        return nil
    }
}

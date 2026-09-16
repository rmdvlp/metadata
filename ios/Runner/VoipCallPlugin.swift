import AVFoundation
import CallKit
import Flutter
import Foundation
import PushKit

#if canImport(WebRTC)
  import WebRTC
#endif

/// CallKit + PushKit integration for in-app VoIP calls.
///
/// This is the part that genuinely cannot be done in Flutter. On iOS:
///
///   * A terminated app cannot be woken by a normal FCM/APNs notification in
///     time to ring. Only a PushKit VoIP push wakes the process immediately,
///     and PushKit is not reachable from Dart.
///   * Apple *requires* that every PushKit push results in a
///     `reportNewIncomingCall` before the handler returns. Skipping it once
///     gets the app terminated; doing it repeatedly gets VoIP push privileges
///     revoked for the app entirely. Every early-return path below therefore
///     still reports a call (and then immediately ends it) rather than
///     returning silently.
///   * The lock-screen / full-screen incoming call UI is CallKit's, not
///     something an app can draw.
///
/// This is still a pure in-app VoIP call: CallKit only presents the system
/// call interface. No cellular call is placed, and no SIM is involved.
class VoipCallPlugin: NSObject {
  private var methodChannel: FlutterMethodChannel?
  private var eventSink: FlutterEventSink?

  private var provider: CXProvider?
  private let callController = CXCallController()
  private var pushRegistry: PKPushRegistry?

  private var voipToken: String?

  /// Maps our Firestore `callId` to the `UUID` CallKit insists on. CallKit
  /// only ever speaks in UUIDs, so both directions are needed.
  private var callIdToUuid: [String: UUID] = [:]
  private var uuidToCallId: [UUID: String] = [:]

  /// An answer/decline performed before Flutter attached its listener —
  /// which is the normal case when CallKit launched the app to present the
  /// call. Drained by Dart on start-up.
  private var pendingAction: [String: String]?

  // MARK: - Registration

  func register(with registrar: FlutterPluginRegistrar) {
    let methods = FlutterMethodChannel(
      name: "com.metadata.voip/methods",
      binaryMessenger: registrar.messenger()
    )
    methods.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
    methodChannel = methods

    let events = FlutterEventChannel(
      name: "com.metadata.voip/events",
      binaryMessenger: registrar.messenger()
    )
    events.setStreamHandler(self)

    configureProvider()
    configurePushRegistry()
  }

  private func configureProvider() {
    let configuration: CXProviderConfiguration
    if #available(iOS 14.0, *) {
      configuration = CXProviderConfiguration()
    } else {
      configuration = CXProviderConfiguration(localizedName: "Metadata")
    }
    configuration.supportsVideo = false
    configuration.maximumCallsPerCallGroup = 1
    configuration.maximumCallGroups = 1
    // `generic` rather than `phoneNumber`: these calls are addressed by app
    // user, not by a dialable number, and a phoneNumber handle would offer
    // the user a "call back" affordance that dials the carrier.
    configuration.supportedHandleTypes = [.generic]

    let provider = CXProvider(configuration: configuration)
    provider.setDelegate(self, queue: nil)
    self.provider = provider
  }

  private func configurePushRegistry() {
    let registry = PKPushRegistry(queue: .main)
    registry.delegate = self
    registry.desiredPushTypes = [.voIP]
    pushRegistry = registry
  }

  // MARK: - Method channel

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]

    switch call.method {
    case "reportIncomingCall":
      guard let callId = args["callId"] as? String else { return result(nil) }
      let callerName = args["callerName"] as? String ?? "Unknown caller"
      reportIncomingCall(callId: callId, callerName: callerName) { _ in result(nil) }

    case "reportOutgoingCall":
      guard let callId = args["callId"] as? String else { return result(nil) }
      let calleeName = args["calleeName"] as? String ?? "Call"
      startOutgoingCall(callId: callId, calleeName: calleeName)
      result(nil)

    case "reportCallConnected":
      if let callId = args["callId"] as? String, let uuid = callIdToUuid[callId] {
        provider?.reportOutgoingCall(with: uuid, connectedAt: Date())
      }
      result(nil)

    case "endCall":
      if let callId = args["callId"] as? String {
        endCall(callId: callId, reason: .remoteEnded)
      }
      result(nil)

    case "setMuted":
      if let callId = args["callId"] as? String,
        let muted = args["muted"] as? Bool,
        let uuid = callIdToUuid[callId]
      {
        let action = CXSetMutedCallAction(call: uuid, muted: muted)
        callController.request(CXTransaction(action: action)) { _ in }
      }
      result(nil)

    case "getVoipToken":
      result(voipToken)

    case "consumePendingCallAction":
      let action = pendingAction
      pendingAction = nil
      result(action)

    // Android-only concepts; harmless no-ops so the Dart layer can call them
    // unconditionally. CallKit's audio session already keeps an iOS call
    // alive in the background.
    case "startCallForegroundService", "stopCallForegroundService":
      result(nil)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - CallKit operations

  private func reportIncomingCall(
    callId: String,
    callerName: String,
    completion: ((Error?) -> Void)? = nil
  ) {
    let uuid = callIdToUuid[callId] ?? UUID()
    callIdToUuid[callId] = uuid
    uuidToCallId[uuid] = callId

    let update = CXCallUpdate()
    update.remoteHandle = CXHandle(type: .generic, value: callerName)
    update.localizedCallerName = callerName
    update.hasVideo = false
    update.supportsGrouping = false
    update.supportsUngrouping = false
    update.supportsHolding = false
    update.supportsDTMF = false

    configureAudioSession()

    provider?.reportNewIncomingCall(with: uuid, update: update) { [weak self] error in
      if let error = error {
        // Most commonly: the user has this app blocked in Focus/Do Not
        // Disturb, or another call is active. The call must still be torn
        // down rather than left half-reported.
        NSLog("VoipCallPlugin: reportNewIncomingCall failed: \(error)")
        self?.cleanUp(callId: callId)
      }
      completion?(error)
    }
  }

  private func startOutgoingCall(callId: String, calleeName: String) {
    let uuid = callIdToUuid[callId] ?? UUID()
    callIdToUuid[callId] = uuid
    uuidToCallId[uuid] = callId

    let handle = CXHandle(type: .generic, value: calleeName)
    let action = CXStartCallAction(call: uuid, handle: handle)
    action.isVideo = false
    action.contactIdentifier = calleeName

    configureAudioSession()
    callController.request(CXTransaction(action: action)) { error in
      if let error = error {
        NSLog("VoipCallPlugin: CXStartCallAction failed: \(error)")
      }
    }
  }

  private func endCall(callId: String, reason: CXCallEndedReason) {
    guard let uuid = callIdToUuid[callId] else { return }
    provider?.reportCall(with: uuid, endedAt: Date(), reason: reason)
    cleanUp(callId: callId)
  }

  private func cleanUp(callId: String) {
    if let uuid = callIdToUuid.removeValue(forKey: callId) {
      uuidToCallId.removeValue(forKey: uuid)
    }
  }

  /// Prepares the session for two-way voice.
  ///
  /// CallKit owns activation — it calls `didActivate` when the call actually
  /// starts — so this only sets the category/mode. Activating it here instead
  /// would fight CallKit and produce a call with no audio.
  private func configureAudioSession() {
    let session = AVAudioSession.sharedInstance()
    do {
      try session.setCategory(
        .playAndRecord,
        mode: .voiceChat,
        options: [.allowBluetooth, .allowBluetoothA2DP]
      )
    } catch {
      NSLog("VoipCallPlugin: could not configure audio session: \(error)")
    }
  }

  fileprivate func send(_ event: [String: Any?]) {
    if let sink = eventSink {
      sink(event.compactMapValues { $0 })
      return
    }
    // Flutter is not listening yet — almost always because CallKit launched
    // the app to present this very call. Park it so it is not lost.
    if let action = event["event"] as? String,
      let callId = event["callId"] as? String,
      action == "answer" || action == "decline"
    {
      pendingAction = ["callId": callId, "action": action]
    }
  }
}

// MARK: - CXProviderDelegate

extension VoipCallPlugin: CXProviderDelegate {
  func providerDidReset(_ provider: CXProvider) {
    // The system dropped every call — tell Dart so WebRTC is torn down and
    // the microphone released.
    for (_, callId) in uuidToCallId {
      send(["event": "end", "callId": callId])
    }
    callIdToUuid.removeAll()
    uuidToCallId.removeAll()
  }

  func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
    guard let callId = uuidToCallId[action.callUUID] else {
      action.fail()
      return
    }
    configureAudioSession()
    send(["event": "answer", "callId": callId])
    action.fulfill()
  }

  func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
    guard let callId = uuidToCallId[action.callUUID] else {
      action.fulfill()
      return
    }
    // Dart decides whether this is a decline or a hang-up based on the call's
    // current status; sending "end" keeps that single source of truth.
    send(["event": "end", "callId": callId])
    cleanUp(callId: callId)
    action.fulfill()
  }

  func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
    if let callId = uuidToCallId[action.callUUID] {
      send(["event": "muted", "callId": callId, "muted": action.isMuted])
    }
    action.fulfill()
  }

  func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
    guard let callId = uuidToCallId[action.callUUID] else {
      action.fail()
      return
    }
    provider.reportOutgoingCall(with: action.callUUID, startedConnectingAt: Date())
    send(["event": "outgoingStarted", "callId": callId])
    action.fulfill()
  }

  func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
    #if canImport(WebRTC)
      // Hand the already-activated session to WebRTC rather than letting it
      // activate its own. Without this the two fight over the session and the
      // call connects with no audible audio — the classic CallKit + WebRTC
      // silent-call bug.
      RTCAudioSession.sharedInstance().audioSessionDidActivate(audioSession)
      RTCAudioSession.sharedInstance().isAudioEnabled = true
    #endif
    send(["event": "audioSessionActivated"])
  }

  func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
    #if canImport(WebRTC)
      RTCAudioSession.sharedInstance().audioSessionDidDeactivate(audioSession)
      RTCAudioSession.sharedInstance().isAudioEnabled = false
    #endif
    send(["event": "audioSessionDeactivated"])
  }
}

// MARK: - PushKit

extension VoipCallPlugin: PKPushRegistryDelegate {
  func pushRegistry(
    _ registry: PKPushRegistry,
    didUpdate pushCredentials: PKPushCredentials,
    for type: PKPushType
  ) {
    guard type == .voIP else { return }
    let token = pushCredentials.token.map { String(format: "%02x", $0) }.joined()
    voipToken = token
    send(["event": "voipToken", "token": token])
  }

  func pushRegistry(
    _ registry: PKPushRegistry,
    didInvalidatePushTokenFor type: PKPushType
  ) {
    guard type == .voIP else { return }
    voipToken = nil
  }

  func pushRegistry(
    _ registry: PKPushRegistry,
    didReceiveIncomingPushWith payload: PKPushPayload,
    for type: PKPushType,
    completion: @escaping () -> Void
  ) {
    guard type == .voIP else {
      completion()
      return
    }

    let data = payload.dictionaryPayload
    let callId = data["callId"] as? String ?? UUID().uuidString
    let callerName = data["callerName"] as? String ?? "Unknown caller"
    let ended = (data["ended"] as? String) == "true" || (data["ended"] as? Bool) == true

    if ended {
      // Still has to report a call first: iOS kills apps that take a VoIP
      // push without reporting one. Report, then immediately end it, so the
      // user sees nothing but the contract is honoured.
      reportIncomingCall(callId: callId, callerName: callerName) { [weak self] _ in
        self?.endCall(callId: callId, reason: .remoteEnded)
        self?.send(["event": "incomingPush", "callId": callId, "ended": "true"])
        completion()
      }
      return
    }

    reportIncomingCall(callId: callId, callerName: callerName) { [weak self] _ in
      self?.send([
        "event": "incomingPush",
        "callId": callId,
        "callerId": data["callerId"] as? String,
        "callerName": callerName,
        "callerPhotoUrl": data["callerPhotoUrl"] as? String,
      ])
      completion()
    }
  }
}

// MARK: - Event channel

extension VoipCallPlugin: FlutterStreamHandler {
  func onListen(
    withArguments arguments: Any?,
    eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    eventSink = events
    // A token issued before Flutter attached would otherwise never reach
    // Dart, leaving this device unreachable for calls.
    if let token = voipToken {
      events(["event": "voipToken", "token": token])
    }
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }
}

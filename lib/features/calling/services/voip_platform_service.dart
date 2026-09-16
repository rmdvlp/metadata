import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metadata/core/logging/call_logger.dart';

final voipPlatformServiceProvider = Provider<VoipPlatformService>((ref) {
  final service = VoipPlatformService();
  ref.onDispose(service.dispose);
  return service;
});

/// What the user did in the *native* call UI (CallKit on iOS, the full-screen
/// call notification on Android), as opposed to inside a Flutter screen.
enum VoipNativeAction { answer, decline, end, mute, unmute }

class VoipNativeEvent {
  final VoipNativeAction? action;
  final String? callId;

  /// Set when iOS delivered a PushKit push — this is the only path that can
  /// wake a fully terminated app for an incoming call.
  final Map<String, String>? incomingPush;
  final String? voipToken;
  final bool audioSessionActive;

  const VoipNativeEvent({
    this.action,
    this.callId,
    this.incomingPush,
    this.voipToken,
    this.audioSessionActive = false,
  });
}

/// Dart side of the VoIP platform bridge.
///
/// Deliberately on its own channel (`com.metadata.voip/*`) rather than
/// sharing the existing `com.metadata.calls/*` channel used for cellular
/// call detection. The two features observe completely different things — one
/// watches the carrier's calls, this one *is* the call — and entangling them
/// would make both harder to reason about.
///
/// Platform reality this wraps, which cannot be done in Dart alone:
///   * iOS requires CallKit to present an incoming call and PushKit to be
///     woken while terminated. Apple additionally *requires* that every
///     PushKit push reports a call to CallKit, or the app is killed and loses
///     VoIP push privileges.
///   * Android requires a foreground service with the `microphone` type to
///     keep audio running when the app is backgrounded, and a full-screen
///     intent notification to present an incoming call over the lock screen.
class VoipPlatformService {
  static const MethodChannel _methods = MethodChannel('com.metadata.voip/methods');
  static const EventChannel _events = EventChannel('com.metadata.voip/events');

  StreamSubscription<dynamic>? _subscription;
  final _controller = StreamController<VoipNativeEvent>.broadcast();
  bool _initialized = false;

  Stream<VoipNativeEvent> get events => _controller.stream;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    _subscription = _events.receiveBroadcastStream().listen(
      (raw) {
        final event = _parse(raw);
        if (event != null) _controller.add(event);
      },
      onError: (Object error) =>
          CallLogger.log(CallLogEvent.nativeEvent, error: error),
    );
  }

  VoipNativeEvent? _parse(dynamic raw) {
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    final name = map['event'] as String?;
    final callId = map['callId'] as String?;
    CallLogger.log(CallLogEvent.nativeEvent, callId: callId, data: {'event': name});

    switch (name) {
      case 'answer':
        return VoipNativeEvent(action: VoipNativeAction.answer, callId: callId);
      case 'decline':
        return VoipNativeEvent(action: VoipNativeAction.decline, callId: callId);
      case 'end':
        return VoipNativeEvent(action: VoipNativeAction.end, callId: callId);
      case 'muted':
        return VoipNativeEvent(
          action: (map['muted'] as bool? ?? false)
              ? VoipNativeAction.mute
              : VoipNativeAction.unmute,
          callId: callId,
        );
      case 'voipToken':
        return VoipNativeEvent(voipToken: map['token'] as String?);
      case 'incomingPush':
        return VoipNativeEvent(
          callId: callId,
          incomingPush: map.map((k, v) => MapEntry(k, '$v')),
        );
      case 'audioSessionActivated':
        return const VoipNativeEvent(audioSessionActive: true);
      case 'audioSessionDeactivated':
        return const VoipNativeEvent(audioSessionActive: false);
      default:
        return null;
    }
  }

  Future<T?> _invoke<T>(String method, [Map<String, dynamic>? args]) async {
    try {
      return await _methods.invokeMethod<T>(method, args);
    } on MissingPluginException {
      // Platform bridge not present (e.g. a unit-test host). The Firestore
      // side of the call still works; only the native call UI is missing.
      return null;
    } on PlatformException catch (e) {
      CallLogger.log(CallLogEvent.nativeEvent, error: e, data: {'method': method});
      return null;
    }
  }

  /// Presents the system incoming-call UI. On iOS this is mandatory when
  /// woken by PushKit; on Android the native FCM service already posted the
  /// notification, so this only promotes the in-app state.
  Future<void> reportIncomingCall({
    required String callId,
    required String callerName,
    required String callerId,
  }) {
    return _invoke<void>('reportIncomingCall', {
      'callId': callId,
      'callerName': callerName,
      'callerId': callerId,
      'hasVideo': false,
    });
  }

  Future<void> reportOutgoingCall({
    required String callId,
    required String calleeName,
  }) {
    return _invoke<void>('reportOutgoingCall', {
      'callId': callId,
      'calleeName': calleeName,
    });
  }

  /// Tells CallKit the call is live so the system call timer starts and the
  /// lock-screen UI stops saying "connecting".
  Future<void> reportCallConnected(String callId) {
    return _invoke<void>('reportCallConnected', {'callId': callId});
  }

  /// Tears down the native call UI. Must be called on every termination path,
  /// including errors — a CallKit call left un-ended leaves the system call
  /// banner on screen indefinitely.
  Future<void> endCall(String callId) {
    return _invoke<void>('endCall', {'callId': callId});
  }

  Future<void> setMuted({required String callId, required bool muted}) {
    return _invoke<void>('setMuted', {'callId': callId, 'muted': muted});
  }

  /// Keeps the process alive and the microphone usable while the call is
  /// backgrounded. Android only; iOS gets the equivalent from CallKit's
  /// audio session.
  Future<void> startCallForegroundService({
    required String callId,
    required String peerName,
  }) {
    if (!Platform.isAndroid) return Future.value();
    return _invoke<void>('startCallForegroundService', {
      'callId': callId,
      'peerName': peerName,
    });
  }

  Future<void> stopCallForegroundService() {
    if (!Platform.isAndroid) return Future.value();
    return _invoke<void>('stopCallForegroundService');
  }

  /// The PushKit token, which is distinct from the FCM token and is the only
  /// thing APNs will accept for a VoIP push.
  Future<String?> getVoipToken() async {
    if (!Platform.isIOS) return null;
    return _invoke<String>('getVoipToken');
  }

  /// If the app was launched cold by the user answering in the native UI, the
  /// answer event fired before Dart existed. The native side parks it and
  /// this drains it once listeners are attached.
  Future<Map<String, String>?> consumePendingCallAction() async {
    final result = await _invoke<Map<dynamic, dynamic>>('consumePendingCallAction');
    if (result == null) return null;
    return result.map((k, v) => MapEntry('$k', '$v'));
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
    await _controller.close();
  }
}

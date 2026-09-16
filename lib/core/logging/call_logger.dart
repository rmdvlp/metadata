import 'package:flutter/foundation.dart';

/// The fixed vocabulary of call lifecycle events. Using an enum instead of
/// free-form strings keeps the logs greppable and makes it obvious when a
/// stage of the flow is never reached during debugging.
enum CallLogEvent {
  callCreated,
  callRinging,
  callAccepted,
  callRejected,
  callCancelled,
  callMissed,
  callBusy,
  webrtcInitialized,
  offerCreated,
  offerReceived,
  answerCreated,
  answerReceived,
  iceCandidateSent,
  iceCandidateReceived,
  iceConnected,
  iceDisconnected,
  callConnected,
  callEnded,
  callFailed,
  permissionDenied,
  nativeEvent,
  pushReceived,
  stateTransitionRejected,
}

/// Single funnel for every log line the calling feature emits.
///
/// Deliberately not `print()` scattered across services: a call is a
/// distributed flow across two devices, Firestore, FCM and native code, and
/// the only practical way to debug it is a consistently-tagged, ordered
/// event stream that can be filtered by `callId`.
class CallLogger {
  const CallLogger._();

  static bool verbose = kDebugMode;

  static void log(
    CallLogEvent event, {
    String? callId,
    Map<String, Object?> data = const {},
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (!verbose && error == null) return;

    final buffer = StringBuffer('[CALL] ${event.name.toUpperCase()}');
    if (callId != null) buffer.write(' call=$callId');
    for (final entry in data.entries) {
      if (entry.value == null) continue;
      buffer.write(' ${entry.key}=${entry.value}');
    }
    if (error != null) buffer.write(' error=$error');

    debugPrint(buffer.toString());
    if (stackTrace != null && kDebugMode) {
      debugPrintStack(stackTrace: stackTrace);
    }
  }
}

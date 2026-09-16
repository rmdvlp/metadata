/// Every failure the calling feature can surface, mapped to copy that is safe
/// to show a user.
///
/// Raw `FirebaseException` / WebRTC platform errors must never reach the UI —
/// they leak implementation detail and read as gibberish. Services throw
/// [CallException]; the controller puts [CallException.message] on screen.
enum CallFailure {
  microphoneDenied,
  microphonePermanentlyDenied,
  webrtcInitFailed,
  peerConnectionFailed,
  networkUnavailable,
  signalingUnavailable,
  receiverUnavailable,
  receiverBusy,
  callRejected,
  callTimeout,
  invalidCall,
  callAlreadyEnded,
  alreadyInCall,
  notAnAppUser,
  cannotCallSelf,
  unknown,
}

class CallException implements Exception {
  final CallFailure failure;
  final Object? cause;

  const CallException(this.failure, {this.cause});

  /// User-facing copy. Deliberately free of Firebase/WebRTC vocabulary.
  String get message {
    switch (failure) {
      case CallFailure.microphoneDenied:
        return 'Microphone access is needed to make a call.';
      case CallFailure.microphonePermanentlyDenied:
        return 'Microphone access is blocked. Enable it in Settings to make calls.';
      case CallFailure.webrtcInitFailed:
        return 'Could not start audio. Please try again.';
      case CallFailure.peerConnectionFailed:
        return 'The call could not connect. Check your connection and try again.';
      case CallFailure.networkUnavailable:
        return 'You appear to be offline. Reconnect and try again.';
      case CallFailure.signalingUnavailable:
        return 'Could not reach the calling service. Please try again.';
      case CallFailure.receiverUnavailable:
        return 'This person is not reachable right now.';
      case CallFailure.receiverBusy:
        return 'This person is on another call.';
      case CallFailure.callRejected:
        return 'Call declined.';
      case CallFailure.callTimeout:
        return 'No answer.';
      case CallFailure.invalidCall:
        return 'This call is no longer available.';
      case CallFailure.callAlreadyEnded:
        return 'This call has already ended.';
      case CallFailure.alreadyInCall:
        return 'You are already on a call.';
      case CallFailure.notAnAppUser:
        return 'This contact does not use the app yet, so they cannot be called in-app.';
      case CallFailure.cannotCallSelf:
        return 'You cannot call yourself.';
      case CallFailure.unknown:
        return 'Something went wrong with the call. Please try again.';
    }
  }

  @override
  String toString() => 'CallException(${failure.name}${cause != null ? ', cause: $cause' : ''})';
}

/// The single source of truth for a VoIP call's lifecycle.
///
/// Both devices and the Cloud Functions backend write to the same
/// `calls/{callId}` document, so "what state is this call in" has to be
/// decided by one shared, explicit state machine rather than by whichever
/// side happened to write last. Every mutation in [CallRemoteDataSource]
/// runs inside a Firestore transaction that consults [canTransitionTo], which
/// is what makes the flow idempotent under duplicate FCM deliveries and
/// duplicate snapshot events.
enum CallStatus {
  /// Document written by the caller; the backend has not fanned out pushes yet.
  initiating,

  /// Receiver has been notified and their device should be ringing.
  ringing,

  /// Receiver tapped accept. WebRTC negotiation has not finished.
  accepted,

  /// SDP/ICE exchange in progress.
  connecting,

  /// Peer connection reports a live media path. This is when the timer starts.
  connected,

  /// Receiver explicitly declined (also used for "busy", via `endReason`).
  rejected,

  /// Caller hung up before the receiver answered.
  cancelled,

  /// Nobody answered within the ring timeout.
  missed,

  /// Either party hung up after the call was answered.
  ended,

  /// Something broke — permissions, WebRTC, or no reachable device.
  failed;

  static CallStatus fromValue(String? value) {
    return CallStatus.values.firstWhere(
      (s) => s.name == value,
      orElse: () => CallStatus.failed,
    );
  }

  /// Once a call reaches one of these it can never move again. Guarding on
  /// this is what prevents the `ENDED -> CONNECTED` class of bug.
  bool get isTerminal => const {
    CallStatus.rejected,
    CallStatus.cancelled,
    CallStatus.missed,
    CallStatus.ended,
    CallStatus.failed,
  }.contains(this);

  /// True while the receiver's phone should be ringing and the caller should
  /// see "Calling…".
  bool get isPending => this == CallStatus.initiating || this == CallStatus.ringing;

  /// True once the call has been answered but audio may not be flowing yet.
  bool get isActive => const {
    CallStatus.accepted,
    CallStatus.connecting,
    CallStatus.connected,
  }.contains(this);

  static const Map<CallStatus, Set<CallStatus>> _allowed = {
    CallStatus.initiating: {
      CallStatus.ringing,
      CallStatus.cancelled,
      CallStatus.rejected,
      CallStatus.failed,
    },
    CallStatus.ringing: {
      CallStatus.accepted,
      CallStatus.rejected,
      CallStatus.cancelled,
      CallStatus.missed,
      CallStatus.failed,
    },
    CallStatus.accepted: {
      CallStatus.connecting,
      CallStatus.connected,
      CallStatus.ended,
      CallStatus.failed,
    },
    CallStatus.connecting: {
      CallStatus.connected,
      CallStatus.ended,
      CallStatus.failed,
    },
    CallStatus.connected: {CallStatus.ended, CallStatus.failed},
    CallStatus.rejected: {},
    CallStatus.cancelled: {},
    CallStatus.missed: {},
    CallStatus.ended: {},
    CallStatus.failed: {},
  };

  bool canTransitionTo(CallStatus next) {
    if (this == next) return false;
    return _allowed[this]?.contains(next) ?? false;
  }
}

/// Why a call ended, when the status alone is ambiguous. Stored alongside
/// `status` rather than encoded into it so the state machine above stays
/// small and the history UI can still explain itself.
class CallEndReason {
  const CallEndReason._();

  static const String busy = 'busy';
  static const String timeout = 'timeout';
  static const String connectTimeout = 'connect_timeout';
  static const String receiverUnavailable = 'receiver_unavailable';
  static const String networkLost = 'network_lost';
  static const String peerConnectionFailed = 'peer_connection_failed';
  static const String microphoneDenied = 'microphone_denied';
  static const String hangUp = 'hang_up';
}

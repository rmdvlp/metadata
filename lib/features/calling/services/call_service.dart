import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:metadata/core/firebase/firebase_providers.dart';
import 'package:metadata/core/logging/call_logger.dart';
import 'package:metadata/features/calling/data/call_remote_datasource.dart';
import 'package:metadata/features/calling/data/signaling_datasource.dart';
import 'package:metadata/features/calling/models/call_config.dart';
import 'package:metadata/features/calling/models/call_exception.dart';
import 'package:metadata/features/calling/models/call_model.dart';
import 'package:metadata/features/calling/models/call_status.dart';
import 'package:metadata/features/calling/models/voip_user.dart';
import 'package:metadata/features/calling/services/call_permission_service.dart';
import 'package:metadata/features/calling/services/voip_platform_service.dart';
import 'package:metadata/features/calling/services/webrtc_service.dart';

final callServiceProvider = Provider<CallService>((ref) {
  final service = CallService(
    auth: ref.watch(firebaseAuthProvider),
    calls: ref.watch(callRemoteDataSourceProvider),
    signaling: ref.watch(signalingDataSourceProvider),
    webrtc: ref.watch(webRTCServiceProvider),
    permissions: ref.watch(callPermissionServiceProvider),
    platform: ref.watch(voipPlatformServiceProvider),
  );
  ref.onDispose(service.dispose);
  return service;
});

/// Everything the UI needs to render a call, in one immutable snapshot.
class CallSessionSnapshot {
  final CallModel? call;
  final MediaConnectionState? media;
  final bool isMuted;
  final bool isSpeakerOn;
  final Duration elapsed;
  final CallException? error;

  const CallSessionSnapshot({
    this.call,
    this.media,
    this.isMuted = false,
    this.isSpeakerOn = false,
    this.elapsed = Duration.zero,
    this.error,
  });

  bool get isIdle => call == null;

  /// True only once WebRTC reports a live media path — the call timer and the
  /// "Voice Connected" label both key off this, never off the Firestore
  /// status alone, because `accepted` means "the user tapped answer", not
  /// "audio is flowing".
  bool get isConnected =>
      media == MediaConnectionState.connected && call?.status == CallStatus.connected;

  CallSessionSnapshot copyWith({
    CallModel? call,
    MediaConnectionState? media,
    bool? isMuted,
    bool? isSpeakerOn,
    Duration? elapsed,
    CallException? error,
    bool clearError = false,
  }) {
    return CallSessionSnapshot(
      call: call ?? this.call,
      media: media ?? this.media,
      isMuted: isMuted ?? this.isMuted,
      isSpeakerOn: isSpeakerOn ?? this.isSpeakerOn,
      elapsed: elapsed ?? this.elapsed,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// The single entry point the UI talks to for calling.
///
/// Nothing above this layer touches Firestore or WebRTC directly. In exchange
/// this class guarantees the invariants that make calling behave: at most one
/// session at a time, every termination path releases the microphone and the
/// native call UI, and no call is ever left ringing forever.
class CallService {
  CallService({
    required FirebaseAuth auth,
    required CallRemoteDataSource calls,
    required SignalingDataSource signaling,
    required WebRTCService webrtc,
    required CallPermissionService permissions,
    required VoipPlatformService platform,
  }) : _auth = auth,
       _calls = calls,
       _signaling = signaling,
       _webrtc = webrtc,
       _permissions = permissions,
       _platform = platform;

  final FirebaseAuth _auth;
  final CallRemoteDataSource _calls;
  final SignalingDataSource _signaling;
  final WebRTCService _webrtc;
  final CallPermissionService _permissions;
  final VoipPlatformService _platform;

  final _sessionController = StreamController<CallSessionSnapshot>.broadcast();
  Stream<CallSessionSnapshot> get session => _sessionController.stream;

  CallSessionSnapshot _snapshot = const CallSessionSnapshot();
  CallSessionSnapshot get current => _snapshot;

  // Subscriptions and timers scoped to the active call. Every one of these is
  // cancelled in _teardown; leaking a Firestore listener across calls would
  // apply one call's signaling to the next.
  StreamSubscription<CallModel?>? _callSub;
  StreamSubscription<RTCSessionDescription?>? _descriptionSub;
  StreamSubscription<RTCIceCandidate>? _remoteCandidateSub;
  StreamSubscription<RTCIceCandidate>? _localCandidateSub;
  StreamSubscription<MediaConnectionState>? _mediaSub;
  Timer? _ringTimeoutTimer;
  Timer? _connectTimeoutTimer;
  Timer? _elapsedTimer;

  String? _activeCallId;
  bool _isCaller = false;
  bool _tearingDown = false;
  DateTime? _connectedSince;

  String? get currentUserId => _auth.currentUser?.uid;

  /// The call this device is currently on, if any. Used to answer "am I
  /// busy?" without a round trip.
  String? get activeCallId => _activeCallId;

  bool get isBusy => _activeCallId != null;

  /// Supplies short-lived, server-issued TURN credentials.
  ///
  /// Kept as a runtime hook rather than a constant so production credentials
  /// are never compiled into the binary, where they can be extracted and the
  /// relay abused.
  void configureTurnServers(List<Map<String, dynamic>> servers) {
    CallConfig.turnServers = servers;
  }

  // ---------------------------------------------------------------------
  // Outgoing
  // ---------------------------------------------------------------------

  /// Places a call and returns its id.
  ///
  /// Ordering matters here: permissions and the busy check happen *before*
  /// the Firestore document is created, so a call that cannot possibly work
  /// never rings the other person's phone.
  Future<String> startCall({required VoipUser receiver, String? callerNameOverride}) async {
    final uid = currentUserId;
    if (uid == null) throw const CallException(CallFailure.invalidCall);
    if (receiver.uid == uid) throw const CallException(CallFailure.cannotCallSelf);
    if (isBusy) throw const CallException(CallFailure.alreadyInCall);

    await _permissions.ensureCallPermissions();

    final callId = _calls.newCallId();
    final call = CallModel(
      callId: callId,
      callerId: uid,
      receiverId: receiver.uid,
      callerName: callerNameOverride ?? _auth.currentUser?.displayName ?? 'Unknown',
      receiverName: receiver.displayName,
      callerPhotoUrl: _auth.currentUser?.photoURL,
      receiverPhotoUrl: receiver.photoUrl,
      participants: [uid, receiver.uid],
      status: CallStatus.initiating,
    );

    _activeCallId = callId;
    _isCaller = true;
    _emit(const CallSessionSnapshot().copyWith(call: call));

    try {
      await _calls.createCall(call);
      await _platform.reportOutgoingCall(callId: callId, calleeName: receiver.displayName);
      await _startWebRtcAsCaller(callId);
      _watchCallDocument(callId);
      _startRingTimeout(callId);
      return callId;
    } catch (e) {
      await _failCall(callId, e);
      rethrow;
    }
  }

  Future<void> _startWebRtcAsCaller(String callId) async {
    await _webrtc.initialize();
    _bindMedia(callId);

    // Publish local candidates as they trickle in rather than waiting for
    // gathering to finish — this is most of the difference between a call
    // that connects in ~1s and one that takes 5s.
    _localCandidateSub = _webrtc.localCandidates.listen((candidate) {
      _signaling.addCandidate(callId, SignalingDataSource.callerCandidates, candidate);
    });

    final offer = await _webrtc.createOffer();
    await _signaling.setOffer(callId, offer);

    _descriptionSub = _signaling.watchAnswer(callId).listen((answer) async {
      if (answer == null) return;
      await _webrtc.setRemoteDescription(answer);
    });

    _remoteCandidateSub = _signaling
        .watchCandidates(callId, SignalingDataSource.receiverCandidates)
        .listen(_webrtc.addRemoteCandidate);
  }

  // ---------------------------------------------------------------------
  // Incoming
  // ---------------------------------------------------------------------

  /// Answers a ringing call.
  ///
  /// The `accepted` transition runs first and its result is respected: if it
  /// returns false the caller already cancelled (or the ring timed out) in
  /// the interval between the screen appearing and the tap, and we must not
  /// open the microphone for a call that no longer exists.
  Future<void> acceptCall(String callId) async {
    final uid = currentUserId;
    if (uid == null) throw const CallException(CallFailure.invalidCall);

    if (isBusy && _activeCallId != callId) {
      await rejectCall(callId, reason: CallEndReason.busy);
      throw const CallException(CallFailure.alreadyInCall);
    }

    await _permissions.ensureCallPermissions();

    final accepted = await _calls.transition(
      callId: callId,
      to: CallStatus.accepted,
      precondition: (call) => call.receiverId == uid,
    );
    if (!accepted) {
      await _platform.endCall(callId);
      throw const CallException(CallFailure.callAlreadyEnded);
    }

    CallLogger.log(CallLogEvent.callAccepted, callId: callId);

    _activeCallId = callId;
    _isCaller = false;
    final call = await _calls.getCall(callId);
    _emit(_snapshot.copyWith(call: call));

    try {
      await _startWebRtcAsReceiver(callId);
      _watchCallDocument(callId);
      _startConnectTimeout(callId);
      await _platform.startCallForegroundService(
        callId: callId,
        peerName: call?.callerName ?? 'Call',
      );
    } catch (e) {
      await _failCall(callId, e);
      rethrow;
    }
  }

  Future<void> _startWebRtcAsReceiver(String callId) async {
    await _webrtc.initialize();
    _bindMedia(callId);

    _localCandidateSub = _webrtc.localCandidates.listen((candidate) {
      _signaling.addCandidate(callId, SignalingDataSource.receiverCandidates, candidate);
    });

    final offer = await _signaling.getOffer(callId);
    if (offer == null) {
      // The caller vanished between creating the document and publishing an
      // offer — there is nothing to answer.
      throw const CallException(CallFailure.peerConnectionFailed);
    }
    await _webrtc.setRemoteDescription(offer);

    final answer = await _webrtc.createAnswer();
    await _signaling.setAnswer(callId, answer);

    _remoteCandidateSub = _signaling
        .watchCandidates(callId, SignalingDataSource.callerCandidates)
        .listen(_webrtc.addRemoteCandidate);

    await _calls.transition(callId: callId, to: CallStatus.connecting);
  }

  /// Declines a ringing call. Also used to auto-decline with
  /// [CallEndReason.busy] when a second call arrives mid-call.
  Future<void> rejectCall(String callId, {String? reason}) async {
    final uid = currentUserId;
    await _calls.transition(
      callId: callId,
      to: CallStatus.rejected,
      endReason: reason ?? CallEndReason.hangUp,
      endedBy: uid,
    );
    CallLogger.log(CallLogEvent.callRejected, callId: callId, data: {'reason': reason});
    await _platform.endCall(callId);
    if (_activeCallId == callId) await _teardown();
  }

  // ---------------------------------------------------------------------
  // Termination
  // ---------------------------------------------------------------------

  /// Caller hanging up before the call was answered.
  Future<void> cancelCall(String callId) async {
    await _calls.transition(
      callId: callId,
      to: CallStatus.cancelled,
      endReason: CallEndReason.hangUp,
      endedBy: currentUserId,
    );
    CallLogger.log(CallLogEvent.callCancelled, callId: callId);
    await _teardown();
  }

  /// Hanging up an answered call. Safe to call from either side and from any
  /// state — if the call is already terminal the transition is a no-op and
  /// only the local teardown runs.
  Future<void> endCall(String callId) async {
    final duration = _elapsedSeconds();
    await _calls.transition(
      callId: callId,
      to: CallStatus.ended,
      endReason: CallEndReason.hangUp,
      endedBy: currentUserId,
      duration: duration,
    );
    CallLogger.log(CallLogEvent.callEnded, callId: callId, data: {'duration': duration});
    await _teardown();
  }

  /// Resolves whatever the current call is, whatever state it is in. Used by
  /// the UI's single "End" button so it does not have to know whether it is
  /// cancelling, rejecting or ending.
  Future<void> hangUpCurrent() async {
    final call = _snapshot.call;
    final callId = _activeCallId;
    if (call == null || callId == null) {
      await _teardown();
      return;
    }
    if (call.status.isPending) {
      if (_isCaller) {
        await cancelCall(callId);
      } else {
        await rejectCall(callId);
      }
      return;
    }
    await endCall(callId);
  }

  // ---------------------------------------------------------------------
  // Wiring
  // ---------------------------------------------------------------------

  /// Reacts to the authoritative call document.
  ///
  /// This is what makes "the other user's UI closes when the call ends" work:
  /// whichever side writes the terminal status, both devices see it here and
  /// tear down independently.
  void _watchCallDocument(String callId) {
    _callSub?.cancel();
    _callSub = _calls.watchCall(callId).listen((call) async {
      if (call == null) {
        await _teardown();
        return;
      }
      _emit(_snapshot.copyWith(call: call));

      if (call.status == CallStatus.accepted && _isCaller) {
        _ringTimeoutTimer?.cancel();
        _startConnectTimeout(callId);
        await _platform.startCallForegroundService(
          callId: callId,
          peerName: call.receiverName,
        );
      }

      if (call.status.isTerminal) {
        CallLogger.log(
          CallLogEvent.callEnded,
          callId: callId,
          data: {'status': call.status.name, 'reason': call.endReason},
        );
        await _teardown();
      }
    });
  }

  void _bindMedia(String callId) {
    _mediaSub?.cancel();
    _mediaSub = _webrtc.connectionState.listen((state) async {
      _emit(_snapshot.copyWith(media: state));
      switch (state) {
        case MediaConnectionState.connected:
          _connectTimeoutTimer?.cancel();
          await _onMediaConnected(callId);
          break;
        case MediaConnectionState.disconnected:
          // The grace period inside WebRTCService has already elapsed by the
          // time this fires, so the path is genuinely gone.
          await _calls.transition(
            callId: callId,
            to: CallStatus.ended,
            endReason: CallEndReason.networkLost,
            endedBy: currentUserId,
            duration: _elapsedSeconds(),
          );
          break;
        case MediaConnectionState.failed:
          await _calls.transition(
            callId: callId,
            to: CallStatus.failed,
            endReason: CallEndReason.peerConnectionFailed,
            endedBy: currentUserId,
          );
          break;
        case MediaConnectionState.connecting:
          break;
      }
    });
  }

  Future<void> _onMediaConnected(String callId) async {
    if (_connectedSince != null) return;
    _connectedSince = DateTime.now();
    CallLogger.log(CallLogEvent.callConnected, callId: callId);

    await _calls.transition(callId: callId, to: CallStatus.connected);
    await _platform.reportCallConnected(callId);

    // The timer is driven from the moment media actually connected, not from
    // when the user tapped call — a caller waiting 20s for an answer must not
    // see a 20s call duration.
    _elapsedTimer?.cancel();
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _emit(_snapshot.copyWith(elapsed: Duration(seconds: _elapsedSeconds())));
    });
  }

  int _elapsedSeconds() {
    final since = _connectedSince;
    if (since == null) return 0;
    return DateTime.now().difference(since).inSeconds;
  }

  void _startRingTimeout(String callId) {
    _ringTimeoutTimer?.cancel();
    _ringTimeoutTimer = Timer(CallConfig.ringTimeout, () async {
      CallLogger.log(CallLogEvent.callMissed, callId: callId);
      await _calls.transition(
        callId: callId,
        to: CallStatus.missed,
        endReason: CallEndReason.timeout,
      );
      await _teardown();
    });
  }

  void _startConnectTimeout(String callId) {
    _connectTimeoutTimer?.cancel();
    _connectTimeoutTimer = Timer(CallConfig.connectTimeout, () async {
      if (_connectedSince != null) return;
      await _calls.transition(
        callId: callId,
        to: CallStatus.failed,
        endReason: CallEndReason.connectTimeout,
      );
      await _teardown();
    });
  }

  Future<void> _failCall(String callId, Object error) async {
    CallLogger.log(CallLogEvent.callFailed, callId: callId, error: error);
    final failure = error is CallException ? error : const CallException(CallFailure.unknown);
    _emit(_snapshot.copyWith(error: failure));
    await _calls.transition(
      callId: callId,
      to: CallStatus.failed,
      endReason: failure.failure == CallFailure.microphoneDenied
          ? CallEndReason.microphoneDenied
          : CallEndReason.peerConnectionFailed,
      endedBy: currentUserId,
    );
    await _teardown(preserveError: true);
  }

  // ---------------------------------------------------------------------
  // Controls
  // ---------------------------------------------------------------------

  Future<void> toggleMute() async {
    final next = !_webrtc.isMuted;
    await _webrtc.setMuted(next);
    final callId = _activeCallId;
    if (callId != null) {
      await _platform.setMuted(callId: callId, muted: next);
    }
    _emit(_snapshot.copyWith(isMuted: next));
  }

  Future<void> setMuted(bool muted) async {
    await _webrtc.setMuted(muted);
    _emit(_snapshot.copyWith(isMuted: muted));
  }

  Future<void> toggleSpeaker() async {
    final next = !_webrtc.isSpeakerOn;
    await _webrtc.setSpeakerOn(next);
    _emit(_snapshot.copyWith(isSpeakerOn: next));
  }

  // ---------------------------------------------------------------------
  // Queries
  // ---------------------------------------------------------------------

  Stream<List<CallModel>> incomingCalls() {
    final uid = currentUserId;
    if (uid == null) return Stream.value(const []);
    return _calls.watchIncomingCalls(uid);
  }

  Stream<CallModel?> watchCall(String callId) => _calls.watchCall(callId);

  Future<CallModel?> getCall(String callId) => _calls.getCall(callId);

  /// Server-side busy check, for the case where this device believes it is
  /// idle but another of the user's devices is on a call.
  Future<bool> isBusyOnAnyDevice() async {
    final uid = currentUserId;
    if (uid == null) return false;
    final active = await _calls.getActiveCalls(uid);
    return active.isNotEmpty;
  }

  // ---------------------------------------------------------------------
  // Teardown
  // ---------------------------------------------------------------------

  /// Releases every resource the call held.
  ///
  /// Guarded by `_tearingDown` because it is reachable from several
  /// concurrent paths at once — the Firestore terminal status, the media
  /// state listener and the user's own tap can all land within the same
  /// frame, and running teardown three times would double-dispose the peer
  /// connection.
  Future<void> _teardown({bool preserveError = false}) async {
    if (_tearingDown) return;
    _tearingDown = true;

    final callId = _activeCallId;
    final wasCaller = _isCaller;

    _ringTimeoutTimer?.cancel();
    _connectTimeoutTimer?.cancel();
    _elapsedTimer?.cancel();
    _ringTimeoutTimer = null;
    _connectTimeoutTimer = null;
    _elapsedTimer = null;

    await _callSub?.cancel();
    await _descriptionSub?.cancel();
    await _remoteCandidateSub?.cancel();
    await _localCandidateSub?.cancel();
    await _mediaSub?.cancel();
    _callSub = null;
    _descriptionSub = null;
    _remoteCandidateSub = null;
    _localCandidateSub = null;
    _mediaSub = null;

    await _webrtc.hangUp();

    if (callId != null) {
      await _platform.endCall(callId);
      await _platform.stopCallForegroundService();
      // Fire-and-forget: the call is already over from the user's point of
      // view and they should not wait on a cleanup batch.
      unawaited(_signaling.clearSignaling(callId, isCaller: wasCaller));
    }

    _activeCallId = null;
    _isCaller = false;
    _connectedSince = null;

    _emit(CallSessionSnapshot(error: preserveError ? _snapshot.error : null));
    _tearingDown = false;
  }

  void _emit(CallSessionSnapshot snapshot) {
    _snapshot = snapshot;
    if (!_sessionController.isClosed) _sessionController.add(snapshot);
  }

  Future<void> dispose() async {
    await _teardown();
    await _sessionController.close();
  }
}

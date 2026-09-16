import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:metadata/core/logging/call_logger.dart';
import 'package:metadata/features/calling/models/call_config.dart';
import 'package:metadata/features/calling/models/call_exception.dart';

final webRTCServiceProvider = Provider<WebRTCService>((ref) {
  final service = WebRTCService();
  ref.onDispose(service.dispose);
  return service;
});

/// High-level view of the media path, collapsed from WebRTC's much larger
/// state enums into the three things the rest of the app actually cares
/// about.
enum MediaConnectionState {
  /// Negotiating — no audio is flowing yet.
  connecting,

  /// A media path is live. This, and only this, starts the call timer.
  connected,

  /// The path dropped and did not recover within the grace period.
  disconnected,

  /// Negotiation failed outright.
  failed,
}

/// Owns everything WebRTC. Nothing above this layer imports `flutter_webrtc`
/// except for the SDP/ICE types that cross the signaling boundary.
///
/// The contract is deliberately narrow — create a peer connection, produce or
/// consume an SDP, feed it candidates, tell it to mute — because peer
/// connection lifetime is the single easiest thing to leak in a calling app.
/// A `RTCPeerConnection` that is not closed keeps the microphone hot and the
/// audio session active, which on iOS shows a permanent red status bar and on
/// Android holds a wakelock.
class WebRTCService {
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;

  final _connectionStateController = StreamController<MediaConnectionState>.broadcast();
  final _localCandidateController = StreamController<RTCIceCandidate>.broadcast();

  /// Candidates that arrived before `setRemoteDescription` had been called.
  ///
  /// This buffer is not optional. Firestore can deliver the other side's
  /// candidates before its offer/answer snapshot lands, and calling
  /// `addCandidate` before a remote description exists throws and silently
  /// drops that candidate — which shows up later as a call that rings, is
  /// answered, and then never produces audio.
  final List<RTCIceCandidate> _pendingRemoteCandidates = [];
  bool _remoteDescriptionSet = false;

  Timer? _disconnectGraceTimer;
  bool _disposed = false;

  /// Emits whenever the media path's health changes.
  Stream<MediaConnectionState> get connectionState => _connectionStateController.stream;

  /// Locally-gathered ICE candidates, to be published to the signaling
  /// channel as they trickle in.
  Stream<RTCIceCandidate> get localCandidates => _localCandidateController.stream;

  bool get isInitialized => _peerConnection != null;

  bool _muted = false;
  bool get isMuted => _muted;

  bool _speakerOn = false;
  bool get isSpeakerOn => _speakerOn;

  /// Builds the peer connection and opens the microphone.
  ///
  /// Microphone permission must already have been granted — this throws
  /// [CallFailure.microphoneDenied] rather than prompting, so the permission
  /// conversation happens in the UI layer where it can be explained.
  Future<void> initialize() async {
    if (_peerConnection != null) return;
    _disposed = false;

    try {
      _peerConnection = await createPeerConnection(CallConfig.iceConfiguration);
    } catch (e, s) {
      CallLogger.log(CallLogEvent.callFailed, error: e, stackTrace: s);
      throw CallException(CallFailure.webrtcInitFailed, cause: e);
    }

    try {
      _localStream = await navigator.mediaDevices.getUserMedia(
        CallConfig.audioOnlyConstraints,
      );
    } catch (e, s) {
      CallLogger.log(CallLogEvent.permissionDenied, error: e, stackTrace: s);
      await _closePeerConnection();
      throw CallException(CallFailure.microphoneDenied, cause: e);
    }

    for (final track in _localStream!.getAudioTracks()) {
      await _peerConnection!.addTrack(track, _localStream!);
    }

    _peerConnection!
      ..onIceCandidate = (candidate) {
        if (_disposed) return;
        _localCandidateController.add(candidate);
      }
      ..onTrack = (event) {
        if (event.streams.isEmpty) return;
        _remoteStream = event.streams.first;
        CallLogger.log(CallLogEvent.nativeEvent, data: {'remoteTrack': event.track.kind});
      }
      ..onIceConnectionState = _handleIceState
      ..onConnectionState = _handlePeerState;

    CallLogger.log(CallLogEvent.webrtcInitialized);
  }

  void _handleIceState(RTCIceConnectionState state) {
    if (_disposed) return;
    switch (state) {
      case RTCIceConnectionState.RTCIceConnectionStateConnected:
      case RTCIceConnectionState.RTCIceConnectionStateCompleted:
        _disconnectGraceTimer?.cancel();
        _disconnectGraceTimer = null;
        CallLogger.log(CallLogEvent.iceConnected);
        _emit(MediaConnectionState.connected);
        break;
      case RTCIceConnectionState.RTCIceConnectionStateDisconnected:
        // Do not tear down yet. A Wi-Fi to cellular handover routinely blips
        // through `disconnected` and recovers on its own within a few
        // seconds; hanging up here would drop perfectly good calls.
        CallLogger.log(CallLogEvent.iceDisconnected);
        _disconnectGraceTimer?.cancel();
        _disconnectGraceTimer = Timer(CallConfig.iceDisconnectGrace, () {
          _emit(MediaConnectionState.disconnected);
        });
        break;
      case RTCIceConnectionState.RTCIceConnectionStateFailed:
        _emit(MediaConnectionState.failed);
        break;
      case RTCIceConnectionState.RTCIceConnectionStateClosed:
        _emit(MediaConnectionState.disconnected);
        break;
      default:
        break;
    }
  }

  void _handlePeerState(RTCPeerConnectionState state) {
    if (_disposed) return;
    if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
      _emit(MediaConnectionState.failed);
    }
  }

  void _emit(MediaConnectionState state) {
    if (_disposed || _connectionStateController.isClosed) return;
    _connectionStateController.add(state);
  }

  Future<RTCSessionDescription> createOffer() async {
    final pc = _requirePeerConnection();
    final offer = await pc.createOffer({'offerToReceiveAudio': true, 'offerToReceiveVideo': false});
    await pc.setLocalDescription(offer);
    return offer;
  }

  Future<RTCSessionDescription> createAnswer() async {
    final pc = _requirePeerConnection();
    final answer = await pc.createAnswer({'offerToReceiveAudio': true, 'offerToReceiveVideo': false});
    await pc.setLocalDescription(answer);
    return answer;
  }

  /// Applies the other side's SDP, then flushes any candidates that arrived
  /// early. Repeat calls are ignored: Firestore re-delivers the same snapshot
  /// on reconnect, and re-applying a remote description mid-call resets
  /// negotiation.
  Future<void> setRemoteDescription(RTCSessionDescription description) async {
    if (_remoteDescriptionSet) return;
    final pc = _requirePeerConnection();
    await pc.setRemoteDescription(description);
    _remoteDescriptionSet = true;
    CallLogger.log(
      description.type == 'offer' ? CallLogEvent.offerReceived : CallLogEvent.answerReceived,
    );

    for (final candidate in _pendingRemoteCandidates) {
      await pc.addCandidate(candidate);
    }
    _pendingRemoteCandidates.clear();
  }

  Future<void> addRemoteCandidate(RTCIceCandidate candidate) async {
    final pc = _peerConnection;
    if (pc == null) return;
    if (!_remoteDescriptionSet) {
      _pendingRemoteCandidates.add(candidate);
      return;
    }
    try {
      await pc.addCandidate(candidate);
      CallLogger.log(CallLogEvent.iceCandidateReceived);
    } catch (e) {
      // One bad candidate does not sink a call — ICE only needs a single
      // working pair, so this is logged rather than propagated.
      CallLogger.log(CallLogEvent.iceCandidateReceived, error: e);
    }
  }

  /// Mutes by disabling the outgoing audio *track*, not the device volume.
  ///
  /// Disabling the track stops audio at the source, so nothing is
  /// transmitted; muting the device instead would still send audio and would
  /// also silence everything else on the phone.
  Future<void> setMuted(bool muted) async {
    final stream = _localStream;
    if (stream == null) return;
    for (final track in stream.getAudioTracks()) {
      track.enabled = !muted;
    }
    _muted = muted;
  }

  /// Routes audio to the loudspeaker or back to the earpiece.
  Future<void> setSpeakerOn(bool speakerOn) async {
    try {
      await Helper.setSpeakerphoneOn(speakerOn);
      _speakerOn = speakerOn;
    } catch (e) {
      CallLogger.log(CallLogEvent.nativeEvent, error: e);
    }
  }

  RTCPeerConnection _requirePeerConnection() {
    final pc = _peerConnection;
    if (pc == null) throw const CallException(CallFailure.webrtcInitFailed);
    return pc;
  }

  /// Releases the microphone, the remote stream and the peer connection.
  ///
  /// Safe to call more than once and from any state — teardown runs on
  /// several paths (local hang-up, remote hang-up, error, screen disposal)
  /// and must never throw or double-free.
  Future<void> hangUp() async {
    _disconnectGraceTimer?.cancel();
    _disconnectGraceTimer = null;
    _remoteDescriptionSet = false;
    _pendingRemoteCandidates.clear();
    _muted = false;

    try {
      final stream = _localStream;
      if (stream != null) {
        for (final track in stream.getTracks()) {
          await track.stop();
        }
        await stream.dispose();
      }
    } catch (e) {
      CallLogger.log(CallLogEvent.callFailed, error: e);
    }
    _localStream = null;

    try {
      await _remoteStream?.dispose();
    } catch (_) {
      // The remote stream is owned by the peer connection on some platforms
      // and may already be gone; nothing to recover here.
    }
    _remoteStream = null;

    await _closePeerConnection();

    if (_speakerOn) {
      await setSpeakerOn(false);
    }
  }

  Future<void> _closePeerConnection() async {
    try {
      await _peerConnection?.close();
      await _peerConnection?.dispose();
    } catch (e) {
      CallLogger.log(CallLogEvent.callFailed, error: e);
    }
    _peerConnection = null;
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await hangUp();
    await _connectionStateController.close();
    await _localCandidateController.close();
  }
}

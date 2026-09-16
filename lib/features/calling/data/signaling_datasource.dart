import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:metadata/core/firebase/firebase_providers.dart';
import 'package:metadata/core/logging/call_logger.dart';
import 'package:metadata/features/calling/models/call_exception.dart';

final signalingDataSourceProvider = Provider<SignalingDataSource>((ref) {
  return SignalingDataSource(firestore: ref.watch(firebaseFirestoreProvider));
});

/// Carries WebRTC negotiation data — and nothing else — between the two
/// devices.
///
/// Firestore is the signaling channel only. Session descriptions and ICE
/// candidates are small text blobs describing *how* to open a peer-to-peer
/// media path; the audio itself never touches Firestore and travels directly
/// between the devices (or via TURN) once that path is open.
///
/// Layout, mirroring the WebRTC roles exactly:
///   calls/{callId}/signaling/offer      written by the caller
///   calls/{callId}/signaling/answer     written by the receiver
///   calls/{callId}/callerCandidates/*   written by the caller
///   calls/{callId}/receiverCandidates/* written by the receiver
///
/// The security rules enforce that split, so a participant cannot forge the
/// other side's half of the negotiation.
class SignalingDataSource {
  SignalingDataSource({required FirebaseFirestore firestore}) : _firestore = firestore;

  final FirebaseFirestore _firestore;

  static const String _offerDoc = 'offer';
  static const String _answerDoc = 'answer';
  static const String callerCandidates = 'callerCandidates';
  static const String receiverCandidates = 'receiverCandidates';

  DocumentReference<Map<String, dynamic>> _call(String callId) =>
      _firestore.collection('calls').doc(callId);

  CollectionReference<Map<String, dynamic>> _signaling(String callId) =>
      _call(callId).collection('signaling');

  CollectionReference<Map<String, dynamic>> candidates(String callId, String which) =>
      _call(callId).collection(which);

  Future<void> setOffer(String callId, RTCSessionDescription offer) async {
    await _writeDescription(callId, _offerDoc, offer, CallLogEvent.offerCreated);
  }

  Future<void> setAnswer(String callId, RTCSessionDescription answer) async {
    await _writeDescription(callId, _answerDoc, answer, CallLogEvent.answerCreated);
  }

  Future<void> _writeDescription(
    String callId,
    String docId,
    RTCSessionDescription description,
    CallLogEvent event,
  ) async {
    try {
      await _signaling(callId).doc(docId).set({
        'sdp': description.sdp,
        'type': description.type,
        'createdAt': FieldValue.serverTimestamp(),
      });
      CallLogger.log(event, callId: callId);
    } on FirebaseException catch (e) {
      CallLogger.log(CallLogEvent.callFailed, callId: callId, error: e);
      throw CallException(CallFailure.signalingUnavailable, cause: e);
    }
  }

  /// Emits once the other side has published its description, then keeps
  /// emitting on any later write. Consumers must guard against applying the
  /// same description twice (see `WebRTCService.setRemoteDescription`).
  Stream<RTCSessionDescription?> watchOffer(String callId) =>
      _watchDescription(callId, _offerDoc);

  Stream<RTCSessionDescription?> watchAnswer(String callId) =>
      _watchDescription(callId, _answerDoc);

  Stream<RTCSessionDescription?> _watchDescription(String callId, String docId) {
    return _signaling(callId).doc(docId).snapshots().map((doc) {
      final data = doc.data();
      if (data == null) return null;
      final sdp = data['sdp'] as String?;
      final type = data['type'] as String?;
      if (sdp == null || type == null) return null;
      return RTCSessionDescription(sdp, type);
    });
  }

  Future<RTCSessionDescription?> getOffer(String callId) async {
    final doc = await _signaling(callId).doc(_offerDoc).get();
    final data = doc.data();
    if (data == null) return null;
    final sdp = data['sdp'] as String?;
    final type = data['type'] as String?;
    if (sdp == null || type == null) return null;
    return RTCSessionDescription(sdp, type);
  }

  /// Publishes a locally-gathered candidate. Called repeatedly as ICE
  /// gathering trickles results in, rather than once at the end — waiting for
  /// gathering to complete adds seconds to time-to-audio.
  Future<void> addCandidate(
    String callId,
    String which,
    RTCIceCandidate candidate,
  ) async {
    if (candidate.candidate == null) return;
    try {
      await candidates(callId, which).add({
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
        'createdAt': FieldValue.serverTimestamp(),
      });
      CallLogger.log(CallLogEvent.iceCandidateSent, callId: callId, data: {'which': which});
    } on FirebaseException catch (e) {
      // A single dropped candidate is not fatal — ICE only needs one working
      // pair, so this is logged and swallowed rather than failing the call.
      CallLogger.log(CallLogEvent.callFailed, callId: callId, error: e);
    }
  }

  /// Only emits candidates as they are *added*, so re-delivered snapshots of
  /// previously-seen documents do not re-add candidates to the peer
  /// connection.
  Stream<RTCIceCandidate> watchCandidates(String callId, String which) {
    return candidates(callId, which).snapshots().expand((snapshot) {
      return snapshot.docChanges
          .where((change) => change.type == DocumentChangeType.added)
          .map((change) {
            final data = change.doc.data() ?? const <String, dynamic>{};
            return RTCIceCandidate(
              data['candidate'] as String?,
              data['sdpMid'] as String?,
              (data['sdpMLineIndex'] as num?)?.toInt(),
            );
          });
    });
  }

  /// Removes the negotiation payloads this device is responsible for.
  ///
  /// Scoped to the caller's or the receiver's own half deliberately: the
  /// security rules only let each side write its own SDP document and its own
  /// candidate collection, so a batch that tried to delete both halves would
  /// be rejected in its entirety and clean up nothing. Both devices run
  /// teardown, so between them everything is removed.
  ///
  /// Best-effort by design: if a device dies mid-call its documents are
  /// orphaned under a terminal call, which is harmless. A TTL policy on
  /// `createdAt` (see the deployment notes) is the durable cleanup.
  Future<void> clearSignaling(String callId, {required bool isCaller}) async {
    try {
      final which = isCaller ? callerCandidates : receiverCandidates;
      final descriptionDoc = isCaller ? _offerDoc : _answerDoc;

      final batch = _firestore.batch();
      final snap = await candidates(callId, which).get();
      for (final doc in snap.docs) {
        batch.delete(doc.reference);
      }
      batch.delete(_signaling(callId).doc(descriptionDoc));
      await batch.commit();
    } on FirebaseException catch (e) {
      CallLogger.log(CallLogEvent.callFailed, callId: callId, error: e);
    }
  }
}

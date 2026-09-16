import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metadata/core/firebase/firebase_providers.dart';
import 'package:metadata/core/logging/call_logger.dart';
import 'package:metadata/features/calling/models/call_exception.dart';
import 'package:metadata/features/calling/models/call_model.dart';
import 'package:metadata/features/calling/models/call_status.dart';

final callRemoteDataSourceProvider = Provider<CallRemoteDataSource>((ref) {
  return CallRemoteDataSource(firestore: ref.watch(firebaseFirestoreProvider));
});

/// Owns every read and write of the `calls/{callId}` document.
///
/// The one rule this class exists to enforce: a call's status only ever
/// changes inside a Firestore transaction that first re-reads the current
/// status and asks [CallStatus.canTransitionTo]. Two devices racing (caller
/// cancels at the same instant the receiver accepts) both run this
/// transaction; Firestore serialises them, the first wins, and the second
/// sees a status it cannot legally move from and gives up quietly. That is
/// also what makes duplicate FCM deliveries and repeated snapshot events
/// harmless — re-applying a transition that already happened is a no-op.
class CallRemoteDataSource {
  CallRemoteDataSource({required FirebaseFirestore firestore}) : _firestore = firestore;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _calls => _firestore.collection('calls');

  DocumentReference<Map<String, dynamic>> callRef(String callId) => _calls.doc(callId);

  /// Reserves a document id up front so the caller can start WebRTC setup and
  /// signaling against a known path before the document round-trips.
  String newCallId() => _calls.doc().id;

  Future<void> createCall(CallModel call) async {
    try {
      await callRef(call.callId).set(call.toCreateMap());
      CallLogger.log(
        CallLogEvent.callCreated,
        callId: call.callId,
        data: {'receiver': call.receiverId},
      );
    } on FirebaseException catch (e) {
      CallLogger.log(CallLogEvent.callFailed, callId: call.callId, error: e);
      throw CallException(CallFailure.signalingUnavailable, cause: e);
    }
  }

  Stream<CallModel?> watchCall(String callId) {
    return callRef(callId).snapshots().map(
      (doc) => doc.exists ? CallModel.fromFirestore(doc) : null,
    );
  }

  Future<CallModel?> getCall(String callId) async {
    final doc = await callRef(callId).get();
    return doc.exists ? CallModel.fromFirestore(doc) : null;
  }

  /// Every incoming call for [uid] that is still live.
  ///
  /// Scoped to non-terminal statuses so a device coming back online does not
  /// resurrect an incoming-call screen for a call that was resolved while it
  /// was away.
  Stream<List<CallModel>> watchIncomingCalls(String uid) {
    return _calls
        .where('receiverId', isEqualTo: uid)
        .where('status', whereIn: [
          CallStatus.initiating.name,
          CallStatus.ringing.name,
        ])
        .snapshots()
        .map((snap) => snap.docs.map(CallModel.fromFirestore).toList());
  }

  /// Any call this user is currently a party to that has been answered.
  /// Used to answer "am I already on a call?" before accepting a new one.
  Future<List<CallModel>> getActiveCalls(String uid) async {
    final snap = await _calls
        .where('participants', arrayContains: uid)
        .where('status', whereIn: [
          CallStatus.accepted.name,
          CallStatus.connecting.name,
          CallStatus.connected.name,
        ])
        .get();
    return snap.docs.map(CallModel.fromFirestore).toList();
  }

  /// Applies a state transition if — and only if — the state machine allows
  /// it from whatever the document currently says.
  ///
  /// Returns `true` when this call actually performed the transition, `false`
  /// when it was already applied or is illegal. Callers use the return value
  /// to decide whether to run one-time side effects (tearing down WebRTC,
  /// navigating away) exactly once.
  Future<bool> transition({
    required String callId,
    required CallStatus to,
    String? endReason,
    String? endedBy,
    int? duration,
    bool Function(CallModel current)? precondition,
  }) async {
    try {
      return await _firestore.runTransaction<bool>((txn) async {
        final snapshot = await txn.get(callRef(callId));
        if (!snapshot.exists) return false;

        final current = CallModel.fromFirestore(snapshot);
        if (precondition != null && !precondition(current)) return false;

        if (!current.status.canTransitionTo(to)) {
          CallLogger.log(
            CallLogEvent.stateTransitionRejected,
            callId: callId,
            data: {'from': current.status.name, 'to': to.name},
          );
          return false;
        }

        txn.update(callRef(callId), {
          'status': to.name,
          'endReason': ?endReason,
          'endedBy': ?endedBy,
          'duration': ?duration,
          ..._timestampsFor(to),
        });
        return true;
      });
    } on FirebaseException catch (e) {
      CallLogger.log(CallLogEvent.callFailed, callId: callId, error: e);
      throw CallException(CallFailure.signalingUnavailable, cause: e);
    }
  }

  /// Server timestamps for the milestone a status represents. Written by
  /// whichever device performs the transition, but always with
  /// [FieldValue.serverTimestamp] so the two devices' clocks never matter.
  Map<String, Object> _timestampsFor(CallStatus status) {
    switch (status) {
      case CallStatus.ringing:
        return {'ringingAt': FieldValue.serverTimestamp()};
      case CallStatus.accepted:
        return {'acceptedAt': FieldValue.serverTimestamp()};
      case CallStatus.connected:
        return {'connectedAt': FieldValue.serverTimestamp()};
      case CallStatus.rejected:
      case CallStatus.cancelled:
      case CallStatus.missed:
      case CallStatus.ended:
      case CallStatus.failed:
        return {'endedAt': FieldValue.serverTimestamp()};
      case CallStatus.initiating:
      case CallStatus.connecting:
        return const {};
    }
  }
}

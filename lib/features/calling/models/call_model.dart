import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:metadata/features/calling/models/call_status.dart';

enum CallType {
  audio;

  static CallType fromValue(String? value) {
    return CallType.values.firstWhere(
      (t) => t.name == value,
      orElse: () => CallType.audio,
    );
  }
}

/// A single `calls/{callId}` document.
///
/// Timestamps are all written with [FieldValue.serverTimestamp] so duration
/// and history ordering never depend on either device's clock — two phones
/// disagreeing by a few seconds would otherwise produce negative durations.
class CallModel {
  final String callId;
  final String callerId;
  final String receiverId;
  final String callerName;
  final String receiverName;
  final String? callerPhotoUrl;
  final String? receiverPhotoUrl;
  final List<String> participants;
  final CallType type;
  final CallStatus status;
  final String? endReason;
  final DateTime? createdAt;
  final DateTime? ringingAt;
  final DateTime? acceptedAt;
  final DateTime? connectedAt;
  final DateTime? endedAt;
  final String? endedBy;
  final int duration;

  const CallModel({
    required this.callId,
    required this.callerId,
    required this.receiverId,
    required this.callerName,
    required this.receiverName,
    this.callerPhotoUrl,
    this.receiverPhotoUrl,
    required this.participants,
    this.type = CallType.audio,
    required this.status,
    this.endReason,
    this.createdAt,
    this.ringingAt,
    this.acceptedAt,
    this.connectedAt,
    this.endedAt,
    this.endedBy,
    this.duration = 0,
  });

  factory CallModel.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    return CallModel(
      callId: doc.id,
      callerId: data['callerId'] as String? ?? '',
      receiverId: data['receiverId'] as String? ?? '',
      callerName: data['callerName'] as String? ?? 'Unknown',
      receiverName: data['receiverName'] as String? ?? 'Unknown',
      callerPhotoUrl: data['callerPhotoUrl'] as String?,
      receiverPhotoUrl: data['receiverPhotoUrl'] as String?,
      participants: (data['participants'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(growable: false),
      type: CallType.fromValue(data['type'] as String?),
      status: CallStatus.fromValue(data['status'] as String?),
      endReason: data['endReason'] as String?,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      ringingAt: (data['ringingAt'] as Timestamp?)?.toDate(),
      acceptedAt: (data['acceptedAt'] as Timestamp?)?.toDate(),
      connectedAt: (data['connectedAt'] as Timestamp?)?.toDate(),
      endedAt: (data['endedAt'] as Timestamp?)?.toDate(),
      endedBy: data['endedBy'] as String?,
      duration: (data['duration'] as num?)?.toInt() ?? 0,
    );
  }

  /// The initial write. `status` must be `initiating` and `participants` must
  /// be exactly `[callerId, receiverId]` — the Firestore security rules
  /// enforce both, so this shape is not merely a convention.
  Map<String, dynamic> toCreateMap() => {
    'callId': callId,
    'callerId': callerId,
    'receiverId': receiverId,
    'callerName': callerName,
    'receiverName': receiverName,
    'callerPhotoUrl': callerPhotoUrl,
    'receiverPhotoUrl': receiverPhotoUrl,
    'participants': [callerId, receiverId],
    'type': type.name,
    'status': CallStatus.initiating.name,
    'endReason': null,
    'createdAt': FieldValue.serverTimestamp(),
    'ringingAt': null,
    'acceptedAt': null,
    'connectedAt': null,
    'endedAt': null,
    'endedBy': null,
    'duration': 0,
  };

  /// Whether [uid] is the side that placed the call — decides which SDP role
  /// (offerer vs answerer) and which ICE candidate collection this device uses.
  bool isCaller(String uid) => callerId == uid;

  /// Name/photo of the party on the other end of the line, from [uid]'s view.
  String otherPartyName(String uid) => isCaller(uid) ? receiverName : callerName;

  String? otherPartyPhotoUrl(String uid) =>
      isCaller(uid) ? receiverPhotoUrl : callerPhotoUrl;

  String otherPartyId(String uid) => isCaller(uid) ? receiverId : callerId;

  CallModel copyWith({CallStatus? status, String? endReason, int? duration}) {
    return CallModel(
      callId: callId,
      callerId: callerId,
      receiverId: receiverId,
      callerName: callerName,
      receiverName: receiverName,
      callerPhotoUrl: callerPhotoUrl,
      receiverPhotoUrl: receiverPhotoUrl,
      participants: participants,
      type: type,
      status: status ?? this.status,
      endReason: endReason ?? this.endReason,
      createdAt: createdAt,
      ringingAt: ringingAt,
      acceptedAt: acceptedAt,
      connectedAt: connectedAt,
      endedAt: endedAt,
      endedBy: endedBy,
      duration: duration ?? this.duration,
    );
  }
}

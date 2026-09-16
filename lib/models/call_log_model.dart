import 'package:cloud_firestore/cloud_firestore.dart';

enum CallMethod {
  pstnDialer,
  voip;

  static CallMethod fromValue(String? value) {
    return CallMethod.values.firstWhere(
      (m) => m.name == value,
      orElse: () => CallMethod.pstnDialer,
    );
  }
}

enum CallLogStatus {
  dialed,
  completed,
  missed,
  received,
  declined;

  static CallLogStatus fromValue(String? value) {
    return CallLogStatus.values.firstWhere(
      (s) => s.name == value,
      orElse: () => CallLogStatus.dialed,
    );
  }
}

enum CallDirection {
  outgoing,
  incoming;

  static CallDirection fromValue(String? value) {
    return CallDirection.values.firstWhere(
      (d) => d.name == value,
      // Older docs predate this field — they were all outgoing.
      orElse: () => CallDirection.outgoing,
    );
  }
}

class CallLogEntry {
  final String id;
  final String contactId;
  final String calleeName;
  final String calleePhone;
  final CallMethod method;
  final CallLogStatus status;
  final CallDirection direction;
  final DateTime? startedAt;
  final DateTime? createdAt;

  /// Conversation length in seconds, filled in when the call ends (see
  /// `CallLogRepository.updateCallOutcome`).
  ///
  /// For `pstnDialer` entries this is measured between the off-hook and idle
  /// phone-state transitions rather than read from the OS, which never tells a
  /// non-default-dialer app how long a carrier call lasted. It stays 0 for a
  /// call that never connected — missed, declined, or unanswered — and for a
  /// call whose ending the app was not running to observe.
  final int duration;

  /// Links the entry back to its `calls/{callId}` document. Empty for
  /// cellular entries, which have no such document.
  final String callId;

  const CallLogEntry({
    required this.id,
    required this.contactId,
    required this.calleeName,
    required this.calleePhone,
    this.method = CallMethod.pstnDialer,
    this.status = CallLogStatus.dialed,
    this.direction = CallDirection.outgoing,
    this.startedAt,
    this.createdAt,
    this.duration = 0,
    this.callId = '',
  });

  factory CallLogEntry.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final map = doc.data() ?? <String, dynamic>{};
    return CallLogEntry(
      id: doc.id,
      contactId: map['contactId'] as String? ?? '',
      calleeName: map['calleeName'] as String? ?? '',
      calleePhone: map['calleePhone'] as String? ?? '',
      method: CallMethod.fromValue(map['method'] as String?),
      status: CallLogStatus.fromValue(map['status'] as String?),
      direction: CallDirection.fromValue(map['direction'] as String?),
      startedAt: (map['startedAt'] as Timestamp?)?.toDate(),
      createdAt: (map['createdAt'] as Timestamp?)?.toDate(),
      duration: (map['duration'] as num?)?.toInt() ?? 0,
      callId: map['callId'] as String? ?? '',
    );
  }

  Map<String, dynamic> toCreateMap() => {
    'contactId': contactId,
    'calleeName': calleeName,
    'calleePhone': calleePhone,
    'method': method.name,
    'status': status.name,
    'direction': direction.name,
    'startedAt': FieldValue.serverTimestamp(),
    'createdAt': FieldValue.serverTimestamp(),
  };
}

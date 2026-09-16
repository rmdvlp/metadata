import 'package:cloud_firestore/cloud_firestore.dart';

enum NotificationType {
  incomingCall,
  missedCall,
  outgoingCall,
  contextCaptured,
  anniversary,
  contactAdded,
  followUp,
  eventDetected,
  generic;

  static NotificationType fromValue(String? value) {
    return NotificationType.values.firstWhere(
      (t) => t.name == value,
      orElse: () => NotificationType.generic,
    );
  }

  /// The three kinds the bell surfaces: an incoming call (received or
  /// declined — both reached the user), a missed call, and an outgoing call.
  /// Everything else (contact added, anniversary, captured context…) is
  /// deliberately excluded from the notification screen and its badge count.
  bool get isCall =>
      this == NotificationType.incomingCall ||
      this == NotificationType.missedCall ||
      this == NotificationType.outgoingCall;

  static List<String> get callTypeNames => <String>[
    incomingCall.name,
    missedCall.name,
    outgoingCall.name,
  ];
}

class AppNotification {
  final String id;
  final NotificationType type;
  final String title;
  final String body;
  final String? imageUrl;
  final String? relatedContactId;
  final bool isRead;
  final DateTime? createdAt;
  final Map<String, dynamic> data;

  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    this.imageUrl,
    this.relatedContactId,
    this.isRead = false,
    this.createdAt,
    this.data = const {},
  });

  factory AppNotification.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final map = doc.data() ?? <String, dynamic>{};
    return AppNotification(
      id: doc.id,
      type: NotificationType.fromValue(map['type'] as String?),
      title: map['title'] as String? ?? '',
      body: map['body'] as String? ?? '',
      imageUrl: map['imageUrl'] as String?,
      relatedContactId: map['relatedContactId'] as String?,
      isRead: map['isRead'] as bool? ?? false,
      createdAt: (map['createdAt'] as Timestamp?)?.toDate(),
      data: (map['data'] as Map<String, dynamic>?) ?? const {},
    );
  }

  Map<String, dynamic> toCreateMap() => {
    'type': type.name,
    'title': title,
    'body': body,
    'imageUrl': imageUrl,
    'relatedContactId': relatedContactId,
    'isRead': isRead,
    'createdAt': FieldValue.serverTimestamp(),
    'data': data,
  };
}

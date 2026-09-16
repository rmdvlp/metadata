import 'package:cloud_firestore/cloud_firestore.dart';

class SupportTicket {
  final String id;
  final String uid;
  final String name;
  final String email;
  final String subject;
  final String message;
  final String status;
  final DateTime? createdAt;

  const SupportTicket({
    required this.id,
    required this.uid,
    required this.name,
    required this.email,
    required this.subject,
    required this.message,
    this.status = 'open',
    this.createdAt,
  });

  factory SupportTicket.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final map = doc.data() ?? <String, dynamic>{};
    return SupportTicket(
      id: doc.id,
      uid: map['uid'] as String? ?? '',
      name: map['name'] as String? ?? '',
      email: map['email'] as String? ?? '',
      subject: map['subject'] as String? ?? '',
      message: map['message'] as String? ?? '',
      status: map['status'] as String? ?? 'open',
      createdAt: (map['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toCreateMap() => {
    'uid': uid,
    'name': name,
    'email': email,
    'subject': subject,
    'message': message,
    'status': status,
    'createdAt': FieldValue.serverTimestamp(),
  };
}

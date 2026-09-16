import 'package:cloud_firestore/cloud_firestore.dart';

/// One entry in a contact's "Notes" list — lets a user keep more than one
/// note per contact instead of a single free-text field.
class NoteEntry {
  final String id;
  final String text;
  final DateTime? createdAt;

  const NoteEntry({required this.id, required this.text, this.createdAt});

  factory NoteEntry.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    return NoteEntry(
      id: doc.id,
      text: data['text'] as String? ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toCreateMap() => {
    'text': text,
    'createdAt': FieldValue.serverTimestamp(),
  };
}

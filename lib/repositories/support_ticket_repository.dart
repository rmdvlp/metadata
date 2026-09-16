import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metadata/core/firebase/firebase_providers.dart';
import 'package:metadata/models/support_ticket_model.dart';

final supportTicketRepositoryProvider = Provider<SupportTicketRepository>((ref) {
  return SupportTicketRepository(
    firestore: ref.watch(firebaseFirestoreProvider),
    auth: ref.watch(firebaseAuthProvider),
  );
});

class SupportTicketRepository {
  SupportTicketRepository({
    required FirebaseFirestore firestore,
    required FirebaseAuth auth,
  }) : _firestore = firestore,
       _auth = auth;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  String get _uid {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw StateError('No signed-in user');
    return uid;
  }

  CollectionReference<Map<String, dynamic>> get _ticketsRef =>
      _firestore.collection('support_tickets');

  Future<void> submitTicket({
    required String name,
    required String email,
    required String subject,
    required String message,
  }) async {
    final ticket = SupportTicket(
      id: '',
      uid: _uid,
      name: name,
      email: email,
      subject: subject,
      message: message,
    );
    await _ticketsRef.add(ticket.toCreateMap());
  }

  Stream<List<SupportTicket>> watchMyTickets() {
    return _ticketsRef
        .where('uid', isEqualTo: _uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map(SupportTicket.fromFirestore).toList());
  }
}

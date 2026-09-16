import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metadata/core/firebase/firebase_providers.dart';
import 'package:metadata/models/contact_model.dart';
import 'package:metadata/models/note_entry.dart';
import 'package:metadata/models/notification_model.dart';
import 'package:metadata/models/timeline_entry.dart';
import 'package:metadata/utils/phone_number.dart';

final contactRepositoryProvider = Provider<ContactRepository>((ref) {
  return ContactRepository(
    firestore: ref.watch(firebaseFirestoreProvider),
    auth: ref.watch(firebaseAuthProvider),
    storageReader: () => ref.read(firebaseStorageProvider),
  );
});

class ContactRepository {
  ContactRepository({
    required FirebaseFirestore firestore,
    required FirebaseAuth auth,
    required FirebaseStorage Function() storageReader,
  }) : _firestore = firestore,
       _auth = auth,
       _storageReader = storageReader;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  // Resolved lazily — most repository operations never touch Storage, so
  // this avoids requiring a working FirebaseStorage instance just to read
  // contacts (e.g. in widget tests that only render a screen).
  final FirebaseStorage Function() _storageReader;
  FirebaseStorage get _storage => _storageReader();

  String get _uid {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw StateError('No signed-in user');
    return uid;
  }

  CollectionReference<Map<String, dynamic>> get _contactsRef =>
      _firestore.collection('users').doc(_uid).collection('contacts');

  /// Alphabetical (A-Z, case-insensitive) by name — used for "All Contacts"
  /// style browsing. Sorted client-side rather than via Firestore `orderBy`
  /// so names differing only in case (e.g. "adam" vs "Adam") still land in
  /// the right place, which Firestore's byte-order string sort would not do.
  Stream<List<ContactModel>> watchContacts() {
    return _contactsRef.snapshots().map((snap) {
      final contacts = snap.docs.map(ContactModel.fromFirestore).toList();
      contacts.sort(
        (a, b) => a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()),
      );
      return contacts;
    });
  }

  Stream<List<ContactModel>> watchRecentContacts({int limit = 20}) {
    return _contactsRef
        .orderBy('updatedAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map(ContactModel.fromFirestore).toList());
  }

  Stream<ContactModel?> watchContact(String contactId) {
    return _contactsRef
        .doc(contactId)
        .snapshots()
        .map((doc) => doc.exists ? ContactModel.fromFirestore(doc) : null);
  }

  Future<ContactModel?> getContact(String contactId) async {
    final doc = await _contactsRef.doc(contactId).get();
    return doc.exists ? ContactModel.fromFirestore(doc) : null;
  }

  /// Client-side match against the incoming call's number, normalized via
  /// [normalizePhoneForMatching]. No `phoneNumberNormalized` field exists on
  /// contact docs (no schema migration for v1), so this pulls the full
  /// contact list once per incoming call — fine at personal-contact-list
  /// scale, worth revisiting if lists grow large.
  Future<ContactModel?> findByPhoneNumber(String phoneNumber) async {
    final target = normalizePhoneForMatching(phoneNumber);
    if (target.isEmpty) return null;
    final snap = await _contactsRef.get();
    for (final doc in snap.docs) {
      final contact = ContactModel.fromFirestore(doc);
      if (normalizePhoneForMatching(contact.phoneNumber) == target) {
        return contact;
      }
    }
    return null;
  }

  Future<Set<String>> getDeviceContactIds() async {
    final snap = await _contactsRef
        .where('source', isEqualTo: ContactSource.device.name)
        .get();
    return snap.docs
        .map((d) => d.data()['deviceContactId'] as String? ?? '')
        .where((s) => s.isNotEmpty)
        .toSet();
  }

  Future<String> createContact(ContactModel draft) async {
    final ref = await _contactsRef.add(draft.toCreateMap());
    await _notifyContactAdded(ref.id, draft.fullName, draft.photoUrl);
    return ref.id;
  }

  Future<void> _notifyContactAdded(
    String contactId,
    String fullName,
    String? photoUrl,
  ) async {
    await _firestore
        .collection('users')
        .doc(_uid)
        .collection('notifications')
        .add(
          AppNotification(
            id: '',
            type: NotificationType.contactAdded,
            title: 'Contact added',
            body: 'You saved $fullName.',
            relatedContactId: contactId,
            imageUrl: photoUrl,
          ).toCreateMap(),
        );
  }

  Future<void> updateContact(
    String contactId,
    Map<String, dynamic> patch,
  ) async {
    await _contactsRef.doc(contactId).set({
      ...patch,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Records that the user and this contact actually communicated, just now.
  ///
  /// Separate from a plain [updateContact] because the two mean different
  /// things: `updatedAt` moves for any edit, while `lastContactedAt` moves
  /// only for a real call. Quarantine reads the latter, so tidying someone's
  /// notes must not read as having spoken to them (see
  /// `lib/utils/contact_quarantine.dart`).
  ///
  /// This also bumps `updatedAt`, which is what keeps Home's "Recent
  /// Contacts" — sorted by `updatedAt` — reflecting who was last called.
  Future<void> markContacted(String contactId) {
    if (contactId.isEmpty) return Future.value();
    return updateContact(contactId, {
      'lastContactedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<String> uploadContactPhoto({
    required String contactId,
    required File file,
  }) async {
    final ref = _storage.ref('users/$_uid/contacts/$contactId/photo.jpg');
    await ref.putFile(file);
    final url = await ref.getDownloadURL();
    await updateContact(contactId, {'photoUrl': url});
    return url;
  }

  Future<String> uploadContactPhotoBytes({
    required String contactId,
    required Uint8List bytes,
  }) async {
    final ref = _storage.ref('users/$_uid/contacts/$contactId/photo.jpg');
    await ref.putData(bytes);
    final url = await ref.getDownloadURL();
    await updateContact(contactId, {'photoUrl': url});
    return url;
  }

  Future<void> deleteContact(String contactId) async {
    final timelineSnap = await _contactsRef
        .doc(contactId)
        .collection('timeline')
        .get();
    final notesSnap = await _contactsRef
        .doc(contactId)
        .collection('notes')
        .get();
    final batch = _firestore.batch();
    for (final doc in timelineSnap.docs) {
      batch.delete(doc.reference);
    }
    for (final doc in notesSnap.docs) {
      batch.delete(doc.reference);
    }
    batch.delete(_contactsRef.doc(contactId));
    await batch.commit();

    // Best-effort photo cleanup. The contact itself is already gone by now, so
    // nothing here may surface as a failure: reporting "could not delete" for
    // an unreachable Storage would leave the caller sitting on a contact that
    // no longer exists. Covers the common no-photo case and everything else
    // (offline, misconfigured Storage) alike.
    try {
      await _storage.ref('users/$_uid/contacts/$contactId/photo.jpg').delete();
    } catch (_) {
      // Ignored on purpose — see above.
    }
  }

  Future<void> deleteAllContacts() async {
    final snap = await _contactsRef.get();
    for (final doc in snap.docs) {
      await deleteContact(doc.id);
    }
  }

  Stream<List<TimelineEntry>> watchTimeline(String contactId) {
    return _contactsRef
        .doc(contactId)
        .collection('timeline')
        .orderBy('date', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map(TimelineEntry.fromFirestore).toList());
  }

  Future<void> addTimelineEntry(String contactId, TimelineEntry entry) async {
    await _contactsRef
        .doc(contactId)
        .collection('timeline')
        .add(entry.toCreateMap());
  }

  Future<void> updateTimelineEntry(
    String contactId,
    TimelineEntry entry,
  ) async {
    await _contactsRef
        .doc(contactId)
        .collection('timeline')
        .doc(entry.id)
        .update(entry.toUpdateMap());
  }

  Future<void> deleteTimelineEntry(String contactId, String entryId) async {
    await _contactsRef
        .doc(contactId)
        .collection('timeline')
        .doc(entryId)
        .delete();
  }

  Stream<List<NoteEntry>> watchNotes(String contactId) {
    return _contactsRef
        .doc(contactId)
        .collection('notes')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map(NoteEntry.fromFirestore).toList());
  }

  Future<void> addNote(String contactId, String text) async {
    await _contactsRef
        .doc(contactId)
        .collection('notes')
        .add(NoteEntry(id: '', text: text).toCreateMap());
  }

  /// Leaves `createdAt` alone so an edited note keeps its place in the list
  /// rather than jumping to the top.
  Future<void> updateNote(String contactId, String noteId, String text) async {
    await _contactsRef.doc(contactId).collection('notes').doc(noteId).update({
      'text': text,
    });
  }

  Future<void> deleteNote(String contactId, String noteId) async {
    await _contactsRef.doc(contactId).collection('notes').doc(noteId).delete();
  }
}

/// Single tap on a contact's heart badge toggles favorite — shared by every
/// screen that renders a [ContactAvatar] so the toggle behaves identically
/// everywhere instead of being reimplemented per screen.
Future<void> toggleContactFavorite(WidgetRef ref, ContactModel contact) {
  return ref.read(contactRepositoryProvider).updateContact(contact.id, {
    'isFavorite': !contact.isFavorite,
  });
}

final recentContactsProvider = StreamProvider.autoDispose<List<ContactModel>>((
  ref,
) {
  return ref.watch(contactRepositoryProvider).watchRecentContacts();
});

final allContactsProvider = StreamProvider.autoDispose<List<ContactModel>>((
  ref,
) {
  return ref.watch(contactRepositoryProvider).watchContacts();
});

final contactByIdProvider = StreamProvider.autoDispose
    .family<ContactModel?, String>((ref, id) {
      return ref.watch(contactRepositoryProvider).watchContact(id);
    });

final contactTimelineProvider = StreamProvider.autoDispose
    .family<List<TimelineEntry>, String>((ref, id) {
      return ref.watch(contactRepositoryProvider).watchTimeline(id);
    });

final contactNotesProvider = StreamProvider.autoDispose
    .family<List<NoteEntry>, String>((ref, id) {
      return ref.watch(contactRepositoryProvider).watchNotes(id);
    });

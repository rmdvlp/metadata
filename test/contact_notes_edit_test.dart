import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metadata/models/contact_model.dart';
import 'package:metadata/repositories/contact_repository.dart';

const _uid = 'test-uid';
const _contactId = 'c1';

void main() {
  late FakeFirebaseFirestore firestore;
  late ContactRepository repository;

  CollectionReference<Map<String, dynamic>> notes() => firestore
      .collection('users')
      .doc(_uid)
      .collection('contacts')
      .doc(_contactId)
      .collection('notes');

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repository = ContactRepository(
      firestore: firestore,
      auth: MockFirebaseAuth(mockUser: MockUser(uid: _uid), signedIn: true),
      storageReader: () => throw UnimplementedError('Storage not needed here'),
    );
  });

  group('updateNote', () {
    test('rewrites the text of an existing note', () async {
      await repository.addNote(_contactId, 'Met at the museum');
      final noteId = (await notes().get()).docs.single.id;

      await repository.updateNote(_contactId, noteId, 'Met at the gallery');

      final docs = (await notes().get()).docs;
      expect(docs, hasLength(1), reason: 'edit must not create a second note');
      expect(docs.single.data()['text'], 'Met at the gallery');
    });

    test('leaves createdAt alone so the note keeps its place in the list',
        () async {
      await repository.addNote(_contactId, 'First');
      final doc = (await notes().get()).docs.single;
      final createdAt = doc.data()['createdAt'];

      await repository.updateNote(_contactId, doc.id, 'First, edited');

      expect((await notes().doc(doc.id).get()).data()!['createdAt'], createdAt);
    });

    test('the contact\'s own note can be rewritten and cleared', () async {
      final contactId = await repository.createContact(
        const ContactModel(
          id: '',
          fullName: 'Ada',
          phoneNumber: '+14155550101',
          notes: 'Met at the museum',
        ),
      );
      final doc = firestore
          .collection('users')
          .doc(_uid)
          .collection('contacts')
          .doc(contactId);

      await repository.updateContact(contactId, {'notes': 'Met at the gallery'});
      expect((await doc.get()).data()!['notes'], 'Met at the gallery');

      // Deleting writes null, which reads back as "no note at all" — the same
      // state as a contact that never had one.
      await repository.updateContact(contactId, {'notes': null});
      expect((await doc.get()).data()!['notes'], isNull);
      expect(ContactModel.fromFirestore(await doc.get()).notes, isNull);
    });

    test('touches only the note it names', () async {
      await repository.addNote(_contactId, 'Keep me');
      await repository.addNote(_contactId, 'Change me');
      final byText = {
        for (final d in (await notes().get()).docs) d.data()['text']: d.id,
      };

      await repository.updateNote(_contactId, byText['Change me']!, 'Changed');

      final texts = (await notes().get()).docs
          .map((d) => d.data()['text'] as String)
          .toList()
        ..sort();
      expect(texts, ['Changed', 'Keep me']);
    });
  });
}

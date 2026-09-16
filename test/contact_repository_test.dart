import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metadata/repositories/contact_repository.dart';

const _testUid = 'test-uid';

void main() {
  late FakeFirebaseFirestore fakeFirestore;
  late MockFirebaseAuth mockAuth;
  late ContactRepository repository;

  setUp(() {
    final mockUser = MockUser(uid: _testUid);
    mockAuth = MockFirebaseAuth(mockUser: mockUser, signedIn: true);
    fakeFirestore = FakeFirebaseFirestore();
    repository = ContactRepository(
      firestore: fakeFirestore,
      auth: mockAuth,
      storageReader: () => throw UnimplementedError('Storage not needed for this test'),
    );
  });

  group('findByPhoneNumber', () {
    Future<void> seedContact(String phoneNumber) {
      return fakeFirestore
          .collection('users')
          .doc(_testUid)
          .collection('contacts')
          .doc('contact-1')
          .set({
            'fullName': 'Jane Doe',
            'phoneNumber': phoneNumber,
            'source': 'manual',
            'createdAt': Timestamp.now(),
            'updatedAt': Timestamp.now(),
          });
    }

    test('matches a differently formatted incoming number', () async {
      await seedContact('(555) 123-4567');

      final contact = await repository.findByPhoneNumber('+15551234567');

      expect(contact, isNotNull);
      expect(contact!.fullName, 'Jane Doe');
    });

    test('returns null when no contact matches', () async {
      await seedContact('5551234567');

      final contact = await repository.findByPhoneNumber('+19998887777');

      expect(contact, isNull);
    });

    // This lookup is what the incoming-call path consults to decide whether to
    // suppress the call card, so the blocked flag has to survive the round trip.
    test('carries the blocked flag through to the incoming-call lookup', () async {
      await fakeFirestore
          .collection('users')
          .doc(_testUid)
          .collection('contacts')
          .doc('contact-blocked')
          .set({
            'fullName': 'Blocked Caller',
            'phoneNumber': '(555) 987-6543',
            'source': 'manual',
            'isBlocked': true,
            'createdAt': Timestamp.now(),
            'updatedAt': Timestamp.now(),
          });

      final contact = await repository.findByPhoneNumber('+15559876543');

      expect(contact, isNotNull);
      expect(contact!.isBlocked, isTrue);
    });

    test('treats a contact saved before blocking existed as unblocked', () async {
      await seedContact('5551234567'); // no isBlocked field at all

      final contact = await repository.findByPhoneNumber('5551234567');

      expect(contact!.isBlocked, isFalse);
    });
  });
}

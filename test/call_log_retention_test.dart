import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metadata/repositories/call_log_repository.dart';

const _testUid = 'test-uid';
final _now = DateTime(2026, 8, 10, 9);

void main() {
  late FakeFirebaseFirestore fakeFirestore;
  late MockFirebaseAuth mockAuth;
  late CallLogRepository repository;

  CollectionReference<Map<String, dynamic>> callLogs() => fakeFirestore
      .collection('users')
      .doc(_testUid)
      .collection('call_logs');

  setUp(() {
    mockAuth = MockFirebaseAuth(
      mockUser: MockUser(uid: _testUid),
      signedIn: true,
    );
    fakeFirestore = FakeFirebaseFirestore();
    repository = CallLogRepository(firestore: fakeFirestore, auth: mockAuth);
  });

  Future<void> seedLog(String id, {DateTime? startedAt}) {
    return callLogs().doc(id).set({
      'contactId': '',
      'calleeName': 'Ada',
      'calleePhone': '+14155550101',
      'method': 'pstnDialer',
      'status': 'dialed',
      'direction': 'outgoing',
      if (startedAt != null) 'startedAt': Timestamp.fromDate(startedAt),
      'createdAt': Timestamp.fromDate(startedAt ?? _now),
    });
  }

  group('purgeExpiredCallLogs', () {
    test('deletes only logs older than the seven-day window', () async {
      await seedLog('today', startedAt: _now);
      await seedLog('six-days', startedAt: _now.subtract(const Duration(days: 6)));
      await seedLog(
        'eight-days',
        startedAt: _now.subtract(const Duration(days: 8)),
      );
      await seedLog('ancient', startedAt: _now.subtract(const Duration(days: 90)));

      final deleted = await repository.purgeExpiredCallLogs(now: _now);

      expect(deleted, 2);
      final remaining = await callLogs().get();
      expect(
        remaining.docs.map((doc) => doc.id).toList()..sort(),
        ['six-days', 'today'],
      );
    });

    test('leaves a call whose server timestamp is still pending', () async {
      // A just-written entry has no resolved startedAt yet; sweeping it would
      // delete the call the user is placing right now.
      await seedLog('pending');

      final deleted = await repository.purgeExpiredCallLogs(now: _now);

      expect(deleted, 0);
      expect((await callLogs().get()).docs, hasLength(1));
    });

    test('is a no-op when nothing has expired', () async {
      await seedLog('today', startedAt: _now);

      expect(await repository.purgeExpiredCallLogs(now: _now), 0);
      expect((await callLogs().get()).docs, hasLength(1));
    });

    test('deletes nothing when signed out', () async {
      await seedLog('ancient', startedAt: _now.subtract(const Duration(days: 90)));
      final signedOut = CallLogRepository(
        firestore: fakeFirestore,
        auth: MockFirebaseAuth(signedIn: false),
      );

      expect(await signedOut.purgeExpiredCallLogs(now: _now), 0);
      expect((await callLogs().get()).docs, hasLength(1));
    });
  });
}

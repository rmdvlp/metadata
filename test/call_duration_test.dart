import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metadata/models/call_log_model.dart';
import 'package:metadata/models/contact_model.dart';
import 'package:metadata/repositories/call_log_repository.dart';
import 'package:metadata/utils/date_formatting.dart';

const _testUid = 'test-uid';

/// A call is logged when it starts (the only moment guaranteed to happen) and
/// completed when it ends. Both halves are covered here, because getting the
/// second half wrong is what produced the two bugs this replaced: a duplicate
/// Recent Call Logs row per call, and an outgoing call recorded as missed.
void main() {
  late FakeFirebaseFirestore fakeFirestore;
  late CallLogRepository repository;

  setUp(() {
    fakeFirestore = FakeFirebaseFirestore();
    repository = CallLogRepository(
      firestore: fakeFirestore,
      auth: MockFirebaseAuth(mockUser: MockUser(uid: _testUid), signedIn: true),
    );
  });

  Future<List<CallLogEntry>> allLogs() async {
    final snap = await fakeFirestore
        .collection('users')
        .doc(_testUid)
        .collection('call_logs')
        .get();
    return snap.docs.map(CallLogEntry.fromFirestore).toList();
  }

  group('formatCallDuration', () {
    test('reads as a clock, dropping hours until there are any', () {
      expect(formatCallDuration(0), '0:00');
      expect(formatCallDuration(9), '0:09');
      expect(formatCallDuration(247), '4:07');
      expect(formatCallDuration(3600), '1:00:00');
      expect(formatCallDuration(3930), '1:05:30');
    });

    test('a backwards clock reads as zero, not as a negative duration', () {
      expect(formatCallDuration(-5), '0:00');
    });
  });

  group('updateCallOutcome', () {
    test('completes the existing entry instead of adding a second one', () async {
      final id = await repository.logCallAttempt(
        contactId: 'c1',
        calleeName: 'Ada',
        calleePhone: '+14155550101',
      );

      await repository.updateCallOutcome(
        id: id!,
        status: CallLogStatus.completed,
        durationSeconds: 95,
      );

      final logs = await allLogs();
      expect(logs, hasLength(1), reason: 'one call must mean one row');
      expect(logs.single.status, CallLogStatus.completed);
      expect(logs.single.duration, 95);
      expect(logs.single.direction, CallDirection.outgoing);
    });

    test('an answered incoming call keeps its status and gains a duration', () async {
      final id = await repository.logIncomingCall(
        contactId: 'c1',
        callerName: 'Ada',
        callerPhone: '+14155550101',
        status: CallLogStatus.received,
      );

      await repository.updateCallOutcome(id: id!, durationSeconds: 42);

      final logs = await allLogs();
      expect(logs, hasLength(1));
      expect(logs.single.status, CallLogStatus.received);
      expect(logs.single.duration, 42);
    });

    test('a call that never connected is left alone, not zero-stamped', () async {
      // An outgoing call nobody picked up, or a missed incoming one: the entry
      // must stay exactly as it was rather than being rewritten as a
      // zero-length conversation.
      final id = await repository.logCallAttempt(
        contactId: 'c1',
        calleeName: 'Ada',
        calleePhone: '+14155550101',
      );

      await repository.updateCallOutcome(id: id!, durationSeconds: 0);

      final logs = await allLogs();
      expect(logs.single.status, CallLogStatus.dialed);
      expect(logs.single.duration, 0);
    });

    test('an unknown id is a no-op rather than a crash mid-call', () async {
      await repository.updateCallOutcome(id: '', durationSeconds: 30);
      expect(await allLogs(), isEmpty);
    });
  });

  group('RecentCallLog.durationLabel', () {
    RecentCallLog logWith({required int duration, required CallLogStatus status}) {
      return RecentCallLog(
        entry: CallLogEntry(
          id: 'l1',
          contactId: 'c1',
          calleeName: 'Ada',
          calleePhone: '+14155550101',
          status: status,
          duration: duration,
        ),
        contact: const ContactModel(
          id: 'c1',
          fullName: 'Ada',
          phoneNumber: '+14155550101',
        ),
      );
    }

    test('shows talk time for a call that connected', () {
      expect(
        logWith(duration: 247, status: CallLogStatus.completed).durationLabel,
        '4:07',
      );
    });

    test('shows nothing when there was no conversation to measure', () {
      expect(logWith(duration: 0, status: CallLogStatus.missed).durationLabel, isNull);
      expect(
        logWith(duration: 0, status: CallLogStatus.declined).durationLabel,
        isNull,
      );
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:metadata/models/call_log_model.dart';
import 'package:metadata/models/contact_model.dart';
import 'package:metadata/repositories/call_log_repository.dart';

CallLogEntry _log({
  required String id,
  String contactId = '',
  String name = '',
  String phone = '',
  CallLogStatus status = CallLogStatus.dialed,
  CallDirection direction = CallDirection.outgoing,
  DateTime? startedAt,
}) {
  return CallLogEntry(
    id: id,
    contactId: contactId,
    calleeName: name,
    calleePhone: phone,
    status: status,
    direction: direction,
    startedAt: startedAt,
  );
}

ContactModel _contact({
  required String id,
  required String name,
  required String phone,
}) {
  return ContactModel(id: id, fullName: name, phoneNumber: phone);
}

final _t0 = DateTime(2026, 8, 10, 9);

void main() {
  group('buildRecentCallLogs', () {
    test('shows only parties with a call log, not the whole contact book', () {
      final contacts = [
        _contact(id: 'c1', name: 'Ada', phone: '+1 415 555 0101'),
        // Synced from the device but never called — must not appear.
        _contact(id: 'c2', name: 'Never Called', phone: '+1 415 555 0202'),
      ];
      final logs = [
        _log(
          id: 'l1',
          contactId: 'c1',
          name: 'Ada',
          phone: '+14155550101',
          startedAt: _t0,
        ),
      ];

      final rows = buildRecentCallLogs(logs, contacts, now: _t0);

      expect(rows, hasLength(1));
      expect(rows.single.contact.id, 'c1');
      expect(rows.single.contact.fullName, 'Ada');
    });

    test('returns nothing when there are contacts but no calls', () {
      final contacts = [
        _contact(id: 'c1', name: 'Ada', phone: '+14155550101'),
      ];
      expect(buildRecentCallLogs(const [], contacts, now: _t0), isEmpty);
    });

    test('keeps every call as its own row, newest first', () {
      final contacts = [_contact(id: 'c1', name: 'Ada', phone: '+14155550101')];
      final logs = [
        _log(
          id: 'old',
          contactId: 'c1',
          phone: '+14155550101',
          startedAt: _t0.subtract(const Duration(hours: 3)),
        ),
        _log(
          id: 'new',
          contactId: 'c1',
          phone: '+14155550101',
          status: CallLogStatus.missed,
          direction: CallDirection.incoming,
          startedAt: _t0,
        ),
      ];

      final rows = buildRecentCallLogs(logs, contacts, now: _t0);

      expect(rows.map((r) => r.entry.id), ['new', 'old']);
      expect(rows.first.isMissed, isTrue);
      // Both rows still resolve to the same saved contact.
      expect(rows.every((r) => r.contact.id == 'c1'), isTrue);
    });

    test('keeps the same person reached on two numbers as two rows', () {
      final contacts = [_contact(id: 'c1', name: 'Ada', phone: '+14155550101')];
      final logs = [
        _log(id: 'l1', contactId: 'c1', phone: '+14155550101', startedAt: _t0),
        _log(
          id: 'l2',
          contactId: 'c1',
          phone: '+14155559999',
          startedAt: _t0.subtract(const Duration(minutes: 5)),
        ),
      ];

      expect(buildRecentCallLogs(logs, contacts, now: _t0), hasLength(2));
    });

    test('resolves a contact by phone number when the log has no contactId',
        () {
      final contacts = [
        _contact(id: 'c1', name: 'Ada', phone: '(415) 555-0101'),
      ];
      // Differently formatted, and no contactId — as written by an incoming
      // call from a number the dialer never linked.
      final logs = [
        _log(
          id: 'l1',
          phone: '+1 415-555-0101',
          status: CallLogStatus.received,
          direction: CallDirection.incoming,
          startedAt: _t0,
        ),
      ];

      final rows = buildRecentCallLogs(logs, contacts, now: _t0);

      expect(rows.single.contact.id, 'c1');
      expect(rows.single.contact.fullName, 'Ada');
    });

    test('keeps unsaved numbers as rows backed by a placeholder contact', () {
      final logs = [
        _log(
          id: 'l1',
          name: 'Unknown Caller',
          phone: '+14155557777',
          status: CallLogStatus.missed,
          direction: CallDirection.incoming,
          startedAt: _t0,
        ),
      ];

      final rows = buildRecentCallLogs(logs, const [], now: _t0);

      expect(rows, hasLength(1));
      expect(rows.single.contact.fullName, 'Unknown Caller');
      expect(rows.single.contact.phoneNumber, '+14155557777');
      // Empty id is the signal the feed uses to suppress navigation.
      expect(rows.single.contact.id, isEmpty);
    });

    test('falls back to the number, then to Unknown, for a nameless log', () {
      final numbered = buildRecentCallLogs([
        _log(id: 'l1', phone: '+14155557777', startedAt: _t0),
      ], const [], now: _t0);
      expect(numbered.single.contact.fullName, '+14155557777');

      final anonymous = buildRecentCallLogs([
        _log(id: 'l2', startedAt: _t0),
      ], const [], now: _t0);
      expect(anonymous.single.contact.fullName, 'Unknown');
    });

    test('a call still awaiting its server timestamp sorts to the top', () {
      final logs = [
        _log(id: 'settled', phone: '+14155550101', startedAt: _t0),
        // Pending serverTimestamp reads as null in the local snapshot.
        _log(id: 'pending', phone: '+14155550202'),
      ];

      final rows = buildRecentCallLogs(logs, const [], now: _t0);

      expect(rows.map((r) => r.entry.id), ['pending', 'settled']);
    });

    test('orders rows newest first regardless of input order', () {
      final logs = [
        _log(
          id: 'oldest',
          phone: '+14155550101',
          startedAt: _t0.subtract(const Duration(days: 2)),
        ),
        _log(id: 'newest', phone: '+14155550303', startedAt: _t0),
        _log(
          id: 'middle',
          phone: '+14155550202',
          startedAt: _t0.subtract(const Duration(hours: 1)),
        ),
      ];

      final rows = buildRecentCallLogs(logs, const [], now: _t0);

      expect(rows.map((r) => r.entry.id), ['newest', 'middle', 'oldest']);
    });

    test('drops calls older than the seven-day retention window', () {
      final logs = [
        _log(id: 'fresh', phone: '+14155550101', startedAt: _t0),
        _log(
          id: 'edge',
          phone: '+14155550202',
          // Just inside the window.
          startedAt: _t0.subtract(const Duration(days: 7)).add(
            const Duration(minutes: 1),
          ),
        ),
        _log(
          id: 'expired',
          phone: '+14155550303',
          startedAt: _t0.subtract(const Duration(days: 7, minutes: 1)),
        ),
        _log(
          id: 'ancient',
          phone: '+14155550404',
          startedAt: _t0.subtract(const Duration(days: 30)),
        ),
      ];

      final rows = buildRecentCallLogs(logs, const [], now: _t0);

      expect(rows.map((r) => r.entry.id), ['fresh', 'edge']);
    });

    test('a pending call is never treated as expired', () {
      final rows = buildRecentCallLogs([
        _log(id: 'pending', phone: '+14155550101'),
      ], const [], now: _t0);

      expect(rows.map((r) => r.entry.id), ['pending']);
    });

    test('returns the whole window by default and honours an explicit limit',
        () {
      final logs = List.generate(
        45,
        (i) => _log(
          id: 'l$i',
          phone: '+1415555${i.toString().padLeft(4, '0')}',
          startedAt: _t0.subtract(Duration(minutes: i)),
        ),
      );

      // No limit: the See All screen gets everything in the window.
      expect(buildRecentCallLogs(logs, const [], now: _t0), hasLength(45));
      // Home's first page.
      expect(
        buildRecentCallLogs(logs, const [], now: _t0, limit: 30),
        hasLength(30),
      );
    });
  });

  group('RecentCallLog direction and label', () {
    RecentCallLog row(CallLogStatus status, CallDirection direction) {
      return RecentCallLog(
        entry: _log(id: 'l', status: status, direction: direction),
        contact: _contact(id: 'c', name: 'Ada', phone: '+14155550101'),
      );
    }

    test('outgoing statuses read as outgoing', () {
      final dialed = row(CallLogStatus.dialed, CallDirection.outgoing);
      expect(dialed.isIncoming, isFalse);
      expect(dialed.isMissed, isFalse);
      expect(dialed.statusLabel, 'Outgoing');

      final completed = row(CallLogStatus.completed, CallDirection.outgoing);
      expect(completed.isIncoming, isFalse);
      expect(completed.statusLabel, 'Outgoing');
    });

    test('incoming statuses read as incoming', () {
      final received = row(CallLogStatus.received, CallDirection.incoming);
      expect(received.isIncoming, isTrue);
      expect(received.statusLabel, 'Incoming');

      final completed = row(CallLogStatus.completed, CallDirection.incoming);
      expect(completed.isIncoming, isTrue);
      expect(completed.statusLabel, 'Incoming');
    });

    test('missed and declined keep the incoming side', () {
      final missed = row(CallLogStatus.missed, CallDirection.incoming);
      expect(missed.isIncoming, isTrue);
      expect(missed.isMissed, isTrue);
      expect(missed.statusLabel, 'Missed');

      final declined = row(CallLogStatus.declined, CallDirection.incoming);
      expect(declined.isIncoming, isTrue);
      expect(declined.isMissed, isFalse);
      expect(declined.statusLabel, 'Declined');
    });
  });
}

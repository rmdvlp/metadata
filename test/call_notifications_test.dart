import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metadata/models/notification_model.dart';
import 'package:metadata/repositories/notification_repository.dart';

const _testUid = 'test-uid';
final _now = DateTime(2026, 8, 10, 9);

void main() {
  late FakeFirebaseFirestore fakeFirestore;
  late NotificationRepository repository;

  CollectionReference<Map<String, dynamic>> notifications() => fakeFirestore
      .collection('users')
      .doc(_testUid)
      .collection('notifications');

  setUp(() {
    fakeFirestore = FakeFirebaseFirestore();
    repository = NotificationRepository(
      firestore: fakeFirestore,
      auth: MockFirebaseAuth(
        mockUser: MockUser(uid: _testUid),
        signedIn: true,
      ),
    );
  });

  Future<void> seed(
    String id,
    NotificationType type, {
    bool isRead = false,
    int minutesAgo = 0,
  }) {
    return notifications().doc(id).set({
      'type': type.name,
      'title': id,
      'body': '',
      'isRead': isRead,
      'createdAt': Timestamp.fromDate(
        _now.subtract(Duration(minutes: minutesAgo)),
      ),
      'data': <String, dynamic>{},
    });
  }

  group('NotificationType.isCall', () {
    test('covers exactly incoming, missed and outgoing calls', () {
      expect(
        NotificationType.values.where((t) => t.isCall).toList(),
        [
          NotificationType.incomingCall,
          NotificationType.missedCall,
          NotificationType.outgoingCall,
        ],
      );
    });
  });

  group('watchCallNotifications', () {
    test('surfaces only the three call kinds, newest first', () async {
      await seed('outgoing', NotificationType.outgoingCall, minutesAgo: 1);
      await seed('missed', NotificationType.missedCall, minutesAgo: 0);
      await seed('incoming', NotificationType.incomingCall, minutesAgo: 2);
      // Everything below must stay out of the bell feed.
      await seed('contact-added', NotificationType.contactAdded);
      await seed('anniversary', NotificationType.anniversary);
      await seed('generic', NotificationType.generic);

      final feed = await repository.watchCallNotifications().first;

      expect(feed.map((n) => n.title), ['missed', 'outgoing', 'incoming']);
    });
  });

  group('bell badge count', () {
    test('counts unread call notifications only', () async {
      await seed('missed', NotificationType.missedCall);
      await seed('incoming', NotificationType.incomingCall);
      await seed('outgoing-read', NotificationType.outgoingCall, isRead: true);
      await seed('contact-added', NotificationType.contactAdded);

      final feed = await repository.watchCallNotifications().first;

      expect(feed.where((n) => !n.isRead), hasLength(2));
    });
  });

  group('markAllCallNotificationsRead', () {
    test('clears the call notifications and leaves the rest unread', () async {
      await seed('missed', NotificationType.missedCall);
      await seed('incoming', NotificationType.incomingCall);
      await seed('outgoing', NotificationType.outgoingCall);
      await seed('contact-added', NotificationType.contactAdded);

      await repository.markAllCallNotificationsRead();

      final snap = await notifications().get();
      final readById = {
        for (final doc in snap.docs) doc.id: doc.data()['isRead'] as bool,
      };
      expect(readById, {
        'missed': true,
        'incoming': true,
        'outgoing': true,
        'contact-added': false,
      });
    });
  });
}

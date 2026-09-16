import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metadata/core/firebase/firebase_providers.dart';
import 'package:metadata/models/notification_model.dart';

final notificationRepositoryProvider = Provider<NotificationRepository>((ref) {
  return NotificationRepository(
    firestore: ref.watch(firebaseFirestoreProvider),
    auth: ref.watch(firebaseAuthProvider),
  );
});

class NotificationRepository {
  NotificationRepository({
    required FirebaseFirestore firestore,
    required FirebaseAuth auth,
  }) : _firestore = firestore,
       _auth = auth;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  CollectionReference<Map<String, dynamic>>? get _ref {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return null;
    return _firestore.collection('users').doc(uid).collection('notifications');
  }

  Stream<List<AppNotification>> watchNotifications() {
    final ref = _ref;
    if (ref == null) return Stream.value(const []);
    return ref
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map(AppNotification.fromFirestore).toList());
  }

  Future<void> create(AppNotification notification) async {
    final ref = _ref;
    if (ref == null) return;
    await ref.add(notification.toCreateMap());
  }

  Future<void> markAsRead(String id) async {
    final ref = _ref;
    if (ref == null) return;
    await ref.doc(id).set({'isRead': true}, SetOptions(merge: true));
  }

  Future<void> markAllAsRead() async {
    final ref = _ref;
    if (ref == null) return;
    final snap = await ref.where('isRead', isEqualTo: false).get();
    if (snap.docs.isEmpty) return;
    final batch = _firestore.batch();
    for (final doc in snap.docs) {
      batch.set(doc.reference, {'isRead': true}, SetOptions(merge: true));
    }
    await batch.commit();
  }

  /// Clears the bell badge: marks only the call notifications read, leaving
  /// any other unread notification untouched.
  Future<void> markAllCallNotificationsRead() async {
    final ref = _ref;
    if (ref == null) return;
    final snap = await ref.where('isRead', isEqualTo: false).get();
    final callDocs = snap.docs.where(
      (doc) => NotificationType.fromValue(doc.data()['type'] as String?).isCall,
    );
    if (callDocs.isEmpty) return;
    final batch = _firestore.batch();
    for (final doc in callDocs) {
      batch.set(doc.reference, {'isRead': true}, SetOptions(merge: true));
    }
    await batch.commit();
  }

  /// Incoming, missed and outgoing call notifications only — the feed behind
  /// the bell icon.
  Stream<List<AppNotification>> watchCallNotifications() {
    return watchNotifications().map(
      (notifications) =>
          notifications.where((notification) => notification.type.isCall).toList(),
    );
  }

  Future<void> createFromRemoteMessage(RemoteMessage message) async {
    final ref = _ref;
    if (ref == null) return;

    final notification = message.notification;
    final data = message.data;

    final entry = AppNotification(
      id: '',
      type: NotificationType.fromValue(data['type'] as String?),
      title: notification?.title ?? data['title'] as String? ?? 'Notification',
      body: notification?.body ?? data['body'] as String? ?? '',
      imageUrl: notification?.android?.imageUrl ?? notification?.apple?.imageUrl,
      relatedContactId: data['contactId'] as String?,
      data: data,
    );

    await ref.add(entry.toCreateMap());
  }
}

final notificationsProvider = StreamProvider.autoDispose<List<AppNotification>>((ref) {
  return ref.watch(notificationRepositoryProvider).watchNotifications();
});

final callNotificationsProvider = StreamProvider.autoDispose<List<AppNotification>>((ref) {
  return ref.watch(notificationRepositoryProvider).watchCallNotifications();
});

/// Drives the badge on Home's bell icon.
final unreadCallNotificationCountProvider = Provider.autoDispose<int>((ref) {
  return ref.watch(callNotificationsProvider).maybeWhen(
        data: (list) => list.where((notification) => !notification.isRead).length,
        orElse: () => 0,
      );
});

final unreadNotificationCountProvider = Provider.autoDispose<int>((ref) {
  return ref
      .watch(notificationsProvider)
      .maybeWhen(
        data: (list) => list.where((n) => !n.isRead).length,
        orElse: () => 0,
      );
});

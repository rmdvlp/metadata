import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:metadata/firebase_options.dart';
import 'package:metadata/models/notification_model.dart';

/// Must be a top-level function annotated with `vm:entry-point` so the Dart
/// compiler doesn't strip it — it runs on a separate background isolate.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return;

  final notification = message.notification;
  final data = message.data;

  // Incoming-call pushes are handled entirely on the native side (Android's
  // FCM service posts the full-screen call notification; iOS uses PushKit),
  // because a Dart background isolate takes too long to start to be a
  // dependable path for a ringing phone. Writing a `notifications` document
  // here would also leave a stray "notification" entry for every call.
  if (data['type'] == 'incoming_call' || data['type'] == 'call_ended') {
    debugPrint('Skipping call payload in Dart background handler: ${data['callId']}');
    return;
  }

  await FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .collection('notifications')
      .add(
        AppNotification(
          id: '',
          type: NotificationType.fromValue(data['type'] as String?),
          title: notification?.title ?? data['title'] as String? ?? 'Notification',
          body: notification?.body ?? data['body'] as String? ?? '',
          relatedContactId: data['contactId'] as String?,
          data: data,
        ).toCreateMap(),
      );

  debugPrint('Handled background FCM message: ${message.messageId}');
}

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final localNotificationsServiceProvider = Provider<LocalNotificationsService>((ref) {
  return LocalNotificationsService();
});

/// Shows a real system notification banner for foreground FCM messages
/// (iOS/Android suppress the system banner for foreground pushes by default).
class LocalNotificationsService {
  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'high_importance_channel',
    'High Importance Notifications',
    description: 'Used for important notifications from Metadata.',
    importance: Importance.high,
  );

  // Separate from _channel: an incoming call's lifecycle (shown on ringing,
  // cancelled on answer/decline/hangup) is entirely different from a normal
  // FCM banner's, so it gets its own channel and its own fixed notification
  // id (there's only ever one active call at a time).
  static const AndroidNotificationChannel _callChannel = AndroidNotificationChannel(
    'incoming_call_channel',
    'Incoming Calls',
    description: 'Shown while a call is ringing so it can be answered from the lock screen.',
    importance: Importance.max,
  );

  static const int incomingCallNotificationId = 990011;

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings();
    await _plugin.initialize(
      settings: const InitializationSettings(android: androidSettings, iOS: iosSettings),
    );

    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(_channel);
    await androidPlugin?.createNotificationChannel(_callChannel);
  }

  /// Full-screen incoming-call banner (Android only — iOS never controls
  /// the real call, so it only gets the in-app overlay via CXCallObserver,
  /// not a system notification). `payload` round-trips the caller's number
  /// so a cold-start tap can re-open [CallingScreen] with the right data.
  Future<void> showIncomingCallNotification({
    required String title,
    required String body,
    required String payload,
  }) async {
    await _plugin.show(
      id: incomingCallNotificationId,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _callChannel.id,
          _callChannel.name,
          channelDescription: _callChannel.description,
          importance: Importance.max,
          priority: Priority.max,
          category: AndroidNotificationCategory.call,
          fullScreenIntent: true,
          ongoing: true,
          autoCancel: false,
          visibility: NotificationVisibility.public,
        ),
      ),
      payload: payload,
    );
  }

  Future<void> cancelIncomingCallNotification() async {
    await _plugin.cancel(id: incomingCallNotificationId);
  }

  Future<void> showRemoteMessage(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;

    await _plugin.show(
      id: notification.hashCode,
      title: notification.title,
      body: notification.body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: const DarwinNotificationDetails(),
      ),
    );
  }
}

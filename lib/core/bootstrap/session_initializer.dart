import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metadata/core/firebase/firebase_services.dart';
import 'package:metadata/core/firebase/local_notifications_service.dart';
import 'package:metadata/features/calling/data/device_registry_datasource.dart';
import 'package:metadata/features/calling/services/call_coordinator.dart';
import 'package:metadata/repositories/call_log_repository.dart';
import 'package:metadata/repositories/incoming_call_service.dart';
import 'package:metadata/repositories/notification_repository.dart';

/// Runs once per app session (after the user is fully onboarded) to start
/// FCM/local-notification wiring and record `lastActiveAt`, then renders
/// [child] unconditionally — this never blocks or re-triggers on rebuilds.
class SessionInitializer extends ConsumerStatefulWidget {
  const SessionInitializer({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<SessionInitializer> createState() => _SessionInitializerState();
}

class _SessionInitializerState extends ConsumerState<SessionInitializer> {
  bool _started = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    if (_started) return;
    _started = true;

    // In-app VoIP. Started before FCM so the coordinator is ready to receive
    // the very first call push, including one that launched the app.
    final callCoordinator = ref.read(callCoordinatorProvider);
    await callCoordinator.initialize();
    final devices = ref.read(deviceRegistryProvider);

    final messaging = ref.read(messagingServiceProvider);
    await messaging.initialize(
      localNotifications: ref.read(localNotificationsServiceProvider),
      notificationRepository: ref.read(notificationRepositoryProvider),
      onCallMessage: callCoordinator.handleRemoteMessage,
      onTokenChanged: (token) => devices.registerDevice(fcmToken: token),
    );
    await messaging.handleInitialMessage(
      onCallMessage: callCoordinator.handleRemoteMessage,
    );

    // Cellular call detection — unrelated to VoIP, left exactly as it was.
    final incomingCalls = ref.read(incomingCallServiceProvider);
    await incomingCalls.initialize();
    await incomingCalls.handleInitialCallNotification();

    await ref.read(userProfileServiceProvider).updateLastActiveAt();

    // "Recent Call Logs" is a rolling seven-day window, so anything older is
    // wiped from Firestore once per session. Non-fatal: a failed sweep only
    // means the logs are purged on the next launch, and the feeds bound
    // themselves to the same window regardless.
    try {
      await ref.read(callLogRepositoryProvider).purgeExpiredCallLogs();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

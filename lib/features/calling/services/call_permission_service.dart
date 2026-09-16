import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metadata/features/calling/models/call_exception.dart';
import 'package:permission_handler/permission_handler.dart';

final callPermissionServiceProvider = Provider<CallPermissionService>((ref) {
  return const CallPermissionService();
});

/// Microphone (and, on Android 13+, notification) permission handling for
/// calls.
///
/// Kept out of [WebRTCService] on purpose: `getUserMedia` will happily throw
/// an opaque platform error when permission is missing, and the difference
/// between "denied, ask again" and "permanently denied, only Settings can fix
/// it" is the difference between a retry button and a Settings button.
class CallPermissionService {
  const CallPermissionService();

  Future<bool> hasMicrophonePermission() async {
    return Permission.microphone.isGranted;
  }

  /// Requests everything a call needs, throwing a typed [CallException] the
  /// UI can turn into the right prompt.
  Future<void> ensureCallPermissions() async {
    final status = await Permission.microphone.request();

    if (status.isPermanentlyDenied || status.isRestricted) {
      throw const CallException(CallFailure.microphonePermanentlyDenied);
    }
    if (!status.isGranted) {
      throw const CallException(CallFailure.microphoneDenied);
    }

    // Android 13+ silently drops the full-screen incoming-call notification
    // without this, which would make the app unable to present calls while
    // backgrounded. Not fatal for placing a call, so it is requested but not
    // enforced.
    if (Platform.isAndroid) {
      final notifications = await Permission.notification.status;
      if (notifications.isDenied) {
        await Permission.notification.request();
      }
    }
  }

  /// Opens the OS settings page. Only meaningful after a permanent denial.
  Future<bool> openSettings() => openAppSettings();
}

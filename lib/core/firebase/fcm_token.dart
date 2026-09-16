import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

/// How long to wait for iOS to hand us an APNs token before carrying on
/// without one. Long enough to cover a cold start on a slow network, short
/// enough that a Simulator (which never gets one) isn't held up for long.
const Duration kApnsTokenTimeout = Duration(seconds: 10);

/// The FCM token for this install, or null if it isn't available yet.
///
/// Always prefer this over calling `FirebaseMessaging.getToken()` directly.
///
/// iOS-only hazard: Firebase cannot mint an FCM token until APNs has issued
/// the install a device token, and `getToken()` *throws* `apns-token-not-set`
/// until it has. Callers that let that escape lose whatever work followed it —
/// which on iOS meant messaging initialisation aborting before any `onMessage`
/// listener was attached, and this device never registering to be rung.
/// Android has no equivalent step and never takes this path.
///
/// Null is a normal, recoverable answer rather than a failure: it is what a
/// Simulator and an offline device always return. Callers should subscribe to
/// `onTokenRefresh` first, which delivers the token if APNs completes later.
Future<String?> resolveFcmToken(
  FirebaseMessaging messaging, {

  /// Overrides the host-platform check. Only for tests — `Platform.isIOS` is
  /// always false under `flutter test`, so the iOS path is otherwise
  /// unreachable by the very suite that needs to cover it.
  @visibleForTesting bool? isIOS,
  @visibleForTesting Duration apnsTimeout = kApnsTokenTimeout,
}) async {
  try {
    if ((isIOS ?? Platform.isIOS) &&
        !await _awaitApnsToken(messaging, apnsTimeout)) {
      return null;
    }
    return await messaging.getToken();
  } catch (error) {
    debugPrint('FCM token not available yet: $error');
    return null;
  }
}

/// Polls for the APNs token until it lands or [timeout] passes.
/// firebase_messaging exposes no callback or future for this, so polling is
/// the only option.
Future<bool> _awaitApnsToken(
  FirebaseMessaging messaging,
  Duration timeout,
) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (await messaging.getAPNSToken() != null) return true;
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  debugPrint(
    'APNs token did not arrive within $timeout; push will start working if '
    'and when onTokenRefresh fires.',
  );
  return false;
}

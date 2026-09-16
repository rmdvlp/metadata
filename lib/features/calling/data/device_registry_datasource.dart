import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metadata/core/firebase/firebase_providers.dart';
import 'package:package_info_plus/package_info_plus.dart';

final deviceRegistryProvider = Provider<DeviceRegistryDataSource>((ref) {
  return DeviceRegistryDataSource(
    firestore: ref.watch(firebaseFirestoreProvider),
    auth: ref.watch(firebaseAuthProvider),
  );
});

/// Maintains `users/{uid}/devices/{deviceId}`.
///
/// The existing profile document carries a single `fcmToken`, which is fine
/// for a "you have a new notification" banner but wrong for calling: if a
/// user is signed in on a phone and a tablet, ringing only one of them means
/// half of all calls silently go unanswered. Calls fan out over every
/// registered device, so each install owns its own document.
///
/// `deviceId` is a stable per-install hardware identifier rather than the FCM
/// token, because tokens rotate — keying on the token would leave a dead
/// document behind on every refresh and the backend would keep pushing to it.
class DeviceRegistryDataSource {
  DeviceRegistryDataSource({
    required FirebaseFirestore firestore,
    required FirebaseAuth auth,
  }) : _firestore = firestore,
       _auth = auth;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  String? _cachedDeviceId;

  CollectionReference<Map<String, dynamic>>? get _devices {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return null;
    return _firestore.collection('users').doc(uid).collection('devices');
  }

  Future<String?> deviceId() async {
    if (_cachedDeviceId != null) return _cachedDeviceId;
    final info = DeviceInfoPlugin();
    try {
      if (Platform.isAndroid) {
        _cachedDeviceId = (await info.androidInfo).id;
      } else if (Platform.isIOS) {
        _cachedDeviceId = (await info.iosInfo).identifierForVendor;
      }
    } catch (_) {
      _cachedDeviceId = null;
    }
    return _cachedDeviceId;
  }

  /// Upserts this install's push routing. Called on sign-in, on every FCM
  /// token refresh, and whenever the iOS PushKit token is (re)issued.
  ///
  /// [voipToken] is merged rather than overwritten when null, so an FCM
  /// refresh does not wipe the PushKit token (and vice versa) — losing either
  /// one silently breaks incoming calls on that platform.
  Future<void> registerDevice({
    required String fcmToken,
    String? voipToken,
  }) async {
    final devices = _devices;
    if (devices == null) return;
    final id = await deviceId();
    if (id == null) return;

    String appVersion = 'unknown';
    String? model;
    try {
      appVersion = (await PackageInfo.fromPlatform()).version;
    } catch (_) {
      // Version is diagnostic only — never block registration on it.
    }
    try {
      final info = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final android = await info.androidInfo;
        model = '${android.manufacturer} ${android.model}';
      } else if (Platform.isIOS) {
        model = (await info.iosInfo).utsname.machine;
      }
    } catch (_) {
      // Diagnostic only.
    }

    await devices.doc(id).set({
      'token': fcmToken,
      'voipToken': ?voipToken,
      'platform': Platform.isIOS ? 'ios' : 'android',
      'appVersion': appVersion,
      'deviceModel': model,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Stores the PushKit token on its own, for the case where it arrives
  /// before or independently of an FCM token.
  Future<void> updateVoipToken(String voipToken) async {
    final devices = _devices;
    if (devices == null) return;
    final id = await deviceId();
    if (id == null) return;
    await devices.doc(id).set({
      'voipToken': voipToken,
      'platform': Platform.isIOS ? 'ios' : 'android',
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Removes this install so a signed-out device stops being rung. Failure is
  /// non-fatal — the backend prunes tokens that APNs/FCM reject anyway.
  Future<void> unregisterDevice() async {
    final devices = _devices;
    if (devices == null) return;
    final id = await deviceId();
    if (id == null) return;
    try {
      await devices.doc(id).delete();
    } catch (e) {
      debugPrint('Failed to unregister device: $e');
    }
  }
}

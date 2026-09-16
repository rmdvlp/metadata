import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metadata/core/firebase/fcm_token.dart';
import 'package:metadata/core/firebase/firebase_providers.dart';
import 'package:metadata/core/firebase/local_notifications_service.dart';
import 'package:metadata/core/navigation/app_navigator.dart';
import 'package:metadata/models/user_profile.dart';
import 'package:metadata/repositories/notification_repository.dart';
import 'package:metadata/screens/saved_contact_details_screen.dart';

final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService(ref.watch(firebaseAuthProvider));
});

final analyticsServiceProvider = Provider<AnalyticsService>((ref) {
  return AnalyticsService(ref.watch(firebaseAnalyticsProvider));
});

final userProfileServiceProvider = Provider<UserProfileService>((ref) {
  return UserProfileService(
    firestore: ref.watch(firebaseFirestoreProvider),
    auth: ref.watch(firebaseAuthProvider),
    storageReader: () => ref.read(firebaseStorageProvider),
  );
});

final messagingServiceProvider = Provider<MessagingService>((ref) {
  return MessagingService(
    messaging: ref.watch(firebaseMessagingProvider),
    firestore: ref.watch(firebaseFirestoreProvider),
    auth: ref.watch(firebaseAuthProvider),
  );
});

class AuthService {
  AuthService(this._auth);

  final FirebaseAuth _auth;

  Stream<User?> authStateChanges() => _auth.authStateChanges();

  User? get currentUser => _auth.currentUser;
}

class AnalyticsService {
  AnalyticsService(this._analytics);

  final FirebaseAnalytics _analytics;

  Future<void> logAppOpen() async {
    await _analytics.logAppOpen();
  }
}

class UserProfileService {
  UserProfileService({
    required FirebaseFirestore firestore,
    required FirebaseAuth auth,
    required FirebaseStorage Function() storageReader,
  }) : _firestore = firestore,
       _auth = auth,
       _storageReader = storageReader;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  // Resolved lazily — most profile operations never touch Storage, so this
  // avoids requiring a working FirebaseStorage instance just to read/update
  // profile fields (e.g. in widget tests).
  final FirebaseStorage Function() _storageReader;
  FirebaseStorage get _storage => _storageReader();

  DocumentReference<Map<String, dynamic>>? get _doc {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return null;
    return _firestore.collection('users').doc(uid);
  }

  /// Writes the initial `users/{uid}` doc. Safe to call more than once
  /// (merges), but intended to run only on a brand-new sign-in.
  ///
  /// Prefers the number on the auth record over [phoneNumber]: that is the
  /// canonical E.164 form Firebase itself verified, whereas the caller only
  /// has whatever was typed into the login field.
  Future<void> createInitialProfile({required String phoneNumber}) async {
    final doc = _doc;
    final user = _auth.currentUser;
    if (doc == null || user == null) return;

    final verified = user.phoneNumber;
    final number = (verified != null && verified.isNotEmpty)
        ? verified
        : phoneNumber;

    final snapshot = await doc.get();
    if (snapshot.exists) {
      // An existing doc is left alone except for a missing number. Sign-up
      // is the only place this field was ever written, so a profile created
      // any other way kept an empty one forever — which is what left the
      // number blank under the name on Profile.
      final stored = snapshot.data()?['phoneNumber'] as String? ?? '';
      if (stored.isEmpty && number.isNotEmpty) {
        await doc.set({'phoneNumber': number}, SetOptions(merge: true));
      }
      return;
    }

    await doc.set(
      UserProfile(
        uid: user.uid,
        phoneNumber: number,
        displayName: '',
        permissionsPrompted: false,
        settings: UserSettings.defaults(),
      ).toInitialFirestoreMap(phoneNumber: number),
    );
  }

  /// Records a phone-number change that has *already* been verified against
  /// the auth record. Nothing here verifies anything — that is
  /// [PhoneNumberUpdateService]'s job — this only keeps the profile document
  /// consistent with the account it describes.
  Future<void> updatePhoneNumber(String phoneNumber) async {
    final doc = _doc;
    if (doc == null) return;
    await doc.set({
      'phoneNumber': phoneNumber,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> updateDisplayName(String name) async {
    await _auth.currentUser?.updateDisplayName(name);
    final doc = _doc;
    if (doc == null) return;
    await doc.set({
      'displayName': name,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<String> uploadProfilePhoto(File file) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw StateError('No signed-in user');

    final ref = _storage.ref('users/$uid/profile.jpg');
    // Without an explicit type the object lands as application/octet-stream,
    // which browsers and the Firebase console then refuse to preview.
    await ref.putFile(file, SettableMetadata(contentType: 'image/jpeg'));
    final url = await ref.getDownloadURL();

    final doc = _doc;
    if (doc != null) {
      await doc.set({
        'photoUrl': url,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
    return url;
  }

  /// Clears the profile picture, in Storage and on the document.
  ///
  /// The document is cleared first: if the object delete fails (already
  /// gone, Storage unreachable) the user still gets the outcome they asked
  /// for, and an orphaned object is overwritten by the next upload anyway.
  Future<void> removeProfilePhoto() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw StateError('No signed-in user');

    await _doc?.set({
      'photoUrl': FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    try {
      await _storage.ref('users/$uid/profile.jpg').delete();
    } on FirebaseException catch (e) {
      if (e.code != 'object-not-found') rethrow;
    }
  }

  Stream<UserProfile?> watchProfile() {
    final doc = _doc;
    if (doc == null) return Stream.value(null);
    return doc.snapshots().map(
      (snap) => snap.exists ? UserProfile.fromFirestore(snap) : null,
    );
  }

  Future<void> updateSetting(String key, bool value) async {
    final doc = _doc;
    if (doc == null) return;
    await doc.set({
      'settings': {key: value},
    }, SetOptions(merge: true));
  }

  Future<void> markPermissionsPrompted() async {
    final doc = _doc;
    if (doc == null) return;
    await doc.set({'permissionsPrompted': true}, SetOptions(merge: true));
  }

  Future<void> updateLastActiveAt() async {
    final doc = _doc;
    if (doc == null) return;
    await doc.set({
      'lastActiveAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}

class MessagingService {
  MessagingService({
    required FirebaseMessaging messaging,
    required FirebaseFirestore firestore,
    required FirebaseAuth auth,
  }) : _messaging = messaging,
       _firestore = firestore,
       _auth = auth;

  final FirebaseMessaging _messaging;
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  bool _initialized = false;

  /// Data-message types that belong to the in-app VoIP feature. They must not
  /// produce an ordinary notification banner or a `notifications` document —
  /// an incoming call is presented by CallKit / a full-screen intent, and a
  /// stray "You have a notification" banner alongside a ringing call reads as
  /// a bug.
  static const Set<String> _callMessageTypes = {'incoming_call', 'call_ended'};

  static bool isCallMessage(RemoteMessage message) =>
      _callMessageTypes.contains(message.data['type']);

  Future<void> initialize({
    required LocalNotificationsService localNotifications,
    required NotificationRepository notificationRepository,
    Future<void> Function(RemoteMessage message)? onCallMessage,
    Future<void> Function(String token)? onTokenChanged,
  }) async {
    if (_initialized) return;
    _initialized = true;

    await _requestPermissionsIfNeeded();
    await localNotifications.initialize();

    // Subscribed before the first fetch, not after: on iOS the initial
    // `getToken()` can legitimately come back empty while APNs is still
    // registering, and the token then arrives here instead. Attaching this
    // afterwards would drop that first token on the floor.
    _messaging.onTokenRefresh.listen((String token) async {
      await _storeToken(token);
      await onTokenChanged?.call(token);
    });

    await _syncFcmToken(onTokenChanged);

    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      // Single onMessage subscription for the whole app: call payloads are
      // routed to the calling feature, everything else keeps its existing
      // behaviour untouched.
      if (isCallMessage(message)) {
        await onCallMessage?.call(message);
        return;
      }
      await localNotifications.showRemoteMessage(message);
      await notificationRepository.createFromRemoteMessage(message);
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) async {
      if (isCallMessage(message)) {
        await onCallMessage?.call(message);
        return;
      }
      _openContactFromMessage(message);
    });
  }

  /// Checks whether the app was opened from a terminated state by tapping a
  /// notification; call once at cold start after the root navigator exists.
  Future<void> handleInitialMessage({
    Future<void> Function(RemoteMessage message)? onCallMessage,
  }) async {
    final message = await _messaging.getInitialMessage();
    if (message == null) return;
    if (isCallMessage(message)) {
      await onCallMessage?.call(message);
      return;
    }
    _openContactFromMessage(message);
  }

  void _openContactFromMessage(RemoteMessage message) {
    final contactId = message.data['contactId'] as String?;
    if (contactId == null) return;
    final navigator = rootNavigatorKey.currentState;
    if (navigator == null) return;
    navigator.push(
      MaterialPageRoute(
        builder: (_) => SavedContactDetailsScreen(contactId: contactId),
      ),
    );
  }

  Future<void> _requestPermissionsIfNeeded() async {
    if (kIsWeb) return;

    final NotificationSettings settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    debugPrint('FCM permission status: ${settings.authorizationStatus}');
  }

  Future<void> _syncFcmToken(
    Future<void> Function(String token)? onTokenChanged,
  ) async {
    final String? token = await resolveFcmToken(_messaging);
    if (token == null) return;
    await _storeToken(token);
    await onTokenChanged?.call(token);
  }

  Future<void> _storeToken(String token) async {
    final String? uid = _auth.currentUser?.uid;
    if (uid == null) return;

    await _firestore.collection('users').doc(uid).set({
      'fcmToken': token,
    }, SetOptions(merge: true));
  }
}

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metadata/core/firebase/firebase_services.dart';
import 'package:metadata/firebase_options.dart';

/// Whether to bypass Firebase's phone-number app verification. Only works
/// with the fictional test numbers configured in the Firebase console — real
/// numbers get no SMS while this is on. See the use site below.
const bool useFirebasePhoneTestNumbers = bool.fromEnvironment(
  'USE_FIREBASE_PHONE_TEST_NUMBERS',
);

final appBootstrapProvider = FutureProvider<void>((ref) async {
  // Initialize Firebase
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Disabling app verification lets verifyPhoneNumber() run on an iOS
  // simulator (where no APNs token exists) without the native SDK assertion
  // crash — but Firebase only honours it for the *fictional* numbers
  // registered under Authentication > Sign-in method > Phone > "Phone numbers
  // for testing". With it on, a real phone number never receives an SMS on
  // either platform, which is why this is opt-in rather than "any debug
  // build": normal `flutter run` testing uses real numbers.
  //
  // Flip it on for a simulator run with:
  //   flutter run --dart-define=USE_FIREBASE_PHONE_TEST_NUMBERS=true
  if (kDebugMode && useFirebasePhoneTestNumbers) {
    await FirebaseAuth.instance.setSettings(
      appVerificationDisabledForTesting: true,
    );
  }

  // Log app open (anonymous analytics) — fire-and-forget so an analytics
  // failure (e.g. no network) can never block the app from booting.
  unawaited(
    ref.read(analyticsServiceProvider).logAppOpen().catchError((_, _) {}),
  );

  // NOTE: User-specific services (FCM, profile updates) are initialized
  // after successful authentication, not here during app bootstrap
});

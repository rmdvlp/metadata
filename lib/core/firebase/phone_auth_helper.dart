import 'package:firebase_auth/firebase_auth.dart';

typedef OnCodeSent = void Function(String verificationId, int? resendToken);
typedef OnAutoVerified = void Function(PhoneAuthCredential credential);
typedef OnVerificationFailed = void Function(FirebaseAuthException e);

/// Shared `verifyPhoneNumber` boilerplate used by both the initial login
/// screen and the OTP screen's "Resend code" action (via
/// [forceResendingToken]).
///
/// [phoneNumber] must already be E.164 — Firebase texts the code to exactly
/// this string. See `toE164` in `utils/phone_number.dart`.
///
/// [auth] exists so callers holding an injected instance (and tests) do not
/// have to go through the `FirebaseAuth.instance` singleton.
Future<void> requestOtp({
  required String phoneNumber,
  int? forceResendingToken,
  required OnCodeSent onCodeSent,
  required OnVerificationFailed onError,
  required OnAutoVerified onAutoVerified,
  FirebaseAuth? auth,
}) {
  return (auth ?? FirebaseAuth.instance).verifyPhoneNumber(
    phoneNumber: phoneNumber,
    forceResendingToken: forceResendingToken,
    timeout: const Duration(seconds: 60),
    verificationCompleted: onAutoVerified,
    verificationFailed: onError,
    codeSent: onCodeSent,
    codeAutoRetrievalTimeout: (_) {},
  );
}

/// Turns a phone-auth failure into something both the user and whoever is
/// debugging the build can act on.
///
/// The default `e.message` is often null or unhelpfully generic ("Verification
/// failed"), which hides the difference between a mistyped number and a
/// Firebase project that has no SHA-1 registered. The `code` is always
/// appended for that reason.
String phoneAuthErrorMessage(FirebaseAuthException e) {
  final String explanation = switch (e.code) {
    'invalid-phone-number' =>
      'That phone number is not valid. Include the country code.',
    'missing-client-identifier' ||
    'app-not-authorized' ||
    'invalid-app-credential' =>
      'This build is not authorized for phone sign-in. On Android, add the '
          "app's SHA-1 and SHA-256 fingerprints in Firebase console > Project "
          'settings and re-download google-services.json. On iOS, upload the '
          'APNs key and add the REVERSED_CLIENT_ID URL scheme.',
    'operation-not-allowed' =>
      'Phone sign-in is not enabled for this Firebase project. Enable it '
          'under Authentication > Sign-in method > Phone.',
    'too-many-requests' || 'quota-exceeded' =>
      'Too many attempts from this device or number. Wait a while, or add '
          'this number as a test number in the Firebase console.',
    'invalid-verification-code' => 'That code is incorrect. Please re-check it.',
    'session-expired' =>
      'That code has expired. Request a new one.',
    'network-request-failed' =>
      'Network error. Check your connection and try again.',
    _ => e.message ?? 'Verification failed',
  };
  return '$explanation (${e.code})';
}

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metadata/core/firebase/firebase_providers.dart';
import 'package:metadata/core/firebase/firebase_services.dart';
import 'package:metadata/core/firebase/phone_auth_helper.dart';

final phoneNumberUpdateServiceProvider = Provider<PhoneNumberUpdateService>((
  ref,
) {
  return PhoneNumberUpdateService(
    auth: ref.watch(firebaseAuthProvider),
    profiles: ref.watch(userProfileServiceProvider),
  );
});

/// What came back from asking Firebase to text a verification code.
sealed class PhoneVerificationOutcome {
  const PhoneVerificationOutcome();
}

/// The usual path: a code is on its way and the user has to type it in.
class CodeSent extends PhoneVerificationOutcome {
  const CodeSent({required this.verificationId, this.resendToken});

  final String verificationId;
  final int? resendToken;
}

/// Android instant verification — the platform proved the number owns the
/// device without an SMS, and hands back a usable credential directly. When
/// this happens there is no code to type and no `codeSent` callback at all,
/// so a flow that only handles [CodeSent] hangs forever on this device.
class AutoVerified extends PhoneVerificationOutcome {
  const AutoVerified(this.credential);

  final PhoneAuthCredential credential;
}

/// Changing the number the account itself is identified by.
///
/// This is deliberately not part of [UserProfileService]: the profile
/// document is a description of the account, and writing a new number there
/// without moving the auth record would leave the app claiming a number the
/// user cannot actually sign in with. Both move together here, auth first.
class PhoneNumberUpdateService {
  PhoneNumberUpdateService({
    required FirebaseAuth auth,
    required UserProfileService profiles,
  }) : _auth = auth,
       _profiles = profiles;

  final FirebaseAuth _auth;
  final UserProfileService _profiles;

  String? get currentPhoneNumber => _auth.currentUser?.phoneNumber;

  /// Texts a verification code to [phoneNumber], which must be E.164.
  ///
  /// `verifyPhoneNumber` reports through callbacks and its own Future can
  /// resolve without any of them ever firing, so the result is raced against
  /// [timeout] rather than awaited directly — otherwise a silently stalled
  /// request leaves the caller's spinner up forever.
  Future<PhoneVerificationOutcome> sendVerificationCode({
    required String phoneNumber,
    int? resendToken,
    Duration timeout = const Duration(seconds: 30),
  }) {
    final completer = Completer<PhoneVerificationOutcome>();

    void settle(PhoneVerificationOutcome outcome) {
      if (!completer.isCompleted) completer.complete(outcome);
    }

    void fail(Object error) {
      if (!completer.isCompleted) completer.completeError(error);
    }

    requestOtp(
      auth: _auth,
      phoneNumber: phoneNumber,
      forceResendingToken: resendToken,
      onCodeSent: (verificationId, token) => settle(
        CodeSent(verificationId: verificationId, resendToken: token),
      ),
      onAutoVerified: (credential) => settle(AutoVerified(credential)),
      onError: fail,
    ).catchError(fail);

    return completer.future.timeout(
      timeout,
      onTimeout: () => throw TimeoutException(
        'No response from Firebase while sending the code',
      ),
    );
  }

  /// Applies a code the user typed. [verificationId] comes from [CodeSent].
  Future<void> confirmCode({
    required String verificationId,
    required String smsCode,
  }) {
    return applyCredential(
      PhoneAuthProvider.credential(
        verificationId: verificationId,
        smsCode: smsCode,
      ),
    );
  }

  /// Moves the account onto the verified number, then the profile document.
  ///
  /// Order matters: auth is the thing that can reject the change (the number
  /// belongs to another account, the session is too old to re-key), and a
  /// profile updated ahead of a rejected auth change would show a number the
  /// user cannot sign in with.
  Future<void> applyCredential(PhoneAuthCredential credential) async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('No signed-in user');

    await user.updatePhoneNumber(credential);
    await user.reload();

    final updated = _auth.currentUser?.phoneNumber;
    if (updated != null && updated.isNotEmpty) {
      await _profiles.updatePhoneNumber(updated);
    }
  }
}

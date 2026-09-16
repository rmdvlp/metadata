import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metadata/core/bootstrap/auth_gate.dart';
import 'package:metadata/core/firebase/firebase_services.dart';
import 'package:metadata/core/firebase/phone_auth_helper.dart';
import 'package:metadata/core/loading/app_loading.dart';
import 'package:metadata/utils/app_colors.dart';
import 'package:metadata/utils/app_images.dart';
import 'package:metadata/widgets/auth_shell.dart';
import 'package:metadata/widgets/button.dart';
import 'package:metadata/widgets/otp_pin_field.dart';

class OtpScreen extends ConsumerStatefulWidget {
  const OtpScreen({
    super.key,
    required this.phoneNumber,
    required this.verificationId,
    this.resendToken,
  });

  final String phoneNumber;
  final String verificationId;
  final int? resendToken;

  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen> {
  static const _resendWindow = 30;

  final TextEditingController _pinController = TextEditingController();
  final FocusNode _pinFocusNode = FocusNode();

  bool _isVerifying = false;
  bool _isResending = false;
  String? _errorMessage;

  late String _verificationId = widget.verificationId;
  int? _resendToken;
  int _secondsRemaining = _resendWindow;
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    _resendToken = widget.resendToken;
    _startCountdown();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _pinController.dispose();
    _pinFocusNode.dispose();
    super.dispose();
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    setState(() => _secondsRemaining = _resendWindow);
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_secondsRemaining <= 1) {
        timer.cancel();
        setState(() => _secondsRemaining = 0);
        return;
      }
      setState(() => _secondsRemaining -= 1);
    });
  }

  bool get _isOtpComplete => _pinController.text.trim().length == 6;

  Future<void> _resendOtp() async {
    setState(() {
      _isResending = true;
      _errorMessage = null;
    });

    // Same hang risk as login_screen's _sendOtp: verifyPhoneNumber()'s
    // returned Future can resolve without any callback ever firing.
    final completer = Completer<void>();

    AppLoading.show();
    try {
      await requestOtp(
        phoneNumber: widget.phoneNumber,
        forceResendingToken: _resendToken,
        onAutoVerified: (PhoneAuthCredential credential) {
          if (!completer.isCompleted) completer.complete();
          _signInWithCredential(credential);
        },
        onError: (FirebaseAuthException e) {
          if (!completer.isCompleted) completer.complete();
          if (!mounted) return;
          setState(() {
            _isResending = false;
            _errorMessage = phoneAuthErrorMessage(e);
          });
        },
        onCodeSent: (String verificationId, int? resendToken) {
          if (!completer.isCompleted) completer.complete();
          if (!mounted) return;
          _pinController.clear();
          setState(() {
            _verificationId = verificationId;
            _resendToken = resendToken;
            _isResending = false;
          });
          _startCountdown();
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('A new code was sent.')));
        },
      );

      await completer.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          if (!mounted) return;
          setState(() {
            _isResending = false;
            _errorMessage = 'This is taking too long. Please try again.';
          });
        },
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _isResending = false;
        _errorMessage = phoneAuthErrorMessage(e);
      });
    } finally {
      AppLoading.dismiss();
    }
  }

  Future<void> _verifyOtp() async {
    final otp = _pinController.text.trim();

    setState(() {
      _isVerifying = true;
      _errorMessage = null;
    });

    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: _verificationId,
        smsCode: otp,
      );

      await _signInWithCredential(credential);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _isVerifying = false;
        _errorMessage = phoneAuthErrorMessage(e);
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(phoneAuthErrorMessage(e))));
    } catch (e) {
      // Catch-all on purpose. `_isVerifying` gates the pin field's `enabled`
      // and the button's `onPressed`, so anything that escapes here leaves the
      // screen permanently frozen on "Verifying..." with no way to retype the
      // code — a far worse failure than showing an ugly error.
      if (!mounted) return;
      setState(() {
        _isVerifying = false;
        _errorMessage = 'Something went wrong while verifying: $e';
      });
    }
  }

  Future<void> _signInWithCredential(PhoneAuthCredential credential) async {
    AppLoading.show();
    try {
      final userCredential = await FirebaseAuth.instance
          .signInWithCredential(credential)
          .timeout(const Duration(seconds: 20));

      // Run for every sign-in, not just the first: the call is a no-op on an
      // existing profile except for backfilling a missing number, and the
      // number is what Profile shows under the user's name.
      //
      // The account's own phoneNumber is preferred over what was typed —
      // Firebase has canonicalised it by now.
      //
      // Deliberately best-effort: the credential is consumed by the
      // signInWithCredential above, so once that succeeds the user IS signed
      // in and there is no way back — sending them to the error state here
      // would strand them on a screen whose OTP can never be accepted again.
      // AuthGate re-reads the profile and routes from real state, so a failed
      // write costs at most a missing phone number on the profile document.
      try {
        await ref
            .read(userProfileServiceProvider)
            .createInitialProfile(
              phoneNumber:
                  userCredential.user?.phoneNumber ?? widget.phoneNumber,
            )
            .timeout(const Duration(seconds: 20));
      } on Exception catch (e) {
        debugPrint('Could not write the initial user profile: $e');
      }

      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => const AuthGate()),
        (route) => false,
      );
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _isVerifying = false;
        _errorMessage =
            'This is taking too long. Please check your connection and try again.';
      });
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _isVerifying = false;
        _errorMessage = phoneAuthErrorMessage(e);
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(phoneAuthErrorMessage(e))));
    } on FirebaseException catch (e) {
      // Firestore/Storage rather than Auth — most commonly `permission-denied`
      // because firestore.rules has not been deployed to the project.
      if (!mounted) return;
      setState(() {
        _isVerifying = false;
        _errorMessage = 'Signed in, but your profile could not be loaded: '
            '${e.message ?? e.code} (${e.code})';
      });
    } finally {
      AppLoading.dismiss();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthShell(
      illustrationAsset: AppImages.otp,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Center(
            child: const Text(
              'Enter Your OTP',
              style: TextStyle(
                fontFamily: 'SF Pro Display',
                fontSize: 24,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Center(
            child: Text(
              'Enter the code that we sent to ${widget.phoneNumber.isEmpty ? 'your mobile number' : widget.phoneNumber}',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'SF Pro Display',
                fontSize: 13,
                fontWeight: FontWeight.w400,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(height: 28),
          Center(
            child: OtpPinField(
              controller: _pinController,
              focusNode: _pinFocusNode,
              enabled: !_isVerifying,
              onChanged: (_) => setState(() {}),
              onCompleted: (_) {
                if (!_isVerifying) _verifyOtp();
              },
            ),
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 12),
            Text(
              _errorMessage!,
              style: const TextStyle(
                fontFamily: 'SF Pro Display',
                fontSize: 12,
                fontWeight: FontWeight.w400,
                color: Colors.redAccent,
              ),
            ),
          ],
          const SizedBox(height: 28),
          CustomButton(
            label: _isVerifying ? 'Verifying...' : 'Verify OTP',
            onPressed: _isOtpComplete && !_isVerifying ? _verifyOtp : null,
          ),
          const SizedBox(height: 18),
          Center(
            child: _secondsRemaining > 0
                ? Text(
                    'Resend code in 00:${_secondsRemaining.toString().padLeft(2, '0')}',
                    style: const TextStyle(
                      fontFamily: 'SF Pro Display',
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  )
                : TextButton(
                    onPressed: _isResending ? null : _resendOtp,
                    child: Text(
                      _isResending ? 'Resending...' : 'Resend code',
                      style: const TextStyle(
                        fontFamily: 'SF Pro Display',
                        color: AppColors.primaryBlue,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

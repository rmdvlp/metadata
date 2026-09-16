import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metadata/repositories/phone_number_update_service.dart';
import 'package:metadata/utils/app_colors.dart';
import 'package:metadata/utils/phone_number.dart';
import 'package:metadata/widgets/app_back_button.dart';
import 'package:metadata/widgets/button.dart';
import 'package:metadata/widgets/otp_pin_field.dart';
import 'package:metadata/widgets/phone_input_row.dart';

/// Changes the number the account itself signs in with.
///
/// The number is account identity, so it is not editable the way a name is:
/// the new one has to prove it belongs to the user first, by receiving a
/// code. Two steps in one screen — enter the number, then the code Firebase
/// texted to *that* number.
///
/// Pops `true` once the change has landed on both the auth record and the
/// profile document.
class ChangePhoneNumberScreen extends ConsumerStatefulWidget {
  const ChangePhoneNumberScreen({super.key, this.currentPhoneNumber});

  /// Shown for reference so the user can see what they are replacing.
  final String? currentPhoneNumber;

  @override
  ConsumerState<ChangePhoneNumberScreen> createState() =>
      _ChangePhoneNumberScreenState();
}

enum _Step { enterNumber, enterCode }

class _ChangePhoneNumberScreenState
    extends ConsumerState<ChangePhoneNumberScreen> {
  static const int _resendWindow = 30;

  final TextEditingController _numberController = TextEditingController();
  final TextEditingController _codeController = TextEditingController();

  String _dialCode = '+1';
  _Step _step = _Step.enterNumber;

  /// The E.164 number the code was actually sent to — shown verbatim on the
  /// code step so the user can catch a wrong number before waiting on an SMS
  /// that is never going to arrive.
  String _sentTo = '';
  String _verificationId = '';
  int? _resendToken;

  bool _isBusy = false;
  String? _errorMessage;

  int _secondsRemaining = 0;
  Timer? _countdownTimer;

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _numberController.dispose();
    _codeController.dispose();
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

  Future<void> _sendCode({bool resend = false}) async {
    final typed = _numberController.text.trim();
    if (typed.isEmpty) {
      setState(() => _errorMessage = 'Please enter a mobile number');
      return;
    }

    // The code goes to exactly this string, so it has to be real E.164.
    final e164 = toE164(typed, dialCode: _dialCode);
    if (e164 == null) {
      setState(
        () => _errorMessage =
            'That does not look like a valid phone number. Enter it without '
            'the leading 0, or in full as $_dialCode...',
      );
      return;
    }
    if (e164 == widget.currentPhoneNumber) {
      setState(
        () => _errorMessage = 'That is already the number on your account.',
      );
      return;
    }

    setState(() {
      _isBusy = true;
      _errorMessage = null;
    });

    final service = ref.read(phoneNumberUpdateServiceProvider);
    try {
      final outcome = await service.sendVerificationCode(
        phoneNumber: e164,
        resendToken: resend ? _resendToken : null,
      );
      if (!mounted) return;

      switch (outcome) {
        case CodeSent(:final verificationId, :final resendToken):
          setState(() {
            _isBusy = false;
            _sentTo = e164;
            _verificationId = verificationId;
            _resendToken = resendToken;
            _step = _Step.enterCode;
            _codeController.clear();
          });
          _startCountdown();
          if (resend) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('A new code was sent.')),
            );
          }
        case AutoVerified(:final credential):
          // No SMS to type on this device — apply it straight away.
          _sentTo = e164;
          await _apply(() => service.applyCredential(credential));
      }
    } on TimeoutException {
      _fail('This is taking too long. Check your connection and try again.');
    } on FirebaseAuthException catch (e) {
      _fail(_messageFor(e));
    } catch (e) {
      _fail('Could not send the code: $e');
    }
  }

  Future<void> _verifyCode() async {
    final code = _codeController.text.trim();
    if (code.length != OtpPinField.length) return;

    setState(() {
      _isBusy = true;
      _errorMessage = null;
    });

    final service = ref.read(phoneNumberUpdateServiceProvider);
    await _apply(
      () => service.confirmCode(
        verificationId: _verificationId,
        smsCode: code,
      ),
    );
  }

  /// Runs the step that actually re-keys the account, and reports the one
  /// outcome the user cares about either way.
  Future<void> _apply(Future<void> Function() change) async {
    // Captured before the await: after the pop below this State's context is
    // defunct, and looking either of them up through it then throws.
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final number = _sentTo;
    try {
      await change().timeout(const Duration(seconds: 25));
      if (!mounted) return;
      navigator.pop(true);
      messenger.showSnackBar(
        SnackBar(content: Text('Your number is now $number.')),
      );
    } on TimeoutException {
      _fail('This is taking too long. Check your connection and try again.');
    } on FirebaseAuthException catch (e) {
      _fail(_messageFor(e));
    } catch (e) {
      _fail('Could not update your number: $e');
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _isBusy = false;
      _errorMessage = message;
    });
  }

  /// Firebase's own messages for these are either absent or unhelpfully
  /// technical, and each one has a different thing the user should do next.
  String _messageFor(FirebaseAuthException e) {
    return switch (e.code) {
      'invalid-phone-number' =>
        'Firebase rejected that number. Check the country code and try again.',
      'invalid-verification-code' =>
        'That code is not right. Check it and try again.',
      'session-expired' || 'code-expired' =>
        'That code has expired. Send a new one.',
      'credential-already-in-use' || 'account-exists-with-different-credential' =>
        'That number is already used by another account.',
      'requires-recent-login' =>
        'For your security, sign out and sign back in before changing your '
            'number.',
      'too-many-requests' =>
        'Too many attempts. Wait a few minutes and try again.',
      _ => e.message ?? 'Could not update your number (${e.code}).',
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        elevation: 0,
        leadingWidth: AppBackButton.leadingWidth,
        leading: const AppBackButton.appBar(),
        title: const Text(
          'Change Phone Number',
          style: TextStyle(
            fontFamily: 'SF Pro Display',
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            if (_step == _Step.enterNumber)
              ..._numberStep()
            else
              ..._codeStep(),
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                style: const TextStyle(
                  fontFamily: 'SF Pro Display',
                  fontSize: 12,
                  color: Colors.redAccent,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _numberStep() {
    final current = widget.currentPhoneNumber;
    return [
      Text(
        current == null || current.isEmpty
            ? 'Enter the number you want to use for this account.'
            : 'Your account currently uses $current. Enter the number you '
                  'want to use instead.',
        style: const TextStyle(
          fontFamily: 'SF Pro Display',
          fontSize: 13,
          color: AppColors.textSecondary,
        ),
      ),
      const SizedBox(height: 20),
      const Text(
        'New Phone Number',
        style: TextStyle(
          fontFamily: 'SF Pro Display',
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
      ),
      const SizedBox(height: 10),
      PhoneInputRow(
        controller: _numberController,
        onCountryCodeChanged: (code) => _dialCode = code,
      ),
      const SizedBox(height: 12),
      const Text(
        "We'll text a 6-digit code to that number to confirm it is yours.",
        style: TextStyle(
          fontFamily: 'SF Pro Display',
          fontSize: 12,
          color: AppColors.textSecondary,
        ),
      ),
      const SizedBox(height: 24),
      CustomButton(
        label: _isBusy ? 'Sending code...' : 'Send Code',
        onPressed: _isBusy ? null : () => _sendCode(),
      ),
    ];
  }

  List<Widget> _codeStep() {
    final complete = _codeController.text.trim().length == OtpPinField.length;
    return [
      Text(
        'Enter the code we sent to $_sentTo',
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontFamily: 'SF Pro Display',
          fontSize: 13,
          color: AppColors.textSecondary,
        ),
      ),
      const SizedBox(height: 24),
      Center(
        child: OtpPinField(
          controller: _codeController,
          enabled: !_isBusy,
          onChanged: (_) => setState(() {}),
          onCompleted: (_) {
            if (!_isBusy) _verifyCode();
          },
        ),
      ),
      const SizedBox(height: 24),
      CustomButton(
        label: _isBusy ? 'Verifying...' : 'Confirm New Number',
        onPressed: complete && !_isBusy ? _verifyCode : null,
      ),
      const SizedBox(height: 12),
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
                onPressed: _isBusy ? null : () => _sendCode(resend: true),
                child: const Text(
                  'Resend code',
                  style: TextStyle(
                    fontFamily: 'SF Pro Display',
                    color: AppColors.primaryBlue,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
      ),
      const SizedBox(height: 4),
      Center(
        child: TextButton(
          onPressed: _isBusy
              ? null
              : () => setState(() {
                  _step = _Step.enterNumber;
                  _errorMessage = null;
                }),
          child: const Text(
            'Use a different number',
            style: TextStyle(
              fontFamily: 'SF Pro Display',
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    ];
  }
}

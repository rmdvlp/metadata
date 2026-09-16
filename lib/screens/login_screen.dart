import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:metadata/core/bootstrap/auth_gate.dart';
import 'package:metadata/core/firebase/phone_auth_helper.dart';
import 'package:metadata/core/loading/app_loading.dart';
import 'package:metadata/screens/otp_screen.dart';
import 'package:metadata/utils/app_colors.dart';
import 'package:metadata/utils/app_images.dart';
import 'package:metadata/utils/phone_number.dart';
import 'package:metadata/widgets/auth_shell.dart';
import 'package:metadata/widgets/button.dart';
import 'package:metadata/widgets/phone_input_row.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _mobileController = TextEditingController();
  String _selectedCountryCode = '+1';
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _mobileController.dispose();
    super.dispose();
  }

  Future<void> _sendOtp() async {
    final phoneNumber = _mobileController.text.trim();
    if (phoneNumber.isEmpty) {
      setState(() => _errorMessage = 'Please enter a mobile number');
      return;
    }

    // Firebase texts the code to exactly this string, so it has to be real
    // E.164 — gluing the dial code onto whatever was typed would send
    // "0300 1234567" to +920300… , a number that is not the user's.
    final fullPhoneNumber = toE164(phoneNumber, dialCode: _selectedCountryCode);
    if (fullPhoneNumber == null) {
      setState(
        () => _errorMessage =
            'That does not look like a valid phone number. Enter it without '
            'the leading 0, or in full as $_selectedCountryCode...',
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    // verifyPhoneNumber()'s returned Future can resolve without any of its
    // callbacks ever firing (e.g. the request silently stalls server-side),
    // which would otherwise leave _isLoading stuck true forever. Race the
    // callback chain against a hard client-side timeout so the UI can
    // always recover with a clear error.
    final completer = Completer<void>();

    AppLoading.show();
    try {
      await requestOtp(
        phoneNumber: fullPhoneNumber,
        onAutoVerified: (PhoneAuthCredential credential) {
          if (!completer.isCompleted) completer.complete();
          // Auto-sign in if SMS auto-retrieval succeeds
          _signInWithCredential(credential);
        },
        onError: (FirebaseAuthException e) {
          if (!completer.isCompleted) completer.complete();
          if (!mounted) return;
          setState(() {
            _isLoading = false;
            _errorMessage = phoneAuthErrorMessage(e);
          });
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(phoneAuthErrorMessage(e))));
        },
        onCodeSent: (String verificationId, int? resendToken) {
          if (!completer.isCompleted) completer.complete();
          if (mounted) {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => OtpScreen(
                  phoneNumber: fullPhoneNumber,
                  verificationId: verificationId,
                  resendToken: resendToken,
                ),
              ),
            );
            setState(() => _isLoading = false);
          }
        },
      );

      await completer.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          if (!mounted) return;
          setState(() {
            _isLoading = false;
            _errorMessage =
                'This is taking too long. Check your network connection and '
                'Firebase phone-auth setup, then try again.';
          });
        },
      );
    } on FirebaseAuthException catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = phoneAuthErrorMessage(e);
      });
    } finally {
      AppLoading.dismiss();
    }
  }

  Future<void> _signInWithCredential(PhoneAuthCredential credential) async {
    AppLoading.show();
    try {
      await FirebaseAuth.instance.signInWithCredential(credential);
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => const AuthGate()),
        (route) => false,
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = phoneAuthErrorMessage(e));
    } finally {
      AppLoading.dismiss();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthShell(
      illustrationAsset: AppImages.welcome,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Center(
            child: const Text(
              'Welcome to Context-ID',
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
            child: const Text(
              'Context-ID where connections come alive',
              style: TextStyle(
                fontFamily: 'SF Pro Display',
                fontSize: 13,
                fontWeight: FontWeight.w400,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(height: 28),
          // The surrounding Column centers its children; without this the
          // label centers along with them instead of sitting above the
          // left-aligned phone field like a form label should.
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Phone Number',
              style: TextStyle(
                fontFamily: 'SF Pro Display',
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          const SizedBox(height: 10),
          PhoneInputRow(
            controller: _mobileController,
            onCountryCodeChanged: (countryCode) {
              _selectedCountryCode = countryCode;
            },
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
          const SizedBox(height: 24),
          CustomButton(
            label: _isLoading ? 'Sending OTP...' : 'Get OTP',
            onPressed: _isLoading ? null : _sendOtp,
          ),
        ],
      ),
    );
  }
}

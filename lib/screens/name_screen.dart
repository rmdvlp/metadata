import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metadata/core/bootstrap/auth_gate.dart';
import 'package:metadata/core/firebase/firebase_services.dart';
import 'package:metadata/core/loading/app_loading.dart';
import 'package:metadata/utils/app_colors.dart';
import 'package:metadata/utils/app_images.dart';
import 'package:metadata/widgets/auth_shell.dart';
import 'package:metadata/widgets/button.dart';

class NameScreen extends ConsumerStatefulWidget {
  const NameScreen({super.key});

  @override
  ConsumerState<NameScreen> createState() => _NameScreenState();
}

class _NameScreenState extends ConsumerState<NameScreen> {
  final TextEditingController _nameController = TextEditingController();
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  bool get _isNameValid {
    return _nameController.text.trim().isNotEmpty;
  }

  Future<void> _onContinue() async {
    if (!_isNameValid || _isSaving) return;
    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    AppLoading.show();
    try {
      await ref
          .read(userProfileServiceProvider)
          .updateDisplayName(_nameController.text.trim())
          .timeout(const Duration(seconds: 20));

      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => const AuthGate()),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _errorMessage = e is TimeoutException
            ? 'This is taking too long. Check your connection and try again.'
            : 'Could not save your name: $e';
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_errorMessage!)));
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
              'Your Name',
              style: TextStyle(
                fontFamily: 'SF Pro Display',
                fontSize: 24,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          const SizedBox(height: 10),
          const Center(
            child: Text(
              'Enter your full name',
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
          TextField(
            controller: _nameController,
            textInputAction: TextInputAction.done,
            keyboardType: TextInputType.name,
            style: const TextStyle(
              fontFamily: 'SF Pro Display',
              fontSize: 16,
              fontWeight: FontWeight.w400,
              color: AppColors.textPrimary,
            ),
            decoration: InputDecoration(
              hintText: 'Enter your full name',
              hintStyle: TextStyle(
                fontFamily: 'SF Pro Display',
                fontSize: 16,
                fontWeight: FontWeight.w400,
                color: AppColors.textSecondary,
              ),
              filled: true,
              fillColor: AppColors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: AppColors.primaryBlue),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
            ),
            onChanged: (_) {
              setState(() {});
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
          const SizedBox(height: 28),
          CustomButton(
            label: _isSaving ? 'Saving...' : 'Continue',
            onPressed: _isNameValid && !_isSaving ? _onContinue : null,
            enabled: _isNameValid && !_isSaving,
          ),
        ],
      ),
    );
  }
}

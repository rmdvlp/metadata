import 'package:flutter/material.dart';
import 'package:metadata/utils/app_colors.dart';
import 'package:pinput/pinput.dart';

/// The six-box SMS code field. Shared by sign-in and by changing the
/// account's own number, so the two never drift into looking like different
/// products.
class OtpPinField extends StatelessWidget {
  const OtpPinField({
    super.key,
    required this.controller,
    this.focusNode,
    this.enabled = true,
    this.autofocus = true,
    this.onChanged,
    this.onCompleted,
  });

  static const int length = 6;

  final TextEditingController controller;
  final FocusNode? focusNode;
  final bool enabled;
  final bool autofocus;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onCompleted;

  static PinTheme _theme({Border? border}) => PinTheme(
    width: 44,
    height: 56,
    textStyle: const TextStyle(
      fontFamily: 'SF Pro Display',
      fontSize: 18,
      fontWeight: FontWeight.w700,
      color: AppColors.textPrimary,
    ),
    decoration: BoxDecoration(
      color: AppColors.white,
      borderRadius: BorderRadius.circular(14),
      border: border ?? Border.all(color: AppColors.border),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Pinput(
      length: length,
      controller: controller,
      focusNode: focusNode,
      autofocus: autofocus,
      enabled: enabled,
      keyboardType: TextInputType.number,
      defaultPinTheme: _theme(),
      focusedPinTheme: _theme(
        border: Border.all(color: AppColors.primaryBlue, width: 1.5),
      ),
      submittedPinTheme: _theme(
        border: Border.all(color: AppColors.primaryBlue),
      ),
      separatorBuilder: (index) => const SizedBox(width: 8),
      onChanged: onChanged,
      onCompleted: onCompleted,
    );
  }
}

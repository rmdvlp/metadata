import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metadata/models/contact_model.dart';
import 'package:metadata/repositories/call_flow_helper.dart';
import 'package:metadata/repositories/contact_repository.dart';
import 'package:metadata/utils/app_colors.dart';

const List<String> _kKeypadDigits = [
  '1', '2', '3', //
  '4', '5', '6', //
  '7', '8', '9', //
  '*', '0', '#', //
];

const Map<String, String> _kKeypadLetters = {
  '2': 'ABC',
  '3': 'DEF',
  '4': 'GHI',
  '5': 'JKL',
  '6': 'MNO',
  '7': 'PQRS',
  '8': 'TUV',
  '9': 'WXYZ',
  '0': '+',
};

/// Numeric keypad shown as a bottom sheet so a user can call any phone
/// number, even one that isn't saved as a contact — previously the only
/// way to place a call was tapping the call icon on an existing saved
/// contact.
class DialerSheet extends ConsumerStatefulWidget {
  const DialerSheet({super.key});

  @override
  ConsumerState<DialerSheet> createState() => _DialerSheetState();
}

class _DialerSheetState extends ConsumerState<DialerSheet> {
  String _input = '';
  bool _isCalling = false;

  void _onDigitTap(String digit) {
    setState(() => _input += digit);
  }

  void _onBackspace() {
    if (_input.isEmpty) return;
    setState(() => _input = _input.substring(0, _input.length - 1));
  }

  void _onBackspaceLongPress() {
    setState(() => _input = '');
  }

  Future<void> _onCallTap() async {
    final number = _input.trim();
    if (number.isEmpty || _isCalling) return;

    setState(() => _isCalling = true);
    try {
      final matched = await ref.read(contactRepositoryProvider).findByPhoneNumber(number);
      final contact = matched ?? ContactModel(id: '', fullName: number, phoneNumber: number);
      if (!mounted) return;
      await initiateCall(context, ref, contact);
    } finally {
      if (mounted) setState(() => _isCalling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 5,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const SizedBox(width: 32),
                const Expanded(
                  child: Text(
                    'Dialer',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'SF Pro Display',
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => Navigator.of(context).pop(),
                  child: const Padding(
                    padding: EdgeInsets.all(6),
                    child: Icon(Icons.close_rounded, size: 20, color: AppColors.textPrimary),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 48,
              child: Center(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  reverse: true,
                  child: Text(
                    _input.isEmpty ? 'Enter a number' : _input,
                    style: TextStyle(
                      fontFamily: 'SF Pro Display',
                      fontSize: 26,
                      fontWeight: FontWeight.w600,
                      color: _input.isEmpty ? AppColors.textSecondary : AppColors.textPrimary,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            GridView.count(
              shrinkWrap: true,
              crossAxisCount: 3,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.35,
              physics: const NeverScrollableScrollPhysics(),
              children: _kKeypadDigits
                  .map((digit) => _KeypadButton(
                        digit: digit,
                        letters: _kKeypadLetters[digit],
                        onTap: () => _onDigitTap(digit),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(width: 52, height: 52),
                const SizedBox(width: 24),
                GestureDetector(
                  onTap: _onCallTap,
                  child: Container(
                    width: 58,
                    height: 58,
                    decoration: const BoxDecoration(
                      color: Colors.green,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: _isCalling
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.4,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.call_rounded, color: Colors.white, size: 26),
                  ),
                ),
                const SizedBox(width: 24),
                SizedBox(
                  width: 52,
                  height: 52,
                  child: _input.isEmpty
                      ? null
                      : IconButton(
                          onPressed: _onBackspace,
                          onLongPress: _onBackspaceLongPress,
                          icon: const Icon(
                            Icons.backspace_outlined,
                            color: AppColors.textSecondary,
                          ),
                        ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _KeypadButton extends StatelessWidget {
  const _KeypadButton({required this.digit, required this.onTap, this.letters});

  final String digit;
  final String? letters;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      customBorder: const CircleBorder(),
      onTap: onTap,
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.mutedGray,
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              digit,
              style: const TextStyle(
                fontFamily: 'SF Pro Display',
                fontSize: 22,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            if (letters != null)
              Text(
                letters!,
                style: const TextStyle(
                  fontFamily: 'SF Pro Display',
                  fontSize: 9,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 1,
                  color: AppColors.textSecondary,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

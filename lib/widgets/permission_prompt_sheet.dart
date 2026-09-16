import 'package:flutter/material.dart';
import 'package:metadata/utils/app_colors.dart';

/// Centered permission-prompt dialog shared by the location/contacts/calls
/// asks shown one-by-one the first time a user lands on Home — icon,
/// title, subtitle, a primary "Allow ..." action, and a "Maybe Later"
/// dismiss.
class PermissionPromptSheet extends StatefulWidget {
  const PermissionPromptSheet({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.buttonLabel,
    required this.onAllow,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String buttonLabel;
  final Future<void> Function() onAllow;

  @override
  State<PermissionPromptSheet> createState() => _PermissionPromptSheetState();
}

class _PermissionPromptSheetState extends State<PermissionPromptSheet> {
  bool _isRequesting = false;

  Future<void> _handleAllow() async {
    if (_isRequesting) return;
    setState(() => _isRequesting = true);
    try {
      await widget.onAllow();
    } finally {
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 32, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _PermissionIllustration(icon: widget.icon),
            const SizedBox(height: 22),
            Text(
              widget.title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'SF Pro Display',
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              widget.subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'SF Pro Display',
                fontSize: 14,
                fontWeight: FontWeight.w400,
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 26),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                onPressed: _isRequesting ? null : _handleAllow,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryBlue,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(27),
                  ),
                ),
                child: _isRequesting
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        widget.buttonLabel,
                        style: const TextStyle(
                          fontFamily: 'SF Pro Display',
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 14),
            TextButton(
              onPressed: _isRequesting ? null : () => Navigator.of(context).pop(),
              child: const Text(
                'Maybe Later',
                style: TextStyle(
                  fontFamily: 'SF Pro Display',
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Decorative "planet + pins" style illustration approximating the design
/// reference — built from stock icons so no new image assets are needed.
class _PermissionIllustration extends StatelessWidget {
  const _PermissionIllustration({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 140,
      height: 110,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: const BoxDecoration(
              color: AppColors.mutedGray,
              shape: BoxShape.circle,
            ),
          ),
          Positioned(
            top: 30,
            left: 8,
            child: Icon(icon, size: 22, color: AppColors.primaryBlue),
          ),
          Positioned(
            top: 6,
            left: 58,
            child: Icon(icon, size: 26, color: AppColors.primaryBlue),
          ),
          Positioned(
            top: 34,
            right: 6,
            child: Icon(icon, size: 20, color: AppColors.primaryBlue),
          ),
          Positioned(
            bottom: 4,
            right: 30,
            child: Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: AppColors.white,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.primaryBlue, width: 3),
              ),
              alignment: Alignment.center,
              child: const Icon(
                Icons.search_rounded,
                size: 22,
                color: AppColors.primaryBlue,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

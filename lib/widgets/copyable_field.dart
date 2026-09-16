import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:metadata/utils/app_colors.dart';

/// A labelled read-only value with a copy button.
///
/// Built for the audience Bank Chat exists to help: someone paying by EFT who
/// may be older, may not see small type well, or may not be confident
/// retyping a ten-digit account number. So:
///
///  * the value is 17pt and `w700`, well above the app's body size;
///  * account numbers and branch codes are grouped in fours
///    ([groupDigits]) so the eye can check them against a bank statement
///    without losing its place — the *copied* text is always the raw,
///    ungrouped value, because spaces pasted into a banking app get rejected;
///  * the whole row is tappable, not just the icon, giving a target far larger
///    than the 34pt button on its own;
///  * copying confirms with a snackbar naming the field, since a silent copy
///    leaves the user unsure whether it worked and re-tapping is how
///    double-pastes happen.
class CopyableField extends StatelessWidget {
  const CopyableField({
    super.key,
    required this.label,
    required this.value,
    this.groupDigits = false,
    this.isLast = false,
  });

  final String label;
  final String value;

  /// Display the value in groups of four. For numeric identifiers only.
  final bool groupDigits;
  final bool isLast;

  static String _grouped(String raw) {
    final compact = raw.replaceAll(RegExp(r'\s+'), '');
    if (compact.length <= 4) return compact;
    final buffer = StringBuffer();
    for (var i = 0; i < compact.length; i += 4) {
      if (i > 0) buffer.write(' ');
      buffer.write(
        compact.substring(i, i + 4 > compact.length ? compact.length : i + 4),
      );
    }
    return buffer.toString();
  }

  Future<void> _copy(BuildContext context) async {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return;
    // Always the raw value, never the grouped display form — a banking app
    // will reject "1234 5678 90".
    await Clipboard.setData(ClipboardData(text: trimmed));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label copied'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final trimmed = value.trim();
    final hasValue = trimmed.isNotEmpty;
    final display = hasValue
        ? (groupDigits ? _grouped(trimmed) : trimmed)
        : 'Not set';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: hasValue ? () => _copy(context) : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: const TextStyle(
                          fontFamily: 'SF Pro Display',
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        display,
                        style: TextStyle(
                          fontFamily: 'SF Pro Display',
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          // Grouped digits read better with a little tracking.
                          letterSpacing: groupDigits && hasValue ? 0.6 : 0,
                          color: hasValue
                              ? AppColors.textPrimary
                              : AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Semantics(
                  button: true,
                  label: 'Copy $label',
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: hasValue
                          ? AppColors.primaryBlue.withValues(alpha: 0.10)
                          : AppColors.mutedGray,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.copy_rounded,
                      size: 18,
                      color: hasValue
                          ? AppColors.primaryBlue
                          : AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (!isLast) const Divider(height: 1, color: AppColors.border),
      ],
    );
  }
}

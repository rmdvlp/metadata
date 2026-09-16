import 'package:flutter/material.dart';
import 'package:metadata/utils/app_colors.dart';
import 'package:metadata/widgets/custom_loader.dart';

class CustomButton extends StatelessWidget {
  const CustomButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.color = AppColors.primaryBlue,
    this.textColor = AppColors.white,
    this.width,
    this.height,
    this.radius = 12,
    this.icon,
    this.iconSize = 20,
    this.fontSize = 16,
    this.fontWeight = FontWeight.w600,
    this.spacing = 8,
    this.enabled = true,
    this.isLoading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final Color color;
  final Color textColor;
  final double? width;
  final double? height;
  final double radius;
  final IconData? icon;
  final double iconSize;
  final double fontSize;
  final FontWeight fontWeight;
  final double spacing;
  final bool enabled;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final Size screenSize = MediaQuery.of(context).size;
    final double responsiveHeight = (height ?? screenSize.height * 0.07).clamp(
      50,
      64,
    );
    final Color effectiveColor = enabled
        ? color
        : color.withValues(alpha: 0.55);

    return SizedBox(
      width: width ?? double.infinity,
      height: responsiveHeight,
      child: ElevatedButton(
        onPressed: enabled && !isLoading ? onPressed : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: effectiveColor,
          foregroundColor: textColor,
          elevation: 0,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radius),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isLoading) ...[
              const AppLoader(size: 18),
              SizedBox(width: spacing),
            ] else if (icon != null) ...[
              Icon(icon, size: iconSize, color: textColor),
              SizedBox(width: spacing),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'SF Pro Display',
                  fontSize: fontSize,
                  fontWeight: fontWeight,
                  color: textColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

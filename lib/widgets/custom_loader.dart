import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:metadata/utils/app_colors.dart';

class AppLoader extends StatelessWidget {
  const AppLoader({super.key, this.size = 20, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final TargetPlatform platform = Theme.of(context).platform;

    if (platform == TargetPlatform.iOS) {
      return CupertinoActivityIndicator(
        radius: size / 2,
        color: color ?? AppColors.primaryBlue,
      );
    }

    return SizedBox(
      width: size,
      height: size,
      child: CircularProgressIndicator(
        strokeWidth: 2.5,
        color: color ?? AppColors.primaryBlue,
      ),
    );
  }
}

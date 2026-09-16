import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:metadata/utils/app_colors.dart';

/// Global blocking-loader config, shown for every Firebase call across the
/// app (auth, Firestore reads/writes, Storage uploads). One configuration
/// point so every screen gets the same look via `EasyLoading.show()`.
class AppLoading {
  AppLoading._();

  static void configure() {
    EasyLoading.instance
      ..displayDuration = const Duration(milliseconds: 2000)
      ..indicatorType = EasyLoadingIndicatorType.fadingCircle
      ..loadingStyle = EasyLoadingStyle.custom
      ..indicatorSize = 40.0
      ..radius = 14.0
      ..progressColor = AppColors.primaryBlue
      ..backgroundColor = AppColors.white
      ..indicatorColor = AppColors.primaryBlue
      ..textColor = AppColors.textPrimary
      ..maskColor = Colors.black.withValues(alpha: 0.25)
      ..userInteractions = false
      ..dismissOnTap = false;
  }

  static void show([String? status]) => EasyLoading.show(status: status ?? 'Please wait...');

  static void dismiss() => EasyLoading.dismiss();
}

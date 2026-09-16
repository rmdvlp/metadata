import 'package:flutter/material.dart';
import 'package:metadata/core/bootstrap/app_bootstrap_gate.dart';
import 'package:metadata/utils/app_colors.dart';
import 'package:metadata/utils/app_images.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  static const _animationDelay = Duration(milliseconds: 400);
  static const _minDisplayDuration = Duration(seconds: 3);

  late final AnimationController _controller;
  late final Animation<double> _scale;
  late final Animation<double> _opacity;

  bool _showApp = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _scale = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutBack,
    ).drive(Tween<double>(begin: 0.7, end: 1.0));
    _opacity = CurvedAnimation(parent: _controller, curve: Curves.easeIn);

    Future.delayed(_animationDelay, () {
      if (mounted) _controller.forward();
    });

    Future.delayed(_minDisplayDuration, () {
      if (mounted) setState(() => _showApp = true);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_showApp) return const AppBootstrapGate();

    return Scaffold(
      backgroundColor: AppColors.primaryBlue,
      body: Center(
        child: FadeTransition(
          opacity: _opacity,
          child: ScaleTransition(
            scale: _scale,
            child: Image.asset(
              AppImages.appLogo,
              width: 180,
              height: 180,
              fit: BoxFit.contain,
            ),
          ),
        ),
      ),
    );
  }
}

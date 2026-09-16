import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:metadata/utils/app_colors.dart';
import 'package:metadata/utils/size_config.dart';

class AuthShell extends StatelessWidget {
  const AuthShell({
    super.key,
    required this.illustrationAsset,
    required this.child,
  });

  final String illustrationAsset;
  final Widget child;

  /// Squeezed below this the illustration reads as a smudge rather than art,
  /// so it is dropped entirely instead of being crushed.
  static const double _minIllustrationSide = 72;

  @override
  Widget build(BuildContext context) {
    sizeConfig = SizeConfig.init(context);

    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Scaffold(
      backgroundColor: AppColors.primaryBlue,
      // The card handles the keyboard itself (see the padding below), so the
      // Scaffold must not also shrink the body — that would double-count it.
      resizeToAvoidBottomInset: false,
      body: LayoutBuilder(
        builder: (context, viewport) {
          // Hide illustration when keyboard is visible to prevent overlap
          final isKeyboardVisible = bottomInset > 0;

          final topPadding = isKeyboardVisible ? 120.0 : 30.0;

          return Column(
            children: [
              if (!isKeyboardVisible)
                Expanded(
                  child: SafeArea(
                    bottom: false,
                    child: LayoutBuilder(
                      builder: (context, slot) {
                        // The keyboard shrinks this slot as the card grows.
                        // Scale the illustration down to whatever is left rather
                        // than letting a fixed square overflow the Column.
                        final side = math.min(
                          sizeConfig.width(0.68),
                          slot.maxHeight - 24,
                        );
                        if (side < _minIllustrationSide) {
                          return const SizedBox.shrink();
                        }
                        return Center(
                          child: Image.asset(
                            illustrationAsset,
                            width: side,
                            height: side,
                            fit: BoxFit.contain,
                          ),
                        );
                      },
                    ),
                  ),
                ),
              // As a non-flex child the Column would hand the card unbounded
              // height; clamp it to the viewport so a tall form plus an open
              // keyboard scrolls instead of overflowing.
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: viewport.maxHeight),
                child: Container(
                  width: double.infinity,
                  decoration: const BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(30),
                    ),
                  ),
                  child: SingleChildScrollView(
                    // Inset lives inside the scroll view so the keyboard's
                    // space scrolls away with the content instead of pinning
                    // dead padding under it.
                    padding: EdgeInsets.fromLTRB(
                      24,
                      topPadding,
                      24,
                      24 + bottomInset,
                    ),
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 520),
                        child: child,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

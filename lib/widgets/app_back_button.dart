import 'package:flutter/material.dart';
import 'package:metadata/utils/app_colors.dart';

/// The app's back control: a grey circle with a blue rounded arrow, as used on
/// the Profile screen.
///
/// Screens that build their own header (Profile, Support Center, Saved Contact
/// Details) place it directly in a [Row]. Screens with an [AppBar] use
/// [AppBackButton.appBar], which lines the circle up with the 16pt content
/// margin the rest of the app uses — pair it with [AppBackButton.leadingWidth].
class AppBackButton extends StatelessWidget {
  const AppBackButton({super.key, this.onPressed}) : _inAppBar = false;

  /// Sized and inset for an [AppBar.leading] slot.
  const AppBackButton.appBar({super.key, this.onPressed}) : _inAppBar = true;

  /// The [AppBar.leadingWidth] that [AppBackButton.appBar] needs: 16pt inset
  /// plus the 40pt circle, with room to spare before the title.
  static const double leadingWidth = 64;

  /// Defaults to popping the current route.
  final VoidCallback? onPressed;

  final bool _inAppBar;

  @override
  Widget build(BuildContext context) {
    final button = Semantics(
      button: true,
      label: 'Back',
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onPressed ?? () => Navigator.of(context).pop(),
        child: Container(
          width: 40,
          height: 40,
          decoration: const BoxDecoration(
            color: AppColors.mutedGray,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: const Icon(
            Icons.arrow_back_rounded,
            color: AppColors.primaryBlue,
          ),
        ),
      ),
    );

    if (!_inAppBar) return button;

    // The leading slot is as tall as the toolbar and as wide as
    // [leadingWidth]; keep the circle its natural size inside it.
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(left: 16),
        child: button,
      ),
    );
  }
}

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:metadata/utils/app_colors.dart';

/// Shared circular avatar for both saved contacts and the user's own
/// profile: shows the photo when one is set (or loads correctly), otherwise
/// a consistent `Icons.person` fallback — so "no photo" looks the same
/// everywhere a contact/profile picture is shown, instead of each screen
/// picking its own placeholder.
///
/// Pass [onFavoriteTap] to render a single heart badge over the photo —
/// green when [isFavorite] is false, red when true — that toggles favorite
/// status on tap. Omit it (leave null) where a contact photo is shown
/// without favorite control at all.
class ContactAvatar extends StatelessWidget {
  const ContactAvatar({
    super.key,
    required this.diameter,
    this.photoUrl,
    this.localFile,
    this.isFavorite = false,
    this.onFavoriteTap,
  });

  final double diameter;
  final String? photoUrl;
  final File? localFile;
  final bool isFavorite;
  final VoidCallback? onFavoriteTap;

  @override
  Widget build(BuildContext context) {
    final Widget photo = _buildPhoto();
    final onTap = onFavoriteTap;
    if (onTap == null) return photo;

    final badgeSize = (diameter * 0.36).clamp(18.0, 40.0);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        photo,
        Positioned(
          right: -badgeSize * 0.08,
          bottom: -badgeSize * 0.08,
          child: GestureDetector(
            onTap: onTap,
            child: Container(
              width: badgeSize,
              height: badgeSize,
              decoration: BoxDecoration(
                color: isFavorite ? Colors.redAccent : Colors.green,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.white, width: badgeSize * 0.08),
              ),
              alignment: Alignment.center,
              child: Icon(
                Icons.favorite_rounded,
                size: badgeSize * 0.52,
                color: AppColors.white,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPhoto() {
    final file = localFile;
    if (file != null) {
      return ClipOval(
        child: Image.file(
          file,
          width: diameter,
          height: diameter,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => _fallback(),
        ),
      );
    }

    final url = photoUrl;
    if (url != null) {
      return ClipOval(
        child: Image.network(
          url,
          width: diameter,
          height: diameter,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => _fallback(),
        ),
      );
    }

    return _fallback();
  }

  Widget _fallback() {
    return Container(
      width: diameter,
      height: diameter,
      decoration: const BoxDecoration(color: AppColors.mutedGray, shape: BoxShape.circle),
      child: Icon(Icons.person, size: diameter * 0.42, color: AppColors.textSecondary),
    );
  }
}

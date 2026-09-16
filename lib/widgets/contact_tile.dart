import 'package:flutter/material.dart';
import 'package:metadata/models/contact_model.dart';
import 'package:metadata/utils/app_colors.dart';
import 'package:metadata/utils/app_images.dart';
import 'package:metadata/utils/contact_quarantine.dart';
import 'package:metadata/widgets/contact_avatar.dart';
import 'package:metadata/widgets/quarantine_badge.dart';

/// Marks a contact the user has blocked, so a blocked contact is never
/// indistinguishable from any other row in a list.
class _BlockedBadge extends StatelessWidget {
  const _BlockedBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.redAccent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(7),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.block_rounded, size: 11, color: Colors.redAccent),
          SizedBox(width: 3),
          Text(
            'Blocked',
            style: TextStyle(
              fontFamily: 'SF Pro Display',
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: Colors.redAccent,
            ),
          ),
        ],
      ),
    );
  }
}

/// Shared contact row used by Home's "Recent Contacts" list and the
/// "See All Contacts" screen — avatar (with a tap-to-toggle favorite heart
/// badge), name, a caller-supplied subtitle line, and a call action.
class ContactTile extends StatelessWidget {
  const ContactTile({
    super.key,
    required this.contact,
    required this.subtitle,
    this.onTap,
    required this.onCallTap,
    required this.onFavoriteTap,
    this.callIcon,
    this.selected,
    this.onLongPress,
    this.onQuarantineTap,
  });

  final ContactModel contact;
  final Widget subtitle;
  final VoidCallback? onTap;
  final VoidCallback onCallTap;
  final VoidCallback onFavoriteTap;

  /// Non-null puts the row in selection mode: the trailing call button gives
  /// way to a checkmark, and the row tints when picked. The caller owns what
  /// tapping does — this only draws the state.
  final bool? selected;

  /// Typically starts selection mode on the list that owns this row.
  final VoidCallback? onLongPress;

  /// Opens the "Keep or Remove Contact?" review for a quarantined contact.
  /// The red pill only appears when the contact has actually been silent for
  /// [kQuarantineAfter]; passing null renders it as a plain label, which is
  /// what a list in selection mode wants.
  final VoidCallback? onQuarantineTap;

  /// Replaces the phone image in the trailing call button. "Recent Call Logs"
  /// puts the call's direction and outcome here — outgoing, incoming, missed
  /// or declined — so the row reads at a glance without a second icon in the
  /// subtitle. Tapping still places a call either way.
  final Widget? callIcon;

  @override
  Widget build(BuildContext context) {
    final isSelecting = selected != null;
    final isSelected = selected ?? false;

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.lightBlueFill : AppColors.mutedGray,
          borderRadius: BorderRadius.circular(18),
          border: isSelected
              ? Border.all(color: AppColors.primaryBlue, width: 1.5)
              : null,
        ),
        child: Row(
          children: [
            ContactAvatar(
              diameter: 52,
              photoUrl: contact.photoUrl,
              isFavorite: contact.isFavorite,
              // While selecting, the whole row is one tap target.
              onFavoriteTap: isSelecting ? null : onFavoriteTap,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          contact.fullName,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: 'SF Pro Display',
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      if (contact.isBlocked) const _BlockedBadge(),
                      if (isQuarantined(contact))
                        QuarantineBadge(
                          onTap: isSelecting ? null : onQuarantineTap,
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  subtitle,
                ],
              ),
            ),
            if (isSelecting)
              Padding(
                padding: const EdgeInsets.only(left: 4, right: 8),
                child: Icon(
                  isSelected
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  size: 24,
                  color: isSelected
                      ? AppColors.primaryBlue
                      : AppColors.textSecondary,
                ),
              )
            else
              // Calling someone you have blocked is almost never intended, so
              // the action is disabled rather than merely labelled. Unblocking
              // is one tap away in the contact's ⋮ menu.
              IconButton(
                onPressed: contact.isBlocked ? null : onCallTap,
                tooltip: contact.isBlocked ? 'Contact is blocked' : 'Call',
                // A blocked contact keeps the greyed-out phone in every list —
                // the disabled action is the point, so a direction icon here
                // would only dilute it.
                icon: contact.isBlocked
                    ? Image.asset(
                        AppImages.callCalling,
                        width: 22,
                        height: 22,
                        color: AppColors.textSecondary,
                      )
                    : callIcon ??
                          Image.asset(
                            AppImages.callCalling,
                            width: 22,
                            height: 22,
                          ),
              ),
          ],
        ),
      ),
    );
  }
}

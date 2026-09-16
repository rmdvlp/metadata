import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metadata/core/loading/app_loading.dart';
import 'package:metadata/models/contact_model.dart';
import 'package:metadata/repositories/contact_repository.dart';
import 'package:metadata/utils/app_colors.dart';
import 'package:metadata/utils/contact_quarantine.dart';

/// What the user chose in the "Keep or Remove Contact?" prompt.
enum QuarantineDecision { delete, skip }

/// The red "Quarantine" pill shown against a contact that has been silent for
/// [kQuarantineAfter] — beside the name in any list, and under the photo on
/// Saved Contact Details.
///
/// Tapping it opens the review prompt. The pill is padded well beyond its own
/// ink so the tap target clears the ~20pt label; without that it would be one
/// of the smallest touch targets in the app, on a screen aimed partly at
/// people who find small targets hard to hit.
class QuarantineBadge extends StatelessWidget {
  const QuarantineBadge({super.key, this.onTap, this.large = false});

  /// Null renders the pill as a plain label — used while a list is in
  /// selection mode, where every tap belongs to the row.
  final VoidCallback? onTap;

  /// The Saved Contact Details size. Lists use the compact form.
  final bool large;

  static const Color _red = Colors.redAccent;

  @override
  Widget build(BuildContext context) {
    final pill = Container(
      padding: large
          ? const EdgeInsets.symmetric(horizontal: 14, vertical: 6)
          : const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: _red.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(large ? 12 : 8),
      ),
      child: Text(
        'Quarantine',
        style: TextStyle(
          fontFamily: 'SF Pro Display',
          fontSize: large ? 13 : 10,
          fontWeight: FontWeight.w700,
          color: _red,
        ),
      ),
    );

    if (onTap == null) {
      return Padding(
        padding: EdgeInsets.only(left: large ? 0 : 6),
        child: pill,
      );
    }

    return Semantics(
      button: true,
      label: 'Quarantine. Review whether to keep this contact.',
      child: GestureDetector(
        // Opaque so the tap stops here instead of also opening the row.
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.only(
            left: large ? 6 : 6,
            right: 6,
            top: 6,
            bottom: 6,
          ),
          child: pill,
        ),
      ),
    );
  }
}

/// The review prompt: "You haven't spoken in about this long — keep them, or
/// delete them?"
///
/// Skip is the primary action and Delete the quiet one, because the
/// destructive choice should never be the one an accidental tap lands on.
/// Delete is lettered in red for the same reason — deleting a contact also
/// takes its notes and timeline, and there is no undo.
Future<QuarantineDecision?> showKeepOrRemoveContactDialog({
  required BuildContext context,
  required String contactName,
  required String silenceLabel,
}) {
  final name = contactName.trim().isEmpty ? 'this contact' : contactName.trim();

  return showDialog<QuarantineDecision>(
    context: context,
    builder: (dialogContext) => Dialog(
      backgroundColor: AppColors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Keep or Remove Contact?',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'SF Pro Display',
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'You last communicated with $name $silenceLabel. Would you like '
              'to keep this contact in your records, or would you prefer to '
              'delete it?',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'SF Pro Display',
                fontSize: 14,
                height: 1.45,
                fontWeight: FontWeight.w400,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 52,
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(
                        dialogContext,
                      ).pop(QuarantineDecision.delete),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.mutedGray,
                        foregroundColor: Colors.redAccent,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: const Text(
                        'Delete',
                        style: TextStyle(
                          fontFamily: 'SF Pro Display',
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: 52,
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(
                        dialogContext,
                      ).pop(QuarantineDecision.skip),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryBlue,
                        foregroundColor: AppColors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: const Text(
                        'Skip',
                        style: TextStyle(
                          fontFamily: 'SF Pro Display',
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

/// Shows the prompt for [contact] and carries out what was chosen.
///
/// Skip writes nothing at all. It means "keep them", and the pill stays —
/// it reports a fact (no contact in over two years) rather than a reminder to
/// dismiss, and the fact is still true after Skip. Writing a "reviewed" flag
/// would also bump `updatedAt`, which for older contacts *is* the quarantine
/// clock, so a Skip would silently reset the very thing it was reviewing.
///
/// [onDeleted] runs after a successful delete, before the confirmation — the
/// details screen uses it to leave a screen whose contact no longer exists.
Future<void> reviewQuarantinedContact(
  BuildContext context,
  WidgetRef ref,
  ContactModel contact, {
  VoidCallback? onDeleted,
  DateTime? now,
}) async {
  if (contact.id.isEmpty) return;

  // Captured before the await: deleting the contact makes its stream emit
  // null, which can tear the calling widget out of the tree — reading the
  // messenger afterwards would find an unmounted context and swallow the
  // confirmation.
  final messenger = ScaffoldMessenger.of(context);
  final name = contact.fullName;

  final decision = await showKeepOrRemoveContactDialog(
    context: context,
    contactName: name,
    silenceLabel: quarantineSilenceLabel(contact, now: now),
  );
  if (decision != QuarantineDecision.delete) return;

  AppLoading.show();
  try {
    await ref
        .read(contactRepositoryProvider)
        .deleteContact(contact.id)
        .timeout(const Duration(seconds: 20));
    onDeleted?.call();
    messenger.showSnackBar(
      SnackBar(content: Text('${name.isEmpty ? 'Contact' : name} deleted.')),
    );
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(content: Text('Could not delete this contact: $e')),
    );
  } finally {
    AppLoading.dismiss();
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metadata/models/call_log_model.dart';
import 'package:metadata/repositories/call_flow_helper.dart';
import 'package:metadata/repositories/call_log_repository.dart';
import 'package:metadata/repositories/contact_repository.dart';
import 'package:metadata/screens/saved_contact_details_screen.dart';
import 'package:metadata/utils/app_colors.dart';
import 'package:metadata/utils/app_images.dart';
import 'package:metadata/utils/date_formatting.dart';
import 'package:metadata/widgets/contact_tile.dart';

/// One call in the "Recent Call Logs" feed. Shared by Home (which shows a
/// paged slice) and the See All screen (which shows the whole window) so the
/// two lists can never drift apart.
class RecentCallLogTile extends ConsumerWidget {
  const RecentCallLogTile({super.key, required this.log});

  final RecentCallLog log;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contact = log.contact;
    final locationText =
        contact.location?.placeName ?? contact.location?.address;
    final occurredAt = log.occurredAt;
    final dateText = occurredAt != null
        ? formatRelativeDateTime(occurredAt, now: DateTime.now())
        : '';
    // Only calls that were actually answered have one, so this doubles as the
    // at-a-glance answer to "did we actually talk, and for how long".
    final durationText = log.durationLabel;

    return ContactTile(
      contact: contact,
      callIcon: _CallOutcomeIcon(log: log),
      // Ad-hoc dialer numbers and unknown callers have no saved contact doc,
      // so there is nothing to open — leave those rows non-navigable.
      onTap: contact.id.isEmpty
          ? null
          : () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      SavedContactDetailsScreen(contactId: contact.id),
                ),
              );
            },
      onCallTap: () => initiateCall(context, ref, contact),
      onFavoriteTap: () => toggleContactFavorite(ref, contact),
      // No direction arrow here — it now lives in the trailing call button.
      subtitle: Row(
        children: [
          Text(
            log.statusLabel,
            style: TextStyle(
              fontFamily: 'SF Pro Display',
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: log.isMissed ? Colors.redAccent : AppColors.textSecondary,
            ),
          ),
          if (durationText != null) ...[
            const _SubtitleDot(),
            Text(
              durationText,
              style: const TextStyle(
                fontFamily: 'SF Pro Display',
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ],
          if (dateText.isNotEmpty) ...[
            const _SubtitleDot(),
            Text(
              dateText,
              style: const TextStyle(
                fontFamily: 'SF Pro Display',
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ],
          if (locationText != null) ...[
            const _SubtitleDot(),
            Image.asset(
              AppImages.location,
              width: 12,
              height: 12,
              color: AppColors.primaryBlue,
            ),
            const SizedBox(width: 3),
            // Last and flexible so a long place name ellipsizes instead of
            // pushing the direction and time off the row.
            Flexible(
              child: Text(
                locationText,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'SF Pro Display',
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The call's outcome, shown in the trailing slot of the row where other
/// lists show a plain phone image. Tapping it still starts a call — this only
/// changes what the button looks like.
///
/// The call-outgoing asset is already green and the call-incoming one red, so
/// a connected call needs no tinting. Missed and declined have no asset of
/// their own and are drawn from Material icons, both in red: neither call
/// resulted in a conversation, and that is the thing worth spotting in a long
/// list.
class _CallOutcomeIcon extends StatelessWidget {
  const _CallOutcomeIcon({required this.log});

  final RecentCallLog log;

  @override
  Widget build(BuildContext context) {
    const double size = 22;

    return switch (log.entry.status) {
      CallLogStatus.missed => const Icon(
        Icons.call_missed_rounded,
        size: size,
        color: Colors.redAccent,
      ),
      CallLogStatus.declined => const Icon(
        Icons.phone_disabled_rounded,
        size: size,
        color: Colors.redAccent,
      ),
      CallLogStatus.received => Image.asset(
        AppImages.callIncoming,
        width: size,
        height: size,
      ),
      CallLogStatus.dialed => Image.asset(
        AppImages.callOutgoing,
        width: size,
        height: size,
      ),
      // A completed call can be either side, so it follows the direction.
      CallLogStatus.completed => Image.asset(
        log.isIncoming ? AppImages.callIncoming : AppImages.callOutgoing,
        width: size,
        height: size,
      ),
    };
  }
}

class _SubtitleDot extends StatelessWidget {
  const _SubtitleDot();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 5),
      child: Text(
        '·',
        style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
      ),
    );
  }
}

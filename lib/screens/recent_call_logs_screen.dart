import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metadata/models/contact_model.dart';
import 'package:metadata/repositories/call_log_repository.dart';
import 'package:metadata/utils/app_colors.dart';
import 'package:metadata/widgets/app_back_button.dart';
import 'package:metadata/widgets/contact_tile.dart';
import 'package:metadata/widgets/recent_call_log_tile.dart';
import 'package:skeletonizer/skeletonizer.dart';

class RecentCallLogsScreen extends ConsumerWidget {
  const RecentCallLogsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recentCallLogsAsync = ref.watch(recentCallLogsProvider);

    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'Recent Call Logs',
          style: TextStyle(
            fontFamily: 'SF Pro Display',
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        leading: const AppBackButton.appBar(),
        leadingWidth: AppBackButton.leadingWidth,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: recentCallLogsAsync.when(
            // Once the feed has data, a recompute must not drop back to the
            // skeleton: the empty state is a small centred box and the
            // skeleton is a full-height 8-row list, so flipping between them
            // reads as the screen jerking.
            skipLoadingOnReload: true,
            loading: () => Skeletonizer(
              enabled: true,
              child: ListView.separated(
                itemCount: 8,
                separatorBuilder: (context, index) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final contact = ContactModel(
                    id: 'skeleton-$index',
                    fullName: 'Loading Name',
                    phoneNumber: '+1 000 000 0000',
                    updatedAt: DateTime.now(),
                  );
                  return ContactTile(
                    contact: contact,
                    subtitle: const Text(
                      'Loading…',
                      style: TextStyle(
                        fontFamily: 'SF Pro Display',
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    onCallTap: () {},
                    onFavoriteTap: () {},
                  );
                },
              ),
            ),
            error: (error, _) => Center(child: Text('Could not load recent call logs: $error')),
            data: (logs) {
              // No slicing here — this is the "See All" destination, so it
              // renders the whole seven-day window the provider already
              // bounds, while Home shows a paged slice of the same feed.
              if (logs.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 56,
                          height: 56,
                          decoration: const BoxDecoration(
                            color: AppColors.mutedGray,
                            shape: BoxShape.circle,
                          ),
                          alignment: Alignment.center,
                          child: const Icon(
                            Icons.history_rounded,
                            color: AppColors.textSecondary,
                            size: 28,
                          ),
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          'No Recent Call Logs',
                          style: TextStyle(
                            fontFamily: 'SF Pro Display',
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Your last 7 days of incoming, outgoing, and missed calls will appear here.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: 'SF Pro Display',
                            fontSize: 13,
                            color: AppColors.textSecondary,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }

              return ListView.separated(
                itemCount: logs.length,
                separatorBuilder: (context, index) => const SizedBox(height: 12),
                itemBuilder: (context, index) =>
                    RecentCallLogTile(log: logs[index]),
              );
            },
          ),
        ),
      ),
    );
  }
}

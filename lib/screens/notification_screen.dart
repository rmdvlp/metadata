import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metadata/core/loading/app_loading.dart';
import 'package:metadata/models/notification_model.dart';
import 'package:metadata/repositories/notification_repository.dart';
import 'package:metadata/screens/saved_contact_details_screen.dart';
import 'package:metadata/utils/app_colors.dart';
import 'package:metadata/utils/date_formatting.dart';
import 'package:metadata/widgets/contact_avatar.dart';
import 'package:skeletonizer/skeletonizer.dart';

final List<AppNotification> _kSkeletonNotifications = List.generate(
  5,
  (i) => AppNotification(
    id: 'skeleton-$i',
    type: NotificationType.generic,
    title: 'Loading title',
    body: 'Loading notification body text',
    createdAt: DateTime.now(),
  ),
);

class NotificationScreen extends ConsumerWidget {
  const NotificationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notificationsAsync = ref.watch(notificationsProvider);

    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        title: const Text(
          'Notifications',
          style: TextStyle(
            fontFamily: 'SF Pro Display',
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        backgroundColor: AppColors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: AppColors.primaryBlue,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              AppLoading.show();
              try {
                await ref.read(notificationRepositoryProvider).markAllAsRead();
              } finally {
                AppLoading.dismiss();
              }
            },
            child: const Text(
              'Mark all read',
              style: TextStyle(
                fontFamily: 'SF Pro Display',
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.primaryBlue,
              ),
            ),
          ),
        ],
      ),
      body: notificationsAsync.when(
        loading: () => Skeletonizer(
          enabled: true,
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            itemCount: _kSkeletonNotifications.length,
            separatorBuilder: (context, index) => const SizedBox(height: 12),
            itemBuilder: (context, index) =>
                _NotificationCard(item: _kSkeletonNotifications[index]),
          ),
        ),
        error: (error, _) =>
            Center(child: Text('Could not load notifications: $error')),
        data: (notifications) {
          if (notifications.isEmpty) {
            return const Center(
              child: Text(
                'No notifications yet.',
                style: TextStyle(
                  fontFamily: 'SF Pro Display',
                  color: AppColors.textSecondary,
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            itemCount: notifications.length,
            separatorBuilder: (context, index) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final item = notifications[index];
              return _NotificationCard(item: item);
            },
          );
        },
      ),
    );
  }
}

class _NotificationCard extends ConsumerWidget {
  final AppNotification item;

  const _NotificationCard({required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () async {
        AppLoading.show();
        try {
          await ref.read(notificationRepositoryProvider).markAsRead(item.id);
        } finally {
          AppLoading.dismiss();
        }
        if (!context.mounted) return;
        final contactId = item.relatedContactId;
        if (contactId != null) {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => SavedContactDetailsScreen(contactId: contactId),
            ),
          );
        }
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.mutedGray,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            ContactAvatar(diameter: 48, photoUrl: item.imageUrl),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: 'SF Pro Display',
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      if (!item.isRead) ...[
                        const SizedBox(width: 6),
                        Container(
                          width: 7,
                          height: 7,
                          decoration: const BoxDecoration(
                            color: Colors.green,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                      const Spacer(),
                      Text(
                        item.createdAt != null
                            ? formatTimeAgo(
                                item.createdAt!,
                                now: DateTime.now(),
                              )
                            : '',
                        style: const TextStyle(
                          fontFamily: 'SF Pro Display',
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.body,
                    style: const TextStyle(
                      fontFamily: 'SF Pro Display',
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                      color: AppColors.textSecondary,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.primaryBlue,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }
}

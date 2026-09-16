import 'package:flutter/material.dart';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metadata/core/bootstrap/auth_gate.dart';
import 'package:metadata/core/permissions/permission_prompt_flow.dart';
import 'package:metadata/models/call_log_model.dart';
import 'package:metadata/models/contact_model.dart';
import 'package:metadata/repositories/call_log_repository.dart';
import 'package:metadata/repositories/device_contacts_service.dart';
import 'package:metadata/repositories/notification_repository.dart';
import 'package:metadata/screens/notification_screen.dart';
import 'package:metadata/screens/profile_screen.dart';
import 'package:metadata/screens/recent_call_logs_screen.dart';
import 'package:metadata/screens/saved_contacts_screen.dart';
import 'package:metadata/utils/app_colors.dart';
import 'package:metadata/utils/app_images.dart';
import 'package:metadata/widgets/button.dart';
import 'package:metadata/widgets/contact_avatar.dart';
import 'package:metadata/widgets/contact_fab_column.dart';
import 'package:metadata/widgets/recent_call_log_tile.dart';
import 'package:skeletonizer/skeletonizer.dart';

/// How many calls Home shows before the user scrolls, and how many more each
/// time they reach the bottom.
const int _kInitialCallLogCount = 30;
const int _kCallLogPageSize = 10;

/// Minimum offset change (in logical pixels) between two scroll notifications
/// before the Contextual Memory card reacts — filters out the sub-pixel
/// jitter every frame of a fling reports, which would otherwise flip the card
/// on and off within a single continuous gesture.
const double _kScrollDirectionThreshold = 2.0;

final List<RecentCallLog> _kSkeletonCallLogs = List.generate(4, (i) {
  final contact = ContactModel(
    id: 'skeleton-$i',
    fullName: 'Loading Name',
    phoneNumber: '+1 000 000 0000',
    updatedAt: DateTime.now(),
  );
  return RecentCallLog(
    entry: CallLogEntry(
      id: 'skeleton-$i',
      contactId: contact.id,
      calleeName: contact.fullName,
      calleePhone: contact.phoneNumber,
      startedAt: DateTime.now(),
    ),
    contact: contact,
  );
});

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _syncTriggered = false;
  bool _permissionPromptTriggered = false;
  bool _showContextualMemory = true;
  int _displayedCallLogLimit = _kInitialCallLogCount;

  /// How many calls the feed currently holds. Written during build (never with
  /// setState — build is the source of truth) purely so the scroll listener
  /// knows when there is nothing left to page in.
  int _availableCallLogCount = 0;

  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _maybeSyncDeviceContacts(),
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// Hides the Contextual Memory card while the user drags down into the
  /// call log, and brings it back once they drag back up toward the top.
  ///
  /// This has already gone through two other approaches that each looked
  /// right until tested on a real device:
  ///
  ///  1. Reading [ScrollPosition.userScrollDirection] resets to
  ///     [ScrollDirection.idle] on every [HoldScrollActivity] — *any*
  ///     touch-down on the list, including grabbing it again before a fling
  ///     settles — so hiding worked but bringing the card back after a
  ///     fling-then-reverse-swipe often didn't.
  ///  2. Comparing [ScrollController.offset] deltas between notifications
  ///     fixed that, but introduced a worse bug: this card animates its own
  ///     height via [AnimatedSize], and the list below it is [Expanded], so
  ///     hiding the card grows the list's viewport and *shrinks*
  ///     [ScrollMetrics.maxScrollExtent]. When the current offset ends up
  ///     past the new, smaller max, Flutter corrects it with a
  ///     [BallisticScrollActivity] snap-back — a real, notifying scroll
  ///     update with a negative delta, indistinguishable from the user
  ///     swiping back toward the top. That correction would immediately flip
  ///     the card visible again mid-hide, which is exactly the "swipe up
  ///     doesn't stay hidden, it snaps back down and shows the card" report.
  ///
  /// [ScrollUpdateNotification.dragDetails] is non-null only while a finger
  /// is actually moving the list (a real drag), and null for both the
  /// momentum phase of a fling and any framework-driven correction like the
  /// one above — so gating on it ignores exactly the spurious case while
  /// still catching every real gesture, including the reverse-swipe grab
  /// from case 1.
  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification is! ScrollUpdateNotification) return false;
    final metrics = notification.metrics;

    if (metrics.pixels <= metrics.minScrollExtent) {
      if (!_showContextualMemory) {
        setState(() => _showContextualMemory = true);
      }
    } else if (notification.dragDetails != null) {
      final delta = notification.scrollDelta ?? 0;
      if (delta > _kScrollDirectionThreshold && _showContextualMemory) {
        // Offset increasing: scrolling further into the list, away from top.
        setState(() => _showContextualMemory = false);
      } else if (delta < -_kScrollDirectionThreshold &&
          !_showContextualMemory) {
        // Offset decreasing: scrolling back toward the top.
        setState(() => _showContextualMemory = true);
      }
    }

    // Near the bottom: reveal the next page, capped by what the feed actually
    // holds, so the list grows 30 → 40 → 50 … until the last call is shown.
    if (metrics.pixels >= metrics.maxScrollExtent - 120 &&
        _displayedCallLogLimit < _availableCallLogCount) {
      setState(() {
        _displayedCallLogLimit = math.min(
          _displayedCallLogLimit + _kCallLogPageSize,
          _availableCallLogCount,
        );
      });
    }

    return false;
  }

  Future<void> _maybeSyncDeviceContacts() async {
    if (_syncTriggered) return;
    _syncTriggered = true;
    await ref
        .read(deviceContactsServiceProvider)
        .syncDeviceContactsToFirestore();
  }

  void _maybeShowPermissionPrompts(bool permissionsPrompted) {
    if (_permissionPromptTriggered || permissionsPrompted) return;
    _permissionPromptTriggered = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showPermissionPrompts(context, ref);
    });
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(userProfileStreamProvider);
    final recentCallLogsAsync = ref.watch(recentCallLogsProvider);
    final unreadCallNotificationCount = ref.watch(
      unreadCallNotificationCountProvider,
    );
    final displayName = profileAsync.value?.displayName;

    final profile = profileAsync.value;
    if (profile != null) {
      _maybeShowPermissionPrompts(profile.permissionsPrompted);
    }

    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: AppColors.white,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Hi 👋',
              style: TextStyle(
                fontFamily: 'SF Pro Display',
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              (displayName == null || displayName.isEmpty)
                  ? 'Welcome'
                  : displayName,
              style: const TextStyle(
                fontFamily: 'SF Pro Display',
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const NotificationScreen(),
                  ),
                );
              },
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: const BoxDecoration(
                      color: AppColors.mutedGray,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Image.asset(
                      AppImages.notification,
                      width: 20,
                      height: 20,
                    ),
                  ),
                  // Unread incoming, missed and outgoing call notifications.
                  if (unreadCallNotificationCount > 0)
                    Positioned(
                      right: 2,
                      top: 2,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.redAccent,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          unreadCallNotificationCount > 9
                              ? '9+'
                              : unreadCallNotificationCount.toString(),
                          style: const TextStyle(
                            fontFamily: 'SF Pro Display',
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ProfileScreen()),
                );
              },
              child: ContactAvatar(diameter: 44, photoUrl: profile?.photoUrl),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimatedSize(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOut,
                alignment: Alignment.topCenter,
                child: !_showContextualMemory
                    ? const SizedBox(width: double.infinity)
                    : Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: AppColors.mutedGray,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.textSecondary.withValues(
                                alpha: 0.10,
                              ),
                              blurRadius: 10,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Contextual Memory',
                              style: TextStyle(
                                fontFamily: 'SF Pro Display',
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 10),
                            const Text(
                              'Save a contact now. We\'ll capture your physical address, venue name, and exact time automatically.',
                              style: TextStyle(
                                fontFamily: 'SF Pro Display',
                                fontSize: 13,
                                fontWeight: FontWeight.w400,
                                color: AppColors.textSecondary,
                                height: 1.5,
                              ),
                            ),
                            const SizedBox(height: 18),
                            SizedBox(
                              width: double.infinity,
                              child: CustomButton(
                                label: 'Add New Contact',
                                onPressed: () => openNewContactScreen(context),
                                height: 48,
                                fontSize: 13,
                                icon: Icons.add_rounded,
                                iconSize: 18,
                              ),
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              child: CustomButton(
                                label: 'View Saved Contact',
                                onPressed: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) =>
                                          const SavedContactsScreen(),
                                    ),
                                  );
                                },
                                height: 44,
                                fontSize: 13,
                                color: AppColors.lightBlueFill,
                                textColor: AppColors.primaryBlue,
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Recent Call Logs',
                    style: TextStyle(
                      fontFamily: 'SF Pro Display',
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  TextButton(
                    // The full seven-day history, unpaged.
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const RecentCallLogsScreen(),
                        ),
                      );
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.primaryBlue,
                      padding: EdgeInsets.zero,
                    ),
                    child: const Text(
                      'See All',
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
              const SizedBox(height: 12),
              Expanded(
                child: NotificationListener<ScrollNotification>(
                  onNotification: _handleScrollNotification,
                  child: recentCallLogsAsync.when(
                    // See recent_call_logs_screen: never fall back to the
                    // skeleton once the feed has data.
                    skipLoadingOnReload: true,
                    loading: () => Skeletonizer(
                      enabled: true,
                      child: ListView.separated(
                        itemCount: _kSkeletonCallLogs.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: 12),
                        itemBuilder: (context, index) =>
                            RecentCallLogTile(log: _kSkeletonCallLogs[index]),
                      ),
                    ),
                    error: (error, _) =>
                        Center(child: Text('Could not load call logs: $error')),
                    data: (logs) {
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
                                    Icons.people_outline_rounded,
                                    color: AppColors.textSecondary,
                                    size: 26,
                                  ),
                                ),
                                const SizedBox(height: 14),
                                const Text(
                                  'No Recent Call Logs Yet',
                                  style: TextStyle(
                                    fontFamily: 'SF Pro Display',
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                const Text(
                                  'Calls you dial, receive, or miss will show up here. Start a call and stay connected!',
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
                      _availableCallLogCount = logs.length;
                      final displayedLogs = logs
                          .take(_displayedCallLogLimit)
                          .toList();
                      return ListView.separated(
                        controller: _scrollController,
                        itemCount: displayedLogs.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: 12),
                        itemBuilder: (context, index) =>
                            RecentCallLogTile(log: displayedLogs[index]),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: const ContactFabColumn(),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metadata/repositories/connectivity_service.dart';
import 'package:metadata/utils/app_colors.dart';
import 'package:metadata/widgets/button.dart';

/// Shown when the device has no internet connection. Any contacts, notes,
/// or timeline entries added/edited while offline are still saved locally
/// (Firestore's own offline cache queues them) and sync automatically the
/// moment connectivity returns — this screen just makes that state visible
/// instead of the app silently looking broken.
class PendingSyncScreen extends ConsumerWidget {
  const PendingSyncScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOnline = ref.watch(connectivityStatusProvider).value ?? true;

    if (isOnline && Navigator.of(context).canPop()) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (Navigator.of(context).canPop()) Navigator.of(context).pop();
      });
    }

    return Scaffold(
      backgroundColor: AppColors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 84,
                height: 84,
                decoration: const BoxDecoration(
                  color: AppColors.lightBlueFill,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.cloud_off_rounded,
                  size: 38,
                  color: AppColors.primaryBlue,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Pending Sync',
                style: TextStyle(
                  fontFamily: 'SF Pro Display',
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'You\'re offline right now. Any contacts, notes, or timeline '
                'entries you add will be saved on this device and synced '
                'automatically as soon as your connection is back.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'SF Pro Display',
                  fontSize: 14,
                  color: AppColors.textSecondary,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: 200,
                child: CustomButton(
                  label: 'Close',
                  onPressed: () => Navigator.of(context).maybePop(),
                  height: 48,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

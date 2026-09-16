import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metadata/repositories/connectivity_service.dart';
import 'package:metadata/screens/pending_sync_screen.dart';

/// Slim app-wide banner shown whenever the device is offline — mounted once
/// in `main.dart`'s `MaterialApp.builder` so it overlays every screen
/// without each screen having to opt in individually. Tapping it opens the
/// full [PendingSyncScreen] with more detail.
class PendingSyncBanner extends ConsumerWidget {
  const PendingSyncBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connectivity = ref.watch(connectivityStatusProvider);
    final isOnline = connectivity.value ?? true;

    if (isOnline) return const SizedBox.shrink();

    return SafeArea(
      bottom: false,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            Navigator.of(context, rootNavigator: true).push(
              MaterialPageRoute<void>(builder: (_) => const PendingSyncScreen()),
            );
          },
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: const Color(0xFFFFF3CD),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.cloud_off_rounded, size: 14, color: Color(0xFF8A6D00)),
                const SizedBox(width: 6),
                const Text(
                  'You\'re offline — changes will sync automatically',
                  style: TextStyle(
                    fontFamily: 'SF Pro Display',
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF8A6D00),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

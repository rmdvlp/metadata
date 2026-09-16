import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metadata/core/bootstrap/auth_gate.dart';
import 'package:metadata/core/firebase/firebase_services.dart';
import 'package:metadata/core/loading/app_loading.dart';
import 'package:metadata/core/permissions/permission_prompt_flow.dart';
import 'package:metadata/models/user_profile.dart';
import 'package:metadata/utils/app_colors.dart';
import 'package:metadata/widgets/app_back_button.dart';
import 'package:metadata/widgets/settings_widgets.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(userProfileStreamProvider);
    final settings = profileAsync.value?.settings ?? UserSettings.defaults();

    Future<void> onToggle(String key, bool value) async {
      AppLoading.show();
      try {
        await ref.read(userProfileServiceProvider).updateSetting(key, value);
      } finally {
        AppLoading.dismiss();
      }
    }

    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        title: const Text(
          'Settings',
          style: TextStyle(
            fontFamily: 'SF Pro Display',
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        backgroundColor: AppColors.white,
        elevation: 0,
        centerTitle: true,
        leading: const AppBackButton.appBar(),
        leadingWidth: AppBackButton.leadingWidth,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          const SectionHeader(title: 'Privacy'),
          const SizedBox(height: 10),
          SettingsCard(
            children: [
              SettingsToggleTile(
                icon: Icons.shield_outlined,
                title: 'Metadata capture',
                subtitle: 'Attach place & time on save',
                value: settings.metadataCapture,
                onChanged: (v) => onToggle('metadataCapture', v),
              ),
              SettingsToggleTile(
                icon: Icons.devices_outlined,
                title: 'End-to-end encryption',
                subtitle: 'memories never leave device',
                value: settings.endToEndEncryption,
                onChanged: (v) => onToggle('endToEndEncryption', v),
              ),
              SettingsToggleTile(
                icon: Icons.dark_mode_outlined,
                title: 'Stealth mode',
                subtitle: 'Hide context from lock screen',
                value: settings.stealthMode,
                onChanged: (v) => onToggle('stealthMode', v),
                isLast: true,
              ),
            ],
          ),
          const SizedBox(height: 20),
          const SectionHeader(title: 'Notifications'),
          const SizedBox(height: 10),
          SettingsCard(
            children: [
              SettingsToggleTile(
                icon: Icons.notifications_none_rounded,
                title: 'Incoming call card',
                subtitle: 'show memory when contact call',
                value: settings.incomingCallCard,
                onChanged: (v) => onToggle('incomingCallCard', v),
              ),
              SettingsToggleTile(
                icon: Icons.notifications_none_rounded,
                title: 'Anniversary reminders',
                subtitle: "Notify on ' met one year ago '",
                value: settings.anniversaryReminders,
                onChanged: (v) => onToggle('anniversaryReminders', v),
                isLast: true,
              ),
            ],
          ),
          const SizedBox(height: 20),
          const SectionHeader(title: 'Permissions'),
          const SizedBox(height: 10),
          SettingsCard(
            children: [
              SettingsNavTile(
                icon: Icons.warning_amber_rounded,
                title: 'Access permission required',
                subtitle: 'Location & Native contact permissions',
                isLast: true,
                onTap: () => showPermissionPrompts(context, ref, markPrompted: false),
              ),
            ],
          ),
          const SizedBox(height: 40),
          const Center(
            child: Text(
              'Version: 1.4.6',
              style: TextStyle(
                fontFamily: 'SF Pro Display',
                fontSize: 13,
                fontWeight: FontWeight.w400,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

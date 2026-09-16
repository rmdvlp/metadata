import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metadata/core/bootstrap/auth_gate.dart';
import 'package:metadata/core/firebase/firebase_providers.dart';
import 'package:metadata/core/firebase/firebase_services.dart';
import 'package:metadata/core/loading/app_loading.dart';
import 'package:metadata/models/contact_model.dart';
import 'package:metadata/models/user_profile.dart';
import 'package:metadata/repositories/contact_repository.dart';
import 'package:metadata/screens/edit_profile_screen.dart';
import 'package:metadata/screens/permissions_required_screen.dart';
import 'package:metadata/screens/saved_contacts_screen.dart';
import 'package:metadata/screens/support_center_screen.dart';
import 'package:metadata/utils/app_colors.dart';
import 'package:metadata/widgets/app_back_button.dart';
import 'package:metadata/widgets/button.dart';
import 'package:metadata/widgets/contact_avatar.dart';
import 'package:metadata/widgets/settings_widgets.dart';
import 'package:skeletonizer/skeletonizer.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  Future<void> _confirmClearMetadata(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => _ClearMetadataDialog(),
    );

    if (confirmed != true || !context.mounted) return;

    AppLoading.show();
    try {
      await ref.read(contactRepositoryProvider).deleteAllContacts();
    } finally {
      AppLoading.dismiss();
    }

    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('All metadata cleared.')));
  }

  /// Photo, name and number all live on one screen now, so Profile itself
  /// is read-only: one way in, instead of three separate edit affordances
  /// that each opened something different.
  void _openEditProfile() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const EditProfileScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(userProfileStreamProvider);
    final contactsAsync = ref.watch(allContactsProvider);
    final profile = profileAsync.value;
    final settings = profile?.settings ?? UserSettings.defaults();

    // The profile doc's number is written once at sign-up, so it can be empty
    // for an account created another way — and `profile?.phoneNumber ?? ...`
    // only caught a null profile, not an empty field, which is what left this
    // line blank. The auth record is authoritative for a phone-auth account,
    // and is already there while the profile doc is still loading.
    final authPhoneNumber = ref
        .watch(firebaseAuthProvider)
        .currentUser
        ?.phoneNumber;
    final phoneNumber = (profile?.phoneNumber.isNotEmpty ?? false)
        ? profile!.phoneNumber
        : (authPhoneNumber ?? '');

    // Counted with the same predicates the tabs filter on, so tapping a card
    // never lands on a list with a different number of rows in it. All is not
    // captured + manual: contacts synced from the phone book are in neither.
    final contacts = contactsAsync.value ?? const <ContactModel>[];
    final allCount = contacts.length;
    final capturedCount = contacts.where((c) => c.isCaptured).length;
    final manualCount = contacts.where((c) => c.isManuallySaved).length;

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
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Row(
              children: [
                const AppBackButton(),
                const Expanded(
                  child: Text(
                    'Profile',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'SF Pro Display',
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 40),
              ],
            ),
            const SizedBox(height: 16),
            Skeletonizer(
              enabled: profileAsync.isLoading,
              child: Column(
                children: [
                  Center(
                    child: GestureDetector(
                      onTap: _openEditProfile,
                      child: ContactAvatar(
                        diameter: 110,
                        photoUrl: profile?.photoUrl,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // The one way into editing. It sits beside the name but
                  // covers the whole profile — photo, name and number are all
                  // on the screen it opens, which is why there is no longer a
                  // separate pen on the number or a camera badge on the
                  // avatar.
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text(
                          (profile?.displayName.isNotEmpty ?? false)
                              ? profile!.displayName
                              : 'Your Name',
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: 'SF Pro Display',
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: _openEditProfile,
                        child: const Padding(
                          padding: EdgeInsets.all(4),
                          child: Icon(
                            Icons.edit_outlined,
                            size: 18,
                            color: AppColors.primaryBlue,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  // No placeholder number here: a made-up one reads as the
                  // user's real one.
                  Text(
                    phoneNumber.isNotEmpty ? phoneNumber : 'No number yet',
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'SF Pro Display',
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: _StatCard(
                          value: '$allCount',
                          label: 'All Contact',
                          onTap: () => _openContacts(context, ContactsTab.all),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _StatCard(
                          value: '$capturedCount',
                          label: 'Captured',
                          onTap: () =>
                              _openContacts(context, ContactsTab.captured),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _StatCard(
                          value: '$manualCount',
                          label: 'Manual',
                          onTap: () =>
                              _openContacts(context, ContactsTab.manual),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
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
                // SettingsToggleTile(
                //   icon: Icons.dark_mode_outlined,
                //   title: 'Stealth mode',
                //   subtitle: 'Hide context from lock screen',
                //   value: settings.stealthMode,
                //   onChanged: (v) => onToggle('stealthMode', v),
                //   isLast: true,
                // ),
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
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const PermissionsRequiredScreen(),
                      ),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 20),
            const SectionHeader(title: 'Allow Permissions'),
            const SizedBox(height: 10),
            SettingsCard(
              children: [
                SettingsToggleTile(
                  icon: Icons.my_location_outlined,
                  title: 'Capture Context Automatically',
                  subtitle: 'Allow Capture Context Automatically',
                  value: settings.captureContextAutomatically,
                  onChanged: (v) => onToggle('captureContextAutomatically', v),
                ),
                SettingsToggleTile(
                  icon: Icons.shield_outlined,
                  title: 'Location Access',
                  subtitle: 'Allow to access location',
                  value: settings.locationAccess,
                  onChanged: (v) => onToggle('locationAccess', v),
                ),
                SettingsToggleTile(
                  icon: Icons.devices_outlined,
                  title: 'Contacts Access',
                  subtitle: 'Allow for contact access',
                  value: settings.contactsAccess,
                  onChanged: (v) => onToggle('contactsAccess', v),
                ),
                SettingsToggleTile(
                  icon: Icons.dark_mode_outlined,
                  title: 'Share Metadata',
                  subtitle: 'Allow to share metadata',
                  value: settings.shareMetadata,
                  onChanged: (v) => onToggle('shareMetadata', v),
                  isLast: true,
                ),
              ],
            ),
            const SizedBox(height: 20),
            const SectionHeader(title: 'Support'),
            const SizedBox(height: 10),
            SettingsCard(
              children: [
                SettingsNavTile(
                  icon: Icons.help_outline_rounded,
                  title: 'Support Center',
                  subtitle: 'Solution of all question',
                  isLast: true,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const SupportCenterScreen(),
                      ),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 28),
            Center(
              child: TextButton(
                onPressed: () => _confirmClearMetadata(context, ref),
                child: const Text(
                  'Clear All Metadata',
                  style: TextStyle(
                    fontFamily: 'SF Pro Display',
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.redAccent,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ClearMetadataDialog extends StatefulWidget {
  @override
  State<_ClearMetadataDialog> createState() => _ClearMetadataDialogState();
}

class _ClearMetadataDialogState extends State<_ClearMetadataDialog> {
  final TextEditingController _controller = TextEditingController();
  bool _canConfirm = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final matches = _controller.text == 'DATA';
      if (matches != _canConfirm) setState(() => _canConfirm = matches);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Confirmation',
              style: TextStyle(
                fontFamily: 'SF Pro Display',
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            RichText(
              textAlign: TextAlign.center,
              text: const TextSpan(
                style: TextStyle(
                  fontFamily: 'SF Pro Display',
                  fontSize: 14,
                  color: AppColors.textSecondary,
                ),
                children: [
                  TextSpan(text: 'Enter '),
                  TextSpan(
                    text: 'DATA',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Colors.redAccent,
                    ),
                  ),
                  TextSpan(text: ' in caps letter to clear metadata'),
                ],
              ),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _controller,
              textAlign: TextAlign.center,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                hintText: 'DATA',
                hintStyle: const TextStyle(color: AppColors.textSecondary),
                filled: true,
                fillColor: AppColors.mutedGray,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: CustomButton(
                label: 'Clear All Metadata',
                onPressed: _canConfirm
                    ? () => Navigator.of(context).pop(true)
                    : null,
                color: Colors.redAccent,
                height: 48,
              ),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text(
                'Cancel',
                style: TextStyle(
                  fontFamily: 'SF Pro Display',
                  fontWeight: FontWeight.w600,
                  color: AppColors.primaryBlue,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Opens Your Contacts on [tab].
void _openContacts(BuildContext context, ContactsTab tab) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => SavedContactsScreen(initialTab: tab),
    ),
  );
}

/// One of Profile's three contact counts. Tapping opens Your Contacts on the
/// tab that lists exactly the contacts it counted.
class _StatCard extends StatelessWidget {
  final String value;
  final String label;
  final VoidCallback onTap;

  const _StatCard({
    required this.value,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.mutedGray,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: const TextStyle(
                fontFamily: 'SF Pro Display',
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(
                fontFamily: 'SF Pro Display',
                fontSize: 12,
                fontWeight: FontWeight.w400,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

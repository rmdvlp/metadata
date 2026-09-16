import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:location/location.dart';
import 'package:metadata/core/permissions/permission_prompt_flow.dart';
import 'package:metadata/repositories/device_contacts_service.dart';
import 'package:metadata/repositories/incoming_call_service.dart';
import 'package:metadata/utils/app_colors.dart';
import 'package:metadata/widgets/app_back_button.dart';
import 'package:metadata/widgets/button.dart';

/// "Context ID Permissions" screen reached from Profile > "Access
/// permission required" — shows each permission the app relies on and
/// whether it's currently allowed, instead of just re-showing the ask
/// sheets with no visibility into current grant state.
class PermissionsRequiredScreen extends ConsumerStatefulWidget {
  const PermissionsRequiredScreen({super.key});

  @override
  ConsumerState<PermissionsRequiredScreen> createState() =>
      _PermissionsRequiredScreenState();
}

class _PermissionsRequiredScreenState
    extends ConsumerState<PermissionsRequiredScreen> with WidgetsBindingObserver {
  bool _locationGranted = false;
  bool _contactsGranted = false;
  bool _callsGranted = false;
  bool _isLoading = true;
  bool _isRequesting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshStatus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Catches the user granting a permission from the OS Settings app and
    // coming back — not just from our own in-app "Allow ..." sheets.
    if (state == AppLifecycleState.resumed) _refreshStatus();
  }

  Future<void> _refreshStatus() async {
    final locationStatus = await Location().hasPermission();
    final contactsGranted = await ref.read(deviceContactsServiceProvider).hasPermission();
    final callsGranted = await ref.read(incomingCallServiceProvider).hasCallPermissions();
    if (!mounted) return;
    setState(() {
      _locationGranted = locationStatus == PermissionStatus.granted ||
          locationStatus == PermissionStatus.grantedLimited;
      _contactsGranted = contactsGranted;
      _callsGranted = callsGranted;
      _isLoading = false;
    });
  }

  Future<void> _grantPermissions() async {
    if (_isRequesting) return;
    setState(() => _isRequesting = true);
    try {
      await showPermissionPrompts(context, ref, markPrompted: false);
    } finally {
      if (mounted) setState(() => _isRequesting = false);
      await _refreshStatus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final allGranted = _locationGranted && _contactsGranted && _callsGranted;

    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'Context ID Permissions',
          style: TextStyle(
            fontFamily: 'SF Pro Display',
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        leading: const AppBackButton.appBar(),
        leadingWidth: AppBackButton.leadingWidth,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: const BoxDecoration(
                  color: AppColors.lightBlueFill,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: const Icon(Icons.lock_outline_rounded, color: AppColors.primaryBlue, size: 28),
              ),
              const SizedBox(height: 14),
              const Text(
                'To capture where and when you met',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'SF Pro Display',
                  fontSize: 14,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 24),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Context ID Required',
                  style: TextStyle(
                    fontFamily: 'SF Pro Display',
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              if (_isLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: CircularProgressIndicator(color: AppColors.primaryBlue),
                )
              else
                Column(
                  children: [
                    _PermissionRow(
                      icon: Icons.location_on_outlined,
                      title: 'Location Access',
                      subtitle: 'Allows us to know your location to enable personalized services.',
                      isGranted: _locationGranted,
                    ),
                    const SizedBox(height: 12),
                    _PermissionRow(
                      icon: Icons.contacts_outlined,
                      title: 'Contacts Access',
                      subtitle: 'Allows us to securely connect and manage contacts for identifying '
                          'communication and networking.',
                      isGranted: _contactsGranted,
                    ),
                    const SizedBox(height: 12),
                    _PermissionRow(
                      icon: Icons.call_outlined,
                      title: 'Call Detection',
                      subtitle: 'Shows contact details on incoming calls and lets outgoing calls '
                          'be placed directly from this app.',
                      isGranted: _callsGranted,
                    ),
                  ],
                ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: CustomButton(
                  label: allGranted ? 'All Permissions Granted' : 'Grant Permissions',
                  onPressed: allGranted || _isRequesting ? null : _grantPermissions,
                  isLoading: _isRequesting,
                  height: 52,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PermissionRow extends StatelessWidget {
  const _PermissionRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.isGranted,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool isGranted;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.mutedGray,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22, color: AppColors.primaryBlue),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontFamily: 'SF Pro Display',
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontFamily: 'SF Pro Display',
                    fontSize: 12,
                    color: AppColors.textSecondary,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(
            isGranted ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
            size: 20,
            color: isGranted ? Colors.green : AppColors.textSecondary,
          ),
        ],
      ),
    );
  }
}

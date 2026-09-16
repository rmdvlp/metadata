import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:location/location.dart';
import 'package:metadata/core/firebase/firebase_services.dart';
import 'package:metadata/repositories/device_contacts_service.dart';
import 'package:metadata/repositories/incoming_call_service.dart';
import 'package:metadata/widgets/permission_prompt_sheet.dart';

/// Shows the location-permission sheet, then the contacts-permission sheet,
/// then (Android only — iOS's CXCallObserver needs no runtime grant) the
/// call-detection sheet, then marks the profile as prompted. Used both for
/// the first-run prompt (Home screen) and for re-prompting later from
/// Settings/Profile.
Future<void> showPermissionPrompts(
  BuildContext context,
  WidgetRef ref, {
  bool markPrompted = true,
}) async {
  if (!context.mounted) return;
  await _showLocationSheet(context);

  if (!context.mounted) return;
  await _showContactsSheet(context, ref);

  if (Platform.isAndroid) {
    if (!context.mounted) return;
    await _showCallDetectionSheet(context, ref);
  }

  if (markPrompted) {
    await ref.read(userProfileServiceProvider).markPermissionsPrompted();
  }
}

Future<void> _showLocationSheet(BuildContext context) {
  return showDialog<void>(
    context: context,
    // Forces an explicit "Allow ..." or "Maybe Later" tap — a stray
    // tap-outside shouldn't silently skip a permission ask the user never
    // consciously saw or decided on.
    barrierDismissible: false,
    builder: (dialogContext) => PermissionPromptSheet(
      icon: Icons.location_on_rounded,
      title: 'Allow your Location',
      subtitle: "We'll use your location to capture where you met each contact.",
      buttonLabel: 'Allow Location',
      onAllow: () async {
        final location = Location();
        if (!await location.serviceEnabled()) {
          await location.requestService();
        }
        var status = await location.hasPermission();
        if (status == PermissionStatus.denied) {
          status = await location.requestPermission();
        }
      },
    ),
  );
}

Future<void> _showContactsSheet(BuildContext context, WidgetRef ref) {
  return showDialog<void>(
    context: context,
    // Forces an explicit "Allow ..." or "Maybe Later" tap — a stray
    // tap-outside shouldn't silently skip a permission ask the user never
    // consciously saw or decided on.
    barrierDismissible: false,
    builder: (dialogContext) => PermissionPromptSheet(
      icon: Icons.contacts_rounded,
      title: 'Allow your Contacts',
      subtitle: "We'll sync your phone contacts so you can save context against them.",
      buttonLabel: 'Allow Contacts',
      onAllow: () async {
        final deviceContacts = ref.read(deviceContactsServiceProvider);
        final granted = await deviceContacts.requestPermission();
        if (granted) {
          try {
            await deviceContacts
                .syncDeviceContactsToFirestore()
                .timeout(const Duration(seconds: 45));
          } catch (_) {
            // Non-fatal: user can still add contacts manually.
          }
        }
      },
    ),
  );
}

Future<void> _showCallDetectionSheet(BuildContext context, WidgetRef ref) {
  return showDialog<void>(
    context: context,
    // Forces an explicit "Allow ..." or "Maybe Later" tap — a stray
    // tap-outside shouldn't silently skip a permission ask the user never
    // consciously saw or decided on.
    barrierDismissible: false,
    builder: (dialogContext) => PermissionPromptSheet(
      icon: Icons.call_rounded,
      title: 'Enable Calling',
      subtitle:
          "We'll show your saved contact's details when they call and let you answer or decline "
          "from here, and place your outgoing calls directly instead of just opening the dialer.",
      buttonLabel: 'Allow Calls',
      onAllow: () async {
        await ref.read(incomingCallServiceProvider).requestPermissions();
      },
    ),
  );
}

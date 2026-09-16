import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metadata/core/loading/app_loading.dart';
import 'package:metadata/features/calling/data/voip_directory_datasource.dart';
import 'package:metadata/features/calling/models/call_exception.dart';
import 'package:metadata/features/calling/models/voip_user.dart';
import 'package:metadata/features/calling/services/call_coordinator.dart';
import 'package:metadata/features/calling/services/call_permission_service.dart';
import 'package:metadata/features/calling/controllers/call_controller.dart';
import 'package:metadata/models/contact_model.dart';

/// "Call this contact over the internet" — the in-app counterpart to
/// `initiateCall` in `call_flow_helper.dart`, which places a carrier call.
///
/// Both live at the same layer and are called the same way from a screen, so
/// a contact tile can offer either without the UI knowing how calling works.
/// This one never opens the dialer and never touches `tel:`.
Future<void> startVoipCallWithContact(
  BuildContext context,
  WidgetRef ref,
  ContactModel contact,
) async {
  AppLoading.show();
  VoipUser? user;
  try {
    user = await ref
        .read(voipDirectoryProvider)
        .resolveOne(contact.phoneNumber)
        .timeout(const Duration(seconds: 15));
  } on CallException catch (e) {
    AppLoading.dismiss();
    if (context.mounted) _showError(context, e.message);
    return;
  } catch (_) {
    AppLoading.dismiss();
    if (context.mounted) {
      _showError(context, const CallException(CallFailure.signalingUnavailable).message);
    }
    return;
  }
  AppLoading.dismiss();

  if (user == null) {
    if (context.mounted) {
      _showError(context, const CallException(CallFailure.notAnAppUser).message);
    }
    return;
  }

  if (!context.mounted) return;
  await startVoipCall(context, ref, user, displayName: contact.fullName);
}

/// Places a call to a known app user.
///
/// Shows the live-call screen through [CallCoordinator] rather than pushing a
/// route here, so outgoing and incoming calls share one route lifecycle and
/// the screen is removed by the same code path in both cases.
Future<void> startVoipCall(
  BuildContext context,
  WidgetRef ref,
  VoipUser receiver, {
  String? displayName,
}) async {
  final controller = ref.read(callControllerProvider);
  final coordinator = ref.read(callCoordinatorProvider);

  try {
    final callId = await controller.startCall(
      receiver: displayName == null
          ? receiver
          : VoipUser(
              uid: receiver.uid,
              displayName: displayName,
              photoUrl: receiver.photoUrl,
            ),
    );
    coordinator.showActiveCallScreen(callId);
  } on CallException catch (e) {
    if (!context.mounted) return;
    if (e.failure == CallFailure.microphonePermanentlyDenied) {
      await _promptOpenSettings(context, ref, e.message);
      return;
    }
    _showError(context, e.message);
  }
}

Future<void> _promptOpenSettings(
  BuildContext context,
  WidgetRef ref,
  String message,
) async {
  final open = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Microphone needed'),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Not now'),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Open Settings'),
        ),
      ],
    ),
  );
  if (open ?? false) {
    await ref.read(callPermissionServiceProvider).openSettings();
  }
}

void _showError(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

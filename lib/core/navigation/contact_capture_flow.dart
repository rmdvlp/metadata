import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metadata/core/bootstrap/auth_gate.dart';
import 'package:metadata/screens/capture_context.dart';
import 'package:metadata/screens/saved_contact_details_screen.dart';

/// Routes to the next screen after a contact is created/selected for
/// capture — the location/time auto-capture flow when the user's
/// "Metadata capture" setting is on (the default), or straight to the
/// contact's details, saved as a plain contact with no metadata, when
/// they've turned it off in Profile > Privacy.
void continueContactCaptureFlow(BuildContext context, WidgetRef ref, String contactId) {
  final metadataCaptureEnabled =
      ref.read(userProfileStreamProvider).value?.settings.metadataCapture ?? true;

  if (metadataCaptureEnabled) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => CaptureContextScreen(contactId: contactId)),
    );
  } else {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => SavedContactDetailsScreen(contactId: contactId)),
    );
  }
}

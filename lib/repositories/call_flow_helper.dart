import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metadata/core/loading/app_loading.dart';
import 'package:metadata/models/contact_model.dart';
import 'package:metadata/models/encounter_details.dart';
import 'package:metadata/models/notification_model.dart';
import 'package:metadata/models/timeline_entry.dart';
import 'package:metadata/repositories/call_log_repository.dart';
import 'package:metadata/repositories/contact_repository.dart';
import 'package:metadata/repositories/dialer_service.dart';
import 'package:metadata/repositories/incoming_call_service.dart';
import 'package:metadata/repositories/notification_repository.dart';

/// Shared "tap to call a contact" flow used by Home and the Saved Contact
/// Detail screen: logs the attempt, arms + shows the live CallingScreen via
/// [IncomingCallService] (so it reacts to the real connected/disconnected
/// phone-state broadcast — see `IncomingCallService.startOutgoingCall`),
/// then hands off to the native dialer to actually place the call.
Future<void> initiateCall(
  BuildContext context,
  WidgetRef ref,
  ContactModel contact, {
  List<TimelineEntry> timeline = const [],
}) async {
  AppLoading.show();
  // Handed to the call service so the entry written here can be completed with
  // the call's outcome and talk time when it ends, instead of the end of the
  // call adding a second row for the same call.
  String? callLogId;
  try {
    callLogId = await ref
        .read(callLogRepositoryProvider)
        .logCallAttempt(
          contactId: contact.id,
          calleeName: contact.fullName,
          calleePhone: contact.phoneNumber,
        )
        .timeout(const Duration(seconds: 15));
    // Records the call against the contact: it drives Home's "Recent
    // Contacts" order (sorted by updatedAt) and resets the two-year
    // quarantine clock, which is the only thing that clears the red pill.
    // Skipped for ad-hoc dialer calls to numbers with no saved contact
    // (contact.id is empty).
    if (contact.id.isNotEmpty) {
      await ref
          .read(contactRepositoryProvider)
          .markContacted(contact.id)
          .timeout(const Duration(seconds: 15));
    }
    await ref
        .read(notificationRepositoryProvider)
        .create(
          AppNotification(
            id: '',
            type: NotificationType.outgoingCall,
            title: 'Outgoing call',
            body: 'You called ${contact.fullName}.',
            relatedContactId: contact.id,
            imageUrl: contact.photoUrl,
          ),
        )
        .timeout(const Duration(seconds: 15));
  } catch (_) {
    // Non-fatal: the call itself matters more than the log/notification entry.
  } finally {
    AppLoading.dismiss();
  }

  await ref
      .read(incomingCallServiceProvider)
      .startOutgoingCall(
        contact: contact,
        encounterDetails: EncounterDetails.fromContact(
          contact,
          timeline: timeline,
        ),
        callLogId: callLogId,
      );

  await ref.read(dialerServiceProvider).callNumber(contact.phoneNumber);
}

import 'package:metadata/models/contact_model.dart';
import 'package:metadata/models/timeline_entry.dart';
import 'package:metadata/utils/date_formatting.dart';

/// All the info shown inside a [CallingScreen]'s "Encounter Details" shutter.
class EncounterDetails {
  final String placeName;
  final String address;
  final String longitude;
  final String latitude;
  final String date;
  final String time;
  final String note;
  final List<TimelineEntry> timeline;

  /// Which saved contact this describes, so the sheet can offer that
  /// contact's Bank Chat. Empty for an unknown caller — there is no contact to
  /// store banking details against, and [BankChatButton] hides itself.
  final String contactId;
  final String contactName;

  const EncounterDetails({
    required this.placeName,
    required this.address,
    required this.longitude,
    required this.latitude,
    required this.date,
    required this.time,
    required this.note,
    this.timeline = const [],
    this.contactId = '',
    this.contactName = '',
  });

  factory EncounterDetails.fromContact(
    ContactModel contact, {
    List<TimelineEntry> timeline = const [],
  }) {
    final location = contact.location;
    final eventDate = contact.eventDate;
    return EncounterDetails(
      placeName: location?.placeName ?? location?.address ?? 'Unknown place',
      address: location?.address ?? 'No address captured',
      longitude: location != null ? '${location.lng.toStringAsFixed(4)}°' : '—',
      latitude: location != null ? '${location.lat.toStringAsFixed(4)}°' : '—',
      date: eventDate != null ? formatShortDate(eventDate) : '—',
      time: eventDate != null ? formatTime(eventDate) : '—',
      note: (contact.notes == null || contact.notes!.isEmpty)
          ? 'No notes added yet.'
          : contact.notes!,
      timeline: timeline,
      contactId: contact.id,
      contactName: contact.fullName,
    );
  }

  /// Fallback used when an incoming call's number has no matching saved
  /// contact (or, on iOS, when the number is unavailable at all — CXCall
  /// never exposes one to 3rd-party observers).
  factory EncounterDetails.unknownCaller() {
    return const EncounterDetails(
      placeName: 'Unknown caller',
      address: 'No saved contact for this number',
      longitude: '—',
      latitude: '—',
      date: '—',
      time: '—',
      note: 'No notes added yet.',
    );
  }
}

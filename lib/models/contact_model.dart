import 'package:cloud_firestore/cloud_firestore.dart';

enum ContactSource {
  manual,
  device;

  static ContactSource fromValue(String? value) {
    return ContactSource.values.firstWhere(
      (s) => s.name == value,
      orElse: () => ContactSource.manual,
    );
  }
}

class ContactLocation {
  final double lat;
  final double lng;
  final String? address;
  final String? placeName;

  const ContactLocation({
    required this.lat,
    required this.lng,
    this.address,
    this.placeName,
  });

  factory ContactLocation.fromMap(Map<String, dynamic> map) => ContactLocation(
    lat: (map['lat'] as num?)?.toDouble() ?? 0,
    lng: (map['lng'] as num?)?.toDouble() ?? 0,
    address: map['address'] as String?,
    placeName: map['placeName'] as String?,
  );

  Map<String, dynamic> toMap() => {
    'lat': lat,
    'lng': lng,
    'address': address,
    'placeName': placeName,
  };
}

class ContactModel {
  final String id;
  final String fullName;
  final String phoneNumber;
  final String? notes;
  final String? photoUrl;
  final ContactSource source;
  final String? deviceContactId;
  final String? role;
  final ContactLocation? location;
  final DateTime? eventDate;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final bool isFavorite;

  /// Suppresses this contact's incoming-call card and notification. The
  /// carrier call still rings the handset — this app is not the default
  /// dialer and cannot intercept the network.
  final bool isBlocked;

  /// When the user and this contact last actually communicated — a call
  /// placed to them, or one received from them. Written by the call flows
  /// rather than by any edit, which is what makes it usable as the
  /// quarantine clock (see `lib/utils/contact_quarantine.dart`).
  ///
  /// Null on every contact saved before this field existed, and on one that
  /// has never been called. `lastInteractionAt` falls back to [updatedAt]
  /// then [createdAt] for those.
  final DateTime? lastContactedAt;

  /// How the contact was created: true when it came through "Capture Context
  /// Automatically", false when it was saved with the plain "Save" button.
  /// This records provenance and drives the Captured/Manual tabs — it does not
  /// limit what can be edited later, since any contact can gain a location,
  /// notes and timeline entries.
  final bool capturesContext;

  const ContactModel({
    required this.id,
    required this.fullName,
    required this.phoneNumber,
    this.notes,
    this.photoUrl,
    this.source = ContactSource.manual,
    this.deviceContactId,
    this.role,
    this.location,
    this.eventDate,
    this.createdAt,
    this.updatedAt,
    this.isFavorite = false,
    this.isBlocked = false,
    this.lastContactedAt,
    this.capturesContext = true,
  });

  /// Saved through "Capture Context Automatically" — the Captured tab.
  ///
  /// Contacts synced from the phone book are excluded: they were never saved
  /// by the user through either button, so they belong only under All
  /// Contacts. (They carry the `capturesContext` default, which is why the
  /// source check is needed here.)
  bool get isCaptured => source == ContactSource.manual && capturesContext;

  /// Saved with the plain "Save" button — the Manual tab.
  bool get isManuallySaved =>
      source == ContactSource.manual && !capturesContext;

  factory ContactModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? <String, dynamic>{};
    final locationMap = data['location'] as Map<String, dynamic>?;
    return ContactModel(
      id: doc.id,
      fullName: data['fullName'] as String? ?? '',
      phoneNumber: data['phoneNumber'] as String? ?? '',
      notes: data['notes'] as String?,
      photoUrl: data['photoUrl'] as String?,
      source: ContactSource.fromValue(data['source'] as String?),
      deviceContactId: data['deviceContactId'] as String?,
      role: data['role'] as String?,
      location: locationMap != null
          ? ContactLocation.fromMap(locationMap)
          : null,
      eventDate: (data['eventDate'] as Timestamp?)?.toDate(),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
      isFavorite: data['isFavorite'] as bool? ?? false,
      // Absent on docs written before blocking existed — those are unblocked.
      isBlocked: data['isBlocked'] as bool? ?? false,
      lastContactedAt: (data['lastContactedAt'] as Timestamp?)?.toDate(),
      // Absent on docs written before "Save Manually" stopped capturing
      // context. Every contact back then went through the capture flow, so
      // defaulting to true keeps their sections exactly as they were.
      capturesContext: data['capturesContext'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toCreateMap() => {
    'fullName': fullName,
    'phoneNumber': phoneNumber,
    'notes': notes,
    'photoUrl': photoUrl,
    'source': source.name,
    'deviceContactId': deviceContactId,
    'role': role,
    'location': location?.toMap(),
    'eventDate': eventDate != null ? Timestamp.fromDate(eventDate!) : null,
    'createdAt': FieldValue.serverTimestamp(),
    'updatedAt': FieldValue.serverTimestamp(),
    'isFavorite': isFavorite,
    'isBlocked': isBlocked,
    'lastContactedAt': lastContactedAt != null
        ? Timestamp.fromDate(lastContactedAt!)
        : null,
    'capturesContext': capturesContext,
  };

  ContactModel copyWith({
    String? fullName,
    String? phoneNumber,
    String? notes,
    String? photoUrl,
    ContactSource? source,
    String? role,
    ContactLocation? location,
    DateTime? eventDate,
    bool? isFavorite,
    bool? isBlocked,
    DateTime? lastContactedAt,
    bool? capturesContext,
  }) {
    return ContactModel(
      id: id,
      fullName: fullName ?? this.fullName,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      notes: notes ?? this.notes,
      photoUrl: photoUrl ?? this.photoUrl,
      source: source ?? this.source,
      deviceContactId: deviceContactId,
      role: role ?? this.role,
      location: location ?? this.location,
      eventDate: eventDate ?? this.eventDate,
      createdAt: createdAt,
      updatedAt: updatedAt,
      isFavorite: isFavorite ?? this.isFavorite,
      isBlocked: isBlocked ?? this.isBlocked,
      lastContactedAt: lastContactedAt ?? this.lastContactedAt,
      capturesContext: capturesContext ?? this.capturesContext,
    );
  }
}

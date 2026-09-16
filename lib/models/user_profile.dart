import 'package:cloud_firestore/cloud_firestore.dart';

class UserSettings {
  final bool metadataCapture;
  final bool endToEndEncryption;
  final bool stealthMode;
  final bool incomingCallCard;
  final bool anniversaryReminders;
  final bool captureContextAutomatically;
  final bool locationAccess;
  final bool contactsAccess;
  final bool shareMetadata;

  const UserSettings({
    required this.metadataCapture,
    required this.endToEndEncryption,
    required this.stealthMode,
    required this.incomingCallCard,
    required this.anniversaryReminders,
    required this.captureContextAutomatically,
    required this.locationAccess,
    required this.contactsAccess,
    required this.shareMetadata,
  });

  factory UserSettings.defaults() => const UserSettings(
    metadataCapture: true,
    endToEndEncryption: true,
    stealthMode: false,
    incomingCallCard: true,
    anniversaryReminders: true,
    captureContextAutomatically: true,
    locationAccess: true,
    contactsAccess: true,
    shareMetadata: false,
  );

  factory UserSettings.fromMap(Map<String, dynamic>? map) {
    if (map == null) return UserSettings.defaults();
    final defaults = UserSettings.defaults();
    return UserSettings(
      metadataCapture: map['metadataCapture'] as bool? ?? defaults.metadataCapture,
      endToEndEncryption: map['endToEndEncryption'] as bool? ?? defaults.endToEndEncryption,
      stealthMode: map['stealthMode'] as bool? ?? defaults.stealthMode,
      incomingCallCard: map['incomingCallCard'] as bool? ?? defaults.incomingCallCard,
      anniversaryReminders: map['anniversaryReminders'] as bool? ?? defaults.anniversaryReminders,
      captureContextAutomatically: map['captureContextAutomatically'] as bool? ?? defaults.captureContextAutomatically,
      locationAccess: map['locationAccess'] as bool? ?? defaults.locationAccess,
      contactsAccess: map['contactsAccess'] as bool? ?? defaults.contactsAccess,
      shareMetadata: map['shareMetadata'] as bool? ?? defaults.shareMetadata,
    );
  }

  Map<String, dynamic> toMap() => {
    'metadataCapture': metadataCapture,
    'endToEndEncryption': endToEndEncryption,
    'stealthMode': stealthMode,
    'incomingCallCard': incomingCallCard,
    'anniversaryReminders': anniversaryReminders,
    'captureContextAutomatically': captureContextAutomatically,
    'locationAccess': locationAccess,
    'contactsAccess': contactsAccess,
    'shareMetadata': shareMetadata,
  };

  UserSettings copyWith({
    bool? metadataCapture,
    bool? endToEndEncryption,
    bool? stealthMode,
    bool? incomingCallCard,
    bool? anniversaryReminders,
    bool? captureContextAutomatically,
    bool? locationAccess,
    bool? contactsAccess,
    bool? shareMetadata,
  }) {
    return UserSettings(
      metadataCapture: metadataCapture ?? this.metadataCapture,
      endToEndEncryption: endToEndEncryption ?? this.endToEndEncryption,
      stealthMode: stealthMode ?? this.stealthMode,
      incomingCallCard: incomingCallCard ?? this.incomingCallCard,
      anniversaryReminders: anniversaryReminders ?? this.anniversaryReminders,
      captureContextAutomatically: captureContextAutomatically ?? this.captureContextAutomatically,
      locationAccess: locationAccess ?? this.locationAccess,
      contactsAccess: contactsAccess ?? this.contactsAccess,
      shareMetadata: shareMetadata ?? this.shareMetadata,
    );
  }
}

class UserProfile {
  final String uid;
  final String phoneNumber;
  final String displayName;
  final String? photoUrl;
  final DateTime? createdAt;
  final DateTime? lastActiveAt;
  final String? fcmToken;
  final bool permissionsPrompted;
  final UserSettings settings;

  const UserProfile({
    required this.uid,
    required this.phoneNumber,
    required this.displayName,
    this.photoUrl,
    this.createdAt,
    this.lastActiveAt,
    this.fcmToken,
    required this.permissionsPrompted,
    required this.settings,
  });

  factory UserProfile.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    return UserProfile(
      uid: doc.id,
      phoneNumber: data['phoneNumber'] as String? ?? '',
      displayName: data['displayName'] as String? ?? '',
      photoUrl: data['photoUrl'] as String?,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      lastActiveAt: (data['lastActiveAt'] as Timestamp?)?.toDate(),
      fcmToken: data['fcmToken'] as String?,
      permissionsPrompted: data['permissionsPrompted'] as bool? ?? false,
      settings: UserSettings.fromMap(data['settings'] as Map<String, dynamic>?),
    );
  }

  Map<String, dynamic> toInitialFirestoreMap({required String phoneNumber}) => {
    'uid': uid,
    'phoneNumber': phoneNumber,
    'displayName': '',
    'permissionsPrompted': false,
    'settings': UserSettings.defaults().toMap(),
    'createdAt': FieldValue.serverTimestamp(),
    'lastActiveAt': FieldValue.serverTimestamp(),
  };
}

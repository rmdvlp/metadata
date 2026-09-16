/// Another app user who can be reached over in-app VoIP.
///
/// Resolved from a phone number via the `resolveVoipUsers` callable, never by
/// reading `users/{uid}` directly — the security rules keep user documents
/// private, and a client-readable phone directory would be trivially
/// enumerable.
class VoipUser {
  final String uid;
  final String displayName;
  final String? photoUrl;

  const VoipUser({
    required this.uid,
    required this.displayName,
    this.photoUrl,
  });

  factory VoipUser.fromMap(Map<String, dynamic> map) {
    return VoipUser(
      uid: map['uid'] as String? ?? '',
      displayName: (map['displayName'] as String?)?.trim().isNotEmpty == true
          ? (map['displayName'] as String).trim()
          : 'Unknown',
      photoUrl: map['photoUrl'] as String?,
    );
  }
}

/// One signed-in installation of the app. A user can be signed in on several
/// devices at once, so incoming-call pushes fan out over every entry rather
/// than a single `fcmToken` field on the user document.
class UserDevice {
  final String deviceId;
  final String token;

  /// APNs PushKit token. iOS only, and distinct from [token] — FCM cannot
  /// deliver PushKit pushes, so terminated-app calls on iOS go through APNs
  /// directly using this.
  final String? voipToken;
  final String platform;
  final String appVersion;
  final String? deviceModel;

  const UserDevice({
    required this.deviceId,
    required this.token,
    this.voipToken,
    required this.platform,
    required this.appVersion,
    this.deviceModel,
  });

  Map<String, dynamic> toMap() => {
    'token': token,
    if (voipToken != null) 'voipToken': voipToken,
    'platform': platform,
    'appVersion': appVersion,
    'deviceModel': deviceModel,
  };
}

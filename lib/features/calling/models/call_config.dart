/// Tunables for the calling feature, kept in one place so timeouts and ICE
/// configuration are not scattered as magic numbers across services.
class CallConfig {
  const CallConfig._();

  /// How long the caller waits for an answer before the call is marked
  /// missed. The backend sweep uses a slightly longer window (60s) so the
  /// caller's own device is normally the one that resolves the call, and the
  /// server only acts as a backstop for a killed app.
  static const Duration ringTimeout = Duration(seconds: 30);

  /// How long we allow SDP/ICE negotiation to take after the call is
  /// answered before declaring it failed.
  static const Duration connectTimeout = Duration(seconds: 30);

  /// Grace period after ICE reports `disconnected` before we tear the call
  /// down. ICE routinely blips on network handover (Wi-Fi -> cellular) and
  /// recovers on its own, so hanging up immediately would be wrong.
  static const Duration iceDisconnectGrace = Duration(seconds: 12);

  /// Upper bound on how long a device keeps a WebRTC session alive without
  /// ever reaching `connected`.
  static const Duration maxNegotiationLifetime = Duration(minutes: 2);

  /// STUN-only by default: enough for the large majority of consumer NATs
  /// and requires no infrastructure. Symmetric NATs and most carrier-grade
  /// NAT deployments will fail without TURN, which is why [turnServers]
  /// exists as a first-class extension point rather than an afterthought.
  static const List<Map<String, dynamic>> stunServers = [
    {
      'urls': [
        'stun:stun.l.google.com:19302',
        'stun:stun1.l.google.com:19302',
      ],
    },
  ];

  /// TURN credentials are intentionally NOT compiled into the app. Long-lived
  /// TURN credentials shipped in a binary are extractable and get abused as
  /// open relays. Populate this at runtime from short-lived, server-issued
  /// credentials (see `CallService.configureTurnServers`).
  static List<Map<String, dynamic>> turnServers = const [];

  static Map<String, dynamic> get iceConfiguration => {
    'iceServers': [...stunServers, ...turnServers],
    // Trickle ICE: candidates are published to Firestore as they are
    // gathered rather than waiting for gathering to complete, which is what
    // keeps time-to-audio low.
    'sdpSemantics': 'unified-plan',
    'iceCandidatePoolSize': 2,
  };

  /// Audio-only: no camera is ever requested, so the app never needs (or
  /// asks for) camera permission for calling.
  static const Map<String, dynamic> audioOnlyConstraints = {
    'audio': {
      'echoCancellation': true,
      'noiseSuppression': true,
      'autoGainControl': true,
    },
    'video': false,
  };
}

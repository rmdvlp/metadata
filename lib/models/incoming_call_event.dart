import 'dart:io';

enum IncomingCallState {
  ringing,
  connected,
  disconnected;

  static IncomingCallState fromValue(String? value) {
    return IncomingCallState.values.firstWhere(
      (s) => s.name == value,
      orElse: () => IncomingCallState.disconnected,
    );
  }
}

/// Unified shape for a native call-state event, regardless of whether it
/// came from Android's telecom/CallScreeningService bridge or iOS's
/// CXCallObserver bridge.
///
/// `canAnswer`/`canDecline` are derived from the platform, not from any
/// per-call native signal: Android can genuinely act on the real call,
/// iOS can only ever observe it (see CallObserverPlugin.swift — CXCall
/// exposes no phone number and no answer/end control to 3rd-party apps).
class IncomingCallEvent {
  final IncomingCallState state;
  final String? phoneNumber;
  final bool isOutgoing;
  final DateTime timestamp;

  /// Talk time on a [IncomingCallState.disconnected] event: measured natively
  /// between the off-hook and idle transitions, so it survives the app being
  /// backgrounded for the whole call. 0 on every other state, and on a call
  /// that never connected.
  final int durationSeconds;

  const IncomingCallEvent({
    required this.state,
    required this.phoneNumber,
    required this.isOutgoing,
    required this.timestamp,
    this.durationSeconds = 0,
  });

  bool get canAnswer => Platform.isAndroid && state == IncomingCallState.ringing;
  bool get canDecline => Platform.isAndroid && state == IncomingCallState.ringing;

  factory IncomingCallEvent.fromMap(Map<dynamic, dynamic> map) {
    final timestampMs = map['timestampMs'] as int?;
    return IncomingCallEvent(
      state: IncomingCallState.fromValue(map['state'] as String?),
      phoneNumber: map['phoneNumber'] as String?,
      isOutgoing: map['isOutgoing'] as bool? ?? false,
      timestamp: timestampMs != null
          ? DateTime.fromMillisecondsSinceEpoch(timestampMs)
          : DateTime.now(),
      durationSeconds: (map['durationSeconds'] as num?)?.toInt() ?? 0,
    );
  }
}

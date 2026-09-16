import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metadata/features/calling/models/call_exception.dart';
import 'package:metadata/features/calling/models/call_model.dart';
import 'package:metadata/features/calling/models/voip_user.dart';
import 'package:metadata/features/calling/services/call_service.dart';

/// Live view of the current call for the UI.
///
/// The screens are `ConsumerWidget`s that watch this and nothing else — they
/// never touch Firestore, WebRTC or the platform channel. That keeps the call
/// screens dumb enough to be rendered in a widget test from a hand-built
/// snapshot.
final callSessionProvider =
    NotifierProvider<CallSessionNotifier, CallSessionSnapshot>(CallSessionNotifier.new);

class CallSessionNotifier extends Notifier<CallSessionSnapshot> {
  StreamSubscription<CallSessionSnapshot>? _sub;

  @override
  CallSessionSnapshot build() {
    final service = ref.watch(callServiceProvider);
    _sub = service.session.listen((snapshot) => state = snapshot);
    ref.onDispose(() => _sub?.cancel());
    return service.current;
  }
}

/// Imperative call actions for the UI.
///
/// Every method swallows nothing: [CallException]s propagate so the screen
/// can show [CallException.message], and unexpected errors are normalised
/// into a generic failure rather than leaking a Firebase or WebRTC string
/// into the interface.
final callControllerProvider = Provider<CallController>((ref) {
  return CallController(ref.watch(callServiceProvider));
});

class CallController {
  CallController(this._service);

  final CallService _service;

  String? get currentUserId => _service.currentUserId;
  bool get isBusy => _service.isBusy;
  String? get activeCallId => _service.activeCallId;

  Future<String> startCall({required VoipUser receiver, String? callerName}) {
    return _guard(() => _service.startCall(receiver: receiver, callerNameOverride: callerName));
  }

  Future<void> accept(String callId) => _guard(() => _service.acceptCall(callId));

  Future<void> reject(String callId) => _guard(() => _service.rejectCall(callId));

  Future<void> cancel(String callId) => _guard(() => _service.cancelCall(callId));

  Future<void> end(String callId) => _guard(() => _service.endCall(callId));

  Future<void> hangUp() => _guard(_service.hangUpCurrent);

  Future<void> toggleMute() => _guard(_service.toggleMute);

  Future<void> toggleSpeaker() => _guard(_service.toggleSpeaker);

  Stream<CallModel?> watchCall(String callId) => _service.watchCall(callId);

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on CallException {
      rethrow;
    } catch (e) {
      throw CallException(CallFailure.unknown, cause: e);
    }
  }
}

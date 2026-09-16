import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metadata/core/firebase/fcm_token.dart';
import 'package:metadata/core/firebase/firebase_providers.dart';
import 'package:metadata/core/logging/call_logger.dart';
import 'package:metadata/core/navigation/app_navigator.dart';
import 'package:metadata/features/calling/data/device_registry_datasource.dart';
import 'package:metadata/features/calling/models/call_model.dart';
import 'package:metadata/features/calling/models/call_status.dart';
import 'package:metadata/features/calling/presentation/voip_active_call_screen.dart';
import 'package:metadata/features/calling/presentation/voip_incoming_call_screen.dart';
import 'package:metadata/features/calling/services/call_service.dart';
import 'package:metadata/features/calling/services/voip_platform_service.dart';

final callCoordinatorProvider = Provider<CallCoordinator>((ref) {
  final coordinator = CallCoordinator(
    calls: ref.watch(callServiceProvider),
    platform: ref.watch(voipPlatformServiceProvider),
    devices: ref.watch(deviceRegistryProvider),
    messaging: ref.watch(firebaseMessagingProvider),
  );
  ref.onDispose(coordinator.dispose);
  return coordinator;
});

/// The one place that decides when a call screen appears and disappears.
///
/// Incoming calls can arrive through three completely different doors — a
/// Firestore snapshot (app in the foreground), an FCM data message (app
/// backgrounded), or a native CallKit/notification event (app terminated) —
/// and the same call frequently arrives through more than one of them at
/// once. Centralising the decision here, keyed by `callId`, is what prevents
/// two incoming-call screens stacking on top of each other.
///
/// It deliberately does not change the app's navigation architecture: it
/// pushes onto the existing [rootNavigatorKey] exactly like the current
/// cellular `IncomingCallService` does.
class CallCoordinator {
  CallCoordinator({
    required CallService calls,
    required VoipPlatformService platform,
    required DeviceRegistryDataSource devices,
    required FirebaseMessaging messaging,
  }) : _calls = calls,
       _platform = platform,
       _devices = devices,
       _messaging = messaging;

  final CallService _calls;
  final VoipPlatformService _platform;
  final DeviceRegistryDataSource _devices;
  final FirebaseMessaging _messaging;

  StreamSubscription<List<CallModel>>? _incomingSub;
  StreamSubscription<VoipNativeEvent>? _nativeSub;
  StreamSubscription<String>? _tokenSub;
  StreamSubscription<CallSessionSnapshot>? _sessionSub;

  /// Calls this device has already reacted to. Without it, the Firestore
  /// listener and an FCM push describing the same call would each try to
  /// present a screen.
  final Set<String> _handledCallIds = {};

  String? _presentedCallId;
  Route<dynamic>? _callRoute;
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    await _platform.initialize();
    _nativeSub = _platform.events.listen(_onNativeEvent);

    await _registerThisDevice();
    _tokenSub = _messaging.onTokenRefresh.listen((token) async {
      await _devices.registerDevice(fcmToken: token);
    });

    _incomingSub = _calls.incomingCalls().listen(_onIncomingCalls);

    // Mirrors the terminal status back into navigation: whichever side ended
    // the call, both devices leave the call screen.
    _sessionSub = _calls.session.listen(_onSessionChanged);

    await _drainPendingNativeAction();
  }

  Future<void> _registerThisDevice() async {
    try {
      final fcmToken = await resolveFcmToken(_messaging);
      final voipToken = await _platform.getVoipToken();
      if (fcmToken != null) {
        await _devices.registerDevice(fcmToken: fcmToken, voipToken: voipToken);
      } else if (voipToken != null) {
        await _devices.updateVoipToken(voipToken);
      }
    } catch (e) {
      CallLogger.log(CallLogEvent.nativeEvent, error: e);
    }
  }

  /// The app may have been launched cold by the user answering in CallKit or
  /// in the full-screen notification. That tap happened before any Dart
  /// listener existed, so the native side parks it and we drain it here.
  Future<void> _drainPendingNativeAction() async {
    final pending = await _platform.consumePendingCallAction();
    if (pending == null) return;
    final callId = pending['callId'];
    final action = pending['action'];
    if (callId == null) return;
    if (action == 'answer') {
      await _acceptCall(callId);
    } else if (action == 'decline') {
      await _calls.rejectCall(callId);
    }
  }

  // ---------------------------------------------------------------------
  // Inbound routes
  // ---------------------------------------------------------------------

  void _onIncomingCalls(List<CallModel> calls) {
    for (final call in calls) {
      unawaited(_presentIncomingCall(call));
    }
  }

  /// Entry point for FCM data messages. Wired in from [MessagingService] so
  /// the app keeps exactly one `FirebaseMessaging.onMessage` subscription.
  Future<void> handleRemoteMessage(RemoteMessage message) async {
    final data = message.data;
    final type = data['type'] as String?;
    final callId = data['callId'] as String?;
    if (callId == null) return;

    CallLogger.log(
      CallLogEvent.pushReceived,
      callId: callId,
      data: {'type': type},
    );

    if (type == 'call_ended') {
      await _dismissCallUi(callId);
      return;
    }
    if (type != 'incoming_call') return;

    // Trust the document, not the push. Push payloads are routed by the
    // backend but the authoritative state — including whether this call is
    // still ringing — only exists in Firestore.
    final call = await _calls.getCall(callId);
    if (call == null) return;
    await _presentIncomingCall(call);
  }

  Future<void> _onNativeEvent(VoipNativeEvent event) async {
    if (event.voipToken != null) {
      await _devices.updateVoipToken(event.voipToken!);
      return;
    }

    final push = event.incomingPush;
    if (push != null) {
      final callId = push['callId'];
      if (callId == null) return;
      if (push['ended'] == 'true') {
        await _dismissCallUi(callId);
        return;
      }
      final call = await _calls.getCall(callId);
      if (call != null) await _presentIncomingCall(call);
      return;
    }

    final callId = event.callId;
    switch (event.action) {
      case VoipNativeAction.answer:
        if (callId != null) await _acceptCall(callId);
        break;
      case VoipNativeAction.decline:
        if (callId != null) await _calls.rejectCall(callId);
        break;
      case VoipNativeAction.end:
        if (callId != null) await _calls.endCall(callId);
        break;
      case VoipNativeAction.mute:
        await _calls.setMuted(true);
        break;
      case VoipNativeAction.unmute:
        await _calls.setMuted(false);
        break;
      case null:
        break;
    }
  }

  // ---------------------------------------------------------------------
  // Presentation
  // ---------------------------------------------------------------------

  Future<void> _presentIncomingCall(CallModel call) async {
    if (call.status.isTerminal) return;
    if (_handledCallIds.contains(call.callId)) return;
    _handledCallIds.add(call.callId);

    // Already talking to someone else: decline with a reason instead of
    // silently dropping the call, so the caller sees "busy" rather than
    // ringing out.
    if (_calls.isBusy || await _calls.isBusyOnAnyDevice()) {
      CallLogger.log(CallLogEvent.callBusy, callId: call.callId);
      await _calls.rejectCall(call.callId, reason: CallEndReason.busy);
      await _platform.endCall(call.callId);
      return;
    }

    await _platform.reportIncomingCall(
      callId: call.callId,
      callerName: call.callerName,
      callerId: call.callerId,
    );

    CallLogger.log(CallLogEvent.callRinging, callId: call.callId);
    _push(VoipIncomingCallScreen(call: call), call.callId);
  }

  Future<void> _acceptCall(String callId) async {
    _handledCallIds.add(callId);
    try {
      await _calls.acceptCall(callId);
      _replaceWithActiveScreen(callId);
    } catch (e) {
      CallLogger.log(CallLogEvent.callFailed, callId: callId, error: e);
      await _dismissCallUi(callId);
    }
  }

  /// Pushes the live-call screen for a call this device has just placed or
  /// answered. Public so the outgoing-call flow can reuse the same route
  /// management and avoid a second, competing navigation path.
  void showActiveCallScreen(String callId) => _replaceWithActiveScreen(callId);

  void _replaceWithActiveScreen(String callId) {
    final navigator = rootNavigatorKey.currentState;
    if (navigator == null) return;
    final route = MaterialPageRoute<void>(
      builder: (_) => VoipActiveCallScreen(callId: callId),
      settings: RouteSettings(name: 'voip_active_call/$callId'),
    );
    final existing = _callRoute;
    if (existing != null && existing.isActive) {
      navigator.replace(oldRoute: existing, newRoute: route);
    } else {
      navigator.push(route);
    }
    _callRoute = route;
    _presentedCallId = callId;
  }

  void _push(Widget screen, String callId) {
    final navigator = rootNavigatorKey.currentState;
    if (navigator == null) return;
    final route = MaterialPageRoute<void>(
      builder: (_) => screen,
      settings: RouteSettings(name: 'voip_call/$callId'),
    );
    navigator.push(route);
    _callRoute = route;
    _presentedCallId = callId;
  }

  void _onSessionChanged(CallSessionSnapshot snapshot) {
    final call = snapshot.call;
    if (call == null) {
      // The service finished tearing down; make sure no call screen is left
      // stranded on top of the app.
      final presented = _presentedCallId;
      if (presented != null) unawaited(_dismissCallUi(presented));
      return;
    }
    if (call.status.isTerminal) {
      unawaited(_dismissCallUi(call.callId));
    }
  }

  /// Removes whichever call screen is showing and clears the native call UI.
  ///
  /// Uses the stored route rather than a bare `pop()` so it can never pop an
  /// unrelated screen the user navigated to in the meantime.
  Future<void> _dismissCallUi(String callId) async {
    await _platform.endCall(callId);
    await _platform.stopCallForegroundService();

    final navigator = rootNavigatorKey.currentState;
    final route = _callRoute;
    if (navigator != null && route != null && route.isActive) {
      navigator.removeRoute(route);
    }
    if (_presentedCallId == callId) {
      _callRoute = null;
      _presentedCallId = null;
    }

    // Keep the id in _handledCallIds so a late duplicate push cannot
    // resurrect the screen, but bound the set so a long session does not grow
    // it without limit.
    if (_handledCallIds.length > 200) {
      _handledCallIds.clear();
      _handledCallIds.add(callId);
    }
  }

  Future<void> dispose() async {
    await _incomingSub?.cancel();
    await _nativeSub?.cancel();
    await _tokenSub?.cancel();
    await _sessionSub?.cancel();
  }
}

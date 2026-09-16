import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metadata/core/firebase/local_notifications_service.dart';
import 'package:metadata/core/navigation/app_navigator.dart';
import 'package:metadata/models/call_log_model.dart';
import 'package:metadata/models/contact_model.dart';
import 'package:metadata/models/encounter_details.dart';
import 'package:metadata/models/incoming_call_event.dart';
import 'package:metadata/models/notification_model.dart';
import 'package:metadata/repositories/call_log_repository.dart';
import 'package:metadata/repositories/contact_repository.dart';
import 'package:metadata/repositories/dialer_service.dart';
import 'package:metadata/repositories/notification_repository.dart';
import 'package:metadata/screens/call_result_screen.dart';
import 'package:metadata/screens/calling_screen.dart';

final incomingCallServiceProvider = Provider<IncomingCallService>((ref) {
  return IncomingCallService(
    contactRepository: ref.watch(contactRepositoryProvider),
    callLogRepository: ref.watch(callLogRepositoryProvider),
    notificationRepository: ref.watch(notificationRepositoryProvider),
    localNotifications: ref.watch(localNotificationsServiceProvider),
    dialerService: ref.watch(dialerServiceProvider),
  );
});

/// Bridges the native call-state platform channel into the app's UI.
///
/// Android side: `CallScreeningServiceImpl.kt` + a telecom broadcast
/// receiver feed real ringing/connected/disconnected state, and
/// `answerCall`/`declineCall` act on the real call (see the plan's Android
/// section for the known best-effort limitation on decline-after-ringing).
/// iOS side: `CallObserverPlugin.swift` wraps `CXCallObserver` — state only,
/// no phone number, no answer/decline control (a hard Apple limitation, not
/// a gap in this class).
///
/// On `ringing`, looks up the caller against saved contacts and pushes
/// [CallingScreen] (incoming variant) via [rootNavigatorKey]. On accept, it
/// swaps to the connected variant instead of closing, mirroring the
/// existing outgoing-call flow in `call_flow_helper.dart`. On
/// disconnected, tears down the notification/overlay and logs the call.
class IncomingCallService {
  IncomingCallService({
    required ContactRepository contactRepository,
    required CallLogRepository callLogRepository,
    required NotificationRepository notificationRepository,
    required LocalNotificationsService localNotifications,
    required DialerService dialerService,
  }) : _contacts = contactRepository,
       _callLogs = callLogRepository,
       _notifications = notificationRepository,
       _localNotifications = localNotifications,
       _dialer = dialerService;

  static const _methodChannel = MethodChannel('com.metadata.calls/methods');
  static const _eventChannel = EventChannel('com.metadata.calls/events');

  final ContactRepository _contacts;
  final CallLogRepository _callLogs;
  final NotificationRepository _notifications;
  final LocalNotificationsService _localNotifications;
  final DialerService _dialer;

  StreamSubscription<dynamic>? _subscription;
  bool _initialized = false;

  // State for whichever call is currently on screen/ringing. There is only
  // ever one active call at a time on a mobile device.
  bool _overlayActive = false;
  bool _showingRingingScreen = false;
  bool _resolved = false; // true once accept/decline/missed has been logged
  bool _isOutgoingCall = false;
  // True once an outgoing call actually connects — lets us tell "the other
  // side answered then hung up" apart from "it never connected" (busy, no
  // answer, or declined — the OS gives us no way to tell which).
  bool _outgoingConnected = false;
  ContactModel? _activeContact;
  String? _activePhoneNumber;
  String? _activeCallerName;
  EncounterDetails? _activeEncounterDetails;

  /// When the current call went live, or null if it never did. Drives both the
  /// duration shown on the call screen and the talk time written to the log.
  DateTime? _connectedAt;

  /// The `call_logs` document for the current call, so the entry written when
  /// the call started can be completed with its outcome instead of a second
  /// entry being added for the same call.
  String? _activeCallLogId;

  /// The in-flight write that will produce [_activeCallLogId]. Awaited before
  /// the call's outcome is recorded, because a call can easily end before a
  /// Firestore round trip finishes — and then the duration would have nowhere
  /// to go.
  Future<void>? _pendingLogWrite;

  /// Set the instant a hang-up starts being handled. Android delivers
  /// `ACTION_PHONE_STATE_CHANGED` more than once for a single transition on
  /// some handsets, and every step of finishing a call has an `await` in it —
  /// without a synchronous latch, the second delivery walks in through the
  /// middle of the first and logs the same call again.
  bool _finishing = false;

  /// The call screen this service currently owns.
  ///
  /// Tracked as a route rather than relying on `pop()` so teardown can only
  /// ever remove *this* screen. A bare pop would remove whatever happens to
  /// be on top, which is the wrong screen as soon as the user has navigated
  /// somewhere else while a call was in flight.
  Route<dynamic>? _activeRoute;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    _subscription = _eventChannel.receiveBroadcastStream().listen(
      (event) => _handleEventSafely(IncomingCallEvent.fromMap(event as Map)),
      onError: (Object error) =>
          debugPrint('IncomingCallService stream error: $error'),
    );
  }

  /// Nothing awaits [_handleEvent], so an error escaping it would be an
  /// unhandled async error — and, worse, would abandon a call screen mid-flow
  /// with no way for the user to get rid of it. A failed hang-up in particular
  /// has to still take the screen down.
  Future<void> _handleEventSafely(IncomingCallEvent event) async {
    try {
      await _handleEvent(event);
    } catch (error) {
      debugPrint(
        'IncomingCallService failed to handle ${event.state.name}: $error',
      );
      if (event.state == IncomingCallState.disconnected) {
        await _teardown();
      }
    }
  }

  /// Requests the Android call-screening role + phone-state/answer/call
  /// runtime permissions. No-op on iOS — CXCallObserver needs no runtime
  /// grant, and there's no equivalent auto-dial permission to request there.
  Future<bool> requestPermissions() async {
    if (!Platform.isAndroid) return true;
    final granted = await _methodChannel.invokeMethod<bool>(
      'requestCallPermissions',
    );
    return granted ?? false;
  }

  /// Whether call detection + direct outgoing dialing are actually usable
  /// right now — lets Profile's Permissions screen show real status instead
  /// of just a re-ask button with no visibility into what's actually
  /// granted. Always true on iOS: nothing here requires a runtime grant.
  Future<bool> hasCallPermissions() async {
    if (!Platform.isAndroid) return true;
    try {
      final status = await _methodChannel.invokeMapMethod<String, bool>(
        'getCallRolesStatus',
      );
      if (status == null) return false;
      return (status['readPhoneState'] ?? false) &&
          (status['answerPhoneCalls'] ?? false) &&
          (status['callPhone'] ?? false) &&
          (status['callScreeningRole'] ?? false);
    } catch (_) {
      return false;
    }
  }

  /// Hook point mirroring `MessagingService.handleInitialMessage()` for
  /// cold starts triggered by tapping the full-screen incoming-call
  /// notification. The notification's full-screen intent already surfaces
  /// the ringing event directly in the common case; kept for parity and as
  /// the place to extend if a cold-start-specific gap shows up in testing.
  Future<void> handleInitialCallNotification() async {}

  /// Starts the live in-app screen for a call the user is placing (tapping
  /// "call" on a saved contact) — called from `call_flow_helper.dart`
  /// before handing off to the native dialer. Shows "Calling…" immediately,
  /// then reacts to the real connected/disconnected phone-state broadcast
  /// (armed on the native side via `armOutgoingCall`) to flip to a live
  /// duration timer and to dismiss when the call actually ends. Ending the
  /// call early from this screen is best-effort only — same underlying
  /// limitation as incoming decline: no public API lets a non-default-dialer
  /// app hang up an active call, so it only dismisses the overlay.
  Future<void> startOutgoingCall({
    required ContactModel contact,
    required EncounterDetails encounterDetails,
    String? callLogId,
  }) async {
    if (_overlayActive) return;
    _overlayActive = true;
    _isOutgoingCall = true;
    _outgoingConnected = false;
    _finishing = false;
    _connectedAt = null;
    _activeCallLogId = callLogId;
    _pendingLogWrite = null;
    _activeContact = contact;
    _activePhoneNumber = contact.phoneNumber;
    _activeCallerName = contact.fullName;
    _activeEncounterDetails = encounterDetails;

    try {
      await _methodChannel.invokeMethod('armOutgoingCall', {
        'phoneNumber': contact.phoneNumber,
      });
    } catch (_) {
      // Non-fatal: worst case the live status/timer won't update
      // reactively — the call itself doesn't depend on this.
    }

    _showCallScreen(
      CallingScreen(
        callerName: _activeCallerName!,
        phoneNumber: _activePhoneNumber!,
        avatarImage: _avatarImage(),
        isIncoming: false,
        isConnected: false,
        encounterDetails: _activeEncounterDetails!,
        onDecline: _onEndTapped,
      ),
    );
  }

  /// Puts [screen] on the root navigator and remembers its route.
  ///
  /// When a call screen is already showing it is *replaced* rather than
  /// stacked, so the ringing → connected → result progression never leaves a
  /// pile of dead call screens behind for the user to back through.
  void _showCallScreen(Widget screen) {
    final navigator = rootNavigatorKey.currentState;
    if (navigator == null) return;

    final route = MaterialPageRoute<void>(builder: (_) => screen);
    final existing = _activeRoute;
    if (existing != null && existing.isActive) {
      navigator.replace(oldRoute: existing, newRoute: route);
    } else {
      navigator.push(route);
    }
    _activeRoute = route;
  }

  /// Removes this service's call screen, if it is still on the stack.
  void _dismissCallScreen() {
    final navigator = rootNavigatorKey.currentState;
    final route = _activeRoute;
    _activeRoute = null;
    if (navigator == null || route == null || !route.isActive) return;
    navigator.removeRoute(route);
  }

  /// The in-app "End"/"Decline" button on an outgoing or connected call.
  ///
  /// Dismisses the overlay *and* clears the service's own state. Popping the
  /// route directly would leave `_overlayActive` set, after which the next
  /// call would be silently ignored by [startOutgoingCall]'s guard.
  ///
  /// A call that was live still gets its talk time written here: ending it from
  /// this screen is best-effort against the real call, so the phone-state idle
  /// that would otherwise record the duration may not arrive until well after
  /// this screen is gone — by which point the call is no longer this service's.
  Future<void> _onEndTapped() async {
    if (_connectedAt != null && !_finishing) {
      _finishing = true;
      await _recordCallOutcome(
        status: _isOutgoingCall ? CallLogStatus.completed : null,
      );
    }
    await _teardown();
  }

  Future<void> _handleEvent(IncomingCallEvent event) async {
    // A call this app placed itself is authoritative about its own direction.
    // The native side labels events too, but a screening callback that
    // mislabels an outgoing call as incoming must not be able to turn it back
    // into one here — that is what put outgoing calls in Recent Call Logs as
    // missed. Safe as a rule because the handset cannot ring for someone else
    // while the user is already on a call this app is showing a screen for —
    // but only while that call is still in flight. Once it has finished, what
    // is on screen is a dismissable result card, and a genuinely new incoming
    // call has to be able to get through it (the person just called back).
    final isOutgoing =
        event.isOutgoing || (_overlayActive && _isOutgoingCall && !_finishing);
    if (isOutgoing) {
      await _handleOutgoingCallEvent(event);
      return;
    }
    switch (event.state) {
      case IncomingCallState.ringing:
        await _onRinging(event);
        break;
      case IncomingCallState.connected:
        await _onConnected(event);
        break;
      case IncomingCallState.disconnected:
        await _onDisconnected(event);
        break;
    }
  }

  Future<void> _handleOutgoingCallEvent(IncomingCallEvent event) async {
    if (!_overlayActive || !_isOutgoingCall) return;
    switch (event.state) {
      case IncomingCallState.connected:
        if (_outgoingConnected) return;
        _outgoingConnected = true;
        _connectedAt = DateTime.now();
        _pushOutgoingConnectedScreen();
        break;
      case IncomingCallState.disconnected:
        if (_finishing) return;
        _finishing = true;
        if (_outgoingConnected) {
          // The one thing the entry written when dialing started could not
          // know: that the call was answered, and for how long.
          await _recordCallOutcome(
            status: CallLogStatus.completed,
            nativeDurationSeconds: event.durationSeconds,
          );
          await _teardown();
        } else {
          // Never connected — the OS gives no reason (busy/no answer/
          // declined all look identical to a non-default-dialer app), so
          // show a generic "couldn't complete" result with Retry/Cancel
          // instead of just silently closing the overlay. The log entry stays
          // as dialed: an outgoing call that went unanswered is not a call the
          // *user* missed, and labelling it that way was actively confusing.
          _pushCallNotConnectedScreen();
        }
        break;
      case IncomingCallState.ringing:
        break;
    }
  }

  void _pushCallNotConnectedScreen() {
    _showCallScreen(
      CallResultScreen(
        callerName: _activeCallerName ?? 'Unknown caller',
        avatarImage: _avatarImage(),
        onRetry: _retryOutgoingCall,
        onCancel: () => _teardown(),
      ),
    );
  }

  Future<void> _retryOutgoingCall() async {
    final phoneNumber = _activePhoneNumber;
    if (phoneNumber == null) return;
    _outgoingConnected = false;
    // Re-arm the finish latch: this is a fresh attempt, and its own
    // connected/disconnected pair still has to get through. The existing log
    // entry is reused — the user is still trying to reach the same person, so
    // a retry is the same call, not a new row in the feed.
    _finishing = false;
    _connectedAt = null;

    try {
      await _methodChannel.invokeMethod('armOutgoingCall', {
        'phoneNumber': phoneNumber,
      });
    } catch (_) {
      // Non-fatal: worst case the live status/timer won't update reactively.
    }

    _showCallScreen(
      CallingScreen(
        callerName: _activeCallerName ?? 'Unknown caller',
        phoneNumber: phoneNumber,
        avatarImage: _avatarImage(),
        isIncoming: false,
        isConnected: false,
        encounterDetails:
            _activeEncounterDetails ?? EncounterDetails.unknownCaller(),
        onDecline: _onEndTapped,
      ),
    );

    await _dialer.callNumber(phoneNumber);
  }

  void _pushOutgoingConnectedScreen() {
    _showCallScreen(
      CallingScreen(
        callerName: _activeCallerName ?? 'Unknown caller',
        phoneNumber: _activePhoneNumber ?? '',
        avatarImage: _avatarImage(),
        isIncoming: false,
        isConnected: true,
        connectedAt: _connectedAt,
        encounterDetails:
            _activeEncounterDetails ?? EncounterDetails.unknownCaller(),
        onDecline: _onEndTapped,
      ),
    );
  }

  Future<void> _onRinging(IncomingCallEvent event) async {
    // A finished outgoing attempt still owns the overlay, because its
    // "couldn't complete" card is waiting on the user. A real ringing call
    // outranks that card, so clear it rather than dropping the call.
    if (_overlayActive && _isOutgoingCall && _finishing) {
      await _teardown();
    }
    if (_overlayActive) return;
    _overlayActive = true;
    _resolved = false;
    _finishing = false;
    _isOutgoingCall = false;
    _connectedAt = null;
    _activeCallLogId = null;
    _pendingLogWrite = null;

    final phoneNumber = event.phoneNumber;
    final contact = phoneNumber != null
        ? await _contacts.findByPhoneNumber(phoneNumber)
        : null;

    // A blocked contact gets no call card and no notification. The handset
    // still rings — this app is not the default dialer, so it cannot stop the
    // carrier call itself. Release the overlay guard taken above so the next
    // call from anyone else is unaffected, and tell the native side to forget
    // the call too, so answering it on the handset doesn't pull this app to the
    // front for a caller the user chose not to hear from.
    if (contact?.isBlocked ?? false) {
      _overlayActive = false;
      try {
        await _methodChannel.invokeMethod('releaseCall');
      } catch (_) {
        // Non-fatal: nothing is on screen for this call either way.
      }
      return;
    }

    _activePhoneNumber = phoneNumber;
    _activeContact = contact;
    _activeCallerName =
        _activeContact?.fullName ?? phoneNumber ?? 'Unknown caller';
    _activeEncounterDetails = _activeContact != null
        ? EncounterDetails.fromContact(_activeContact!)
        : EncounterDetails.unknownCaller();

    await _localNotifications.showIncomingCallNotification(
      title: 'Incoming call',
      body: _activeCallerName!,
      payload: phoneNumber ?? '',
    );

    _showingRingingScreen = true;
    _showCallScreen(
      CallingScreen(
        callerName: _activeCallerName!,
        phoneNumber: phoneNumber ?? '',
        avatarImage: _avatarImage(),
        isIncoming: true,
        encounterDetails: _activeEncounterDetails!,
        onAccept: event.canAnswer ? _onAcceptTapped : null,
        onDecline: event.canDecline ? _onDeclineTapped : null,
      ),
    );
  }

  /// If the call became active while our ringing screen is still up — e.g.
  /// the user answered via the native call UI instead of our button, which
  /// is the expected path whenever our in-app Decline can't reach the call
  /// (see the plan's Android limitation) — swap to the connected view so
  /// the overlay reflects reality instead of going stale.
  Future<void> _onConnected(IncomingCallEvent event) async {
    // Latched *before* the first await. The screen swap below is what used to
    // stand in for this, and it happens a Firestore round trip later — long
    // enough for a repeated off-hook broadcast to log the same answered call a
    // second time.
    if (!_showingRingingScreen) {
      await _localNotifications.cancelIncomingCallNotification();
      return;
    }
    _showingRingingScreen = false;
    _resolved = true;
    _connectedAt ??= DateTime.now();

    _replaceWithConnectedScreen();
    await _localNotifications.cancelIncomingCallNotification();
    await _logActiveCall(CallLogStatus.received);
  }

  Future<void> _onDisconnected(IncomingCallEvent event) async {
    if (_finishing) return;
    _finishing = true;

    if (_overlayActive && !_resolved) {
      _resolved = true;
      await _logActiveCall(CallLogStatus.missed);
    } else if (_overlayActive) {
      // Answered, so the entry already exists — complete it with the talk
      // time rather than adding a row for the same call.
      await _recordCallOutcome(nativeDurationSeconds: event.durationSeconds);
    }
    await _teardown();
  }

  Future<void> _onAcceptTapped() async {
    if (_resolved) return;
    // Both latches set synchronously, so the off-hook broadcast that follows
    // acceptRingingCall() finds this call already resolved instead of logging
    // it as a second "received" call.
    _resolved = true;
    _showingRingingScreen = false;
    _connectedAt = DateTime.now();

    _replaceWithConnectedScreen();
    try {
      await _methodChannel.invokeMethod('answerCall');
    } catch (_) {
      // Answering is best-effort: without ANSWER_PHONE_CALLS the user has to
      // use the handset's own UI, and the connected screen already shown here
      // is still the right thing to be looking at when they do.
    }
    await _localNotifications.cancelIncomingCallNotification();
    await _logActiveCall(CallLogStatus.received);
  }

  Future<void> _onDeclineTapped() async {
    if (_resolved) return;
    _resolved = true;
    _showingRingingScreen = false;

    // Started, not awaited: the log is a network write, and the user's decline
    // should reach the call without waiting on it. `_logActiveCall` snapshots
    // what it needs up front, so the teardown below cannot pull the caller's
    // details out from under it.
    final logging = _logActiveCall(CallLogStatus.declined);
    try {
      await _methodChannel.invokeMethod('declineCall');
    } catch (_) {
      // Best-effort by design — see MainActivity.declineRingingCall().
    }
    await _teardown();
    await logging;
  }

  void _replaceWithConnectedScreen() {
    _showingRingingScreen = false;
    _showCallScreen(
      CallingScreen(
        callerName: _activeCallerName ?? 'Unknown caller',
        phoneNumber: _activePhoneNumber ?? '',
        avatarImage: _avatarImage(),
        isIncoming: false,
        connectedAt: _connectedAt,
        encounterDetails:
            _activeEncounterDetails ?? EncounterDetails.unknownCaller(),
        onDecline: _onEndTapped,
      ),
    );
  }

  ImageProvider? _avatarImage() {
    final url = _activeContact?.photoUrl;
    return url != null ? NetworkImage(url) : null;
  }

  /// Writes the single Recent Call Logs row for the current incoming call, plus
  /// its bell notification.
  ///
  /// Everything it needs is snapshotted synchronously up front, so a teardown
  /// racing the network writes below can't leave half a log entry attributed to
  /// "Unknown caller". Callers are responsible for only reaching here once per
  /// call — see the `_resolved`/`_finishing` latches.
  Future<void> _logActiveCall(CallLogStatus status) {
    final contact = _activeContact;
    final phoneNumber = _activePhoneNumber ?? '';
    final callerName =
        _activeCallerName ?? _activePhoneNumber ?? 'Unknown caller';

    final write = _writeCallLog(
      status: status,
      contact: contact,
      phoneNumber: phoneNumber,
      callerName: callerName,
    );
    _pendingLogWrite = write;
    return write;
  }

  Future<void> _writeCallLog({
    required CallLogStatus status,
    required ContactModel? contact,
    required String phoneNumber,
    required String callerName,
  }) async {
    _activeCallLogId = await _callLogs.logIncomingCall(
      contactId: contact?.id,
      callerName: callerName,
      callerPhone: phoneNumber,
      status: status,
    );
    if (contact != null) {
      // Counts as communication both ways: it orders Home's "Recent Contacts"
      // and resets the two-year quarantine clock. A call *from* someone is
      // every bit as much contact as one placed to them.
      await _contacts.markContacted(contact.id);
    }
    await _notifications.create(
      AppNotification(
        id: '',
        type: _notificationTypeForStatus(status),
        title: _titleForStatus(status),
        body: '${_bodyVerbForStatus(status)} $callerName.',
        relatedContactId: contact?.id,
        imageUrl: contact?.photoUrl,
      ),
    );
  }

  /// Completes the current call's existing log entry with how it ended.
  ///
  /// The duration is measured natively between the off-hook and idle
  /// transitions, which is what makes it right even when the app spent the
  /// whole call in the background; the local `_connectedAt` clock is the
  /// fallback for a platform that reported no duration of its own.
  Future<void> _recordCallOutcome({
    CallLogStatus? status,
    int nativeDurationSeconds = 0,
  }) async {
    // The entry may still be in flight — a short call can easily end before
    // the write that created its row has come back with an id. Bounded,
    // because losing the duration is a far better outcome than leaving the
    // call screen up while a write on a dead connection never settles.
    try {
      await _pendingLogWrite?.timeout(const Duration(seconds: 10));
    } catch (_) {
      // Falls through to the id check below, which is null if the row that
      // would have carried the duration was never created.
    }
    final id = _activeCallLogId;
    if (id == null || id.isEmpty) return;

    final connectedAt = _connectedAt;
    final localSeconds = connectedAt == null
        ? 0
        : DateTime.now().difference(connectedAt).inSeconds;
    final seconds = nativeDurationSeconds > localSeconds
        ? nativeDurationSeconds
        : localSeconds;

    try {
      await _callLogs.updateCallOutcome(
        id: id,
        status: status,
        durationSeconds: seconds,
      );
    } catch (_) {
      // Non-fatal: the call is already in the feed, just without its length.
    }
  }

  /// A missed call gets its own notification type so the bell can tell the
  /// three call kinds apart. Declined stays on the incoming side — the call
  /// did reach the user, they just turned it down.
  NotificationType _notificationTypeForStatus(CallLogStatus status) {
    return status == CallLogStatus.missed
        ? NotificationType.missedCall
        : NotificationType.incomingCall;
  }

  String _titleForStatus(CallLogStatus status) {
    switch (status) {
      case CallLogStatus.received:
        return 'Incoming call';
      case CallLogStatus.declined:
        return 'Declined call';
      case CallLogStatus.missed:
        return 'Missed call';
      case CallLogStatus.dialed:
      case CallLogStatus.completed:
        return 'Call';
    }
  }

  String _bodyVerbForStatus(CallLogStatus status) {
    switch (status) {
      case CallLogStatus.received:
        return 'You answered a call from';
      case CallLogStatus.declined:
        return 'You declined a call from';
      case CallLogStatus.missed:
        return 'You missed a call from';
      case CallLogStatus.dialed:
      case CallLogStatus.completed:
        return 'Call with';
    }
  }

  Future<void> _teardown() async {
    await _localNotifications.cancelIncomingCallNotification();
    // Covers every screen this class can leave on display (ringing,
    // incoming-connected, outgoing calling/connected, call-not-connected) so
    // none of them get stuck open once the real call actually ends. Removing
    // the tracked route rather than popping means this can never take away a
    // screen the user navigated to themselves.
    _dismissCallScreen();
    _overlayActive = false;
    _showingRingingScreen = false;
    _resolved = false;
    _isOutgoingCall = false;
    _outgoingConnected = false;
    _finishing = false;
    _connectedAt = null;
    _activeCallLogId = null;
    _pendingLogWrite = null;
    _activeContact = null;
    _activePhoneNumber = null;
    _activeCallerName = null;
    _activeEncounterDetails = null;
  }

  void dispose() {
    _subscription?.cancel();
  }
}

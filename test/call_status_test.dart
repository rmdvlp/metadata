import 'package:flutter_test/flutter_test.dart';
import 'package:metadata/features/calling/models/call_status.dart';

/// The call state machine is the one piece of the calling feature whose
/// correctness cannot be checked by looking at a screen: it is what stops two
/// racing devices from producing an inconsistent call, and it only ever
/// misbehaves under timing that is hard to reproduce by hand.
void main() {
  group('CallStatus classification', () {
    test('terminal statuses are exactly the five end states', () {
      final terminal = CallStatus.values.where((s) => s.isTerminal).toSet();
      expect(terminal, {
        CallStatus.rejected,
        CallStatus.cancelled,
        CallStatus.missed,
        CallStatus.ended,
        CallStatus.failed,
      });
    });

    test('pending covers only the pre-answer states', () {
      expect(CallStatus.initiating.isPending, isTrue);
      expect(CallStatus.ringing.isPending, isTrue);
      expect(CallStatus.accepted.isPending, isFalse);
    });

    test('active covers the answered-but-not-yet-over states', () {
      expect(CallStatus.accepted.isActive, isTrue);
      expect(CallStatus.connecting.isActive, isTrue);
      expect(CallStatus.connected.isActive, isTrue);
      expect(CallStatus.ringing.isActive, isFalse);
      expect(CallStatus.ended.isActive, isFalse);
    });

    test('unknown wire values decode to failed rather than throwing', () {
      expect(CallStatus.fromValue('not_a_status'), CallStatus.failed);
      expect(CallStatus.fromValue(null), CallStatus.failed);
      expect(CallStatus.fromValue('connected'), CallStatus.connected);
    });
  });

  group('CallStatus transitions', () {
    test('happy path walks initiating -> ringing -> accepted -> connecting -> connected -> ended', () {
      expect(CallStatus.initiating.canTransitionTo(CallStatus.ringing), isTrue);
      expect(CallStatus.ringing.canTransitionTo(CallStatus.accepted), isTrue);
      expect(CallStatus.accepted.canTransitionTo(CallStatus.connecting), isTrue);
      expect(CallStatus.connecting.canTransitionTo(CallStatus.connected), isTrue);
      expect(CallStatus.connected.canTransitionTo(CallStatus.ended), isTrue);
    });

    test('a terminal status can never move again', () {
      for (final terminal in CallStatus.values.where((s) => s.isTerminal)) {
        for (final next in CallStatus.values) {
          expect(
            terminal.canTransitionTo(next),
            isFalse,
            reason: '${terminal.name} must not transition to ${next.name}',
          );
        }
      }
    });

    test('ended cannot go back to connected', () {
      expect(CallStatus.ended.canTransitionTo(CallStatus.connected), isFalse);
    });

    test('re-applying the same status is not a transition, which makes duplicate events no-ops', () {
      for (final status in CallStatus.values) {
        expect(status.canTransitionTo(status), isFalse, reason: status.name);
      }
    });

    test('a ringing call can be resolved by either party or by timeout', () {
      expect(CallStatus.ringing.canTransitionTo(CallStatus.rejected), isTrue);
      expect(CallStatus.ringing.canTransitionTo(CallStatus.cancelled), isTrue);
      expect(CallStatus.ringing.canTransitionTo(CallStatus.missed), isTrue);
    });

    test('an unanswered call cannot jump straight to connected', () {
      expect(CallStatus.ringing.canTransitionTo(CallStatus.connected), isFalse);
      expect(CallStatus.initiating.canTransitionTo(CallStatus.connected), isFalse);
    });

    test('an answered call can no longer be cancelled or missed', () {
      // The race this encodes: the caller's 30s ring timeout fires at the
      // same moment the receiver taps answer. Whichever transaction lands
      // first wins; the loser must be rejected rather than overwriting it.
      expect(CallStatus.accepted.canTransitionTo(CallStatus.missed), isFalse);
      expect(CallStatus.accepted.canTransitionTo(CallStatus.cancelled), isFalse);
      expect(CallStatus.connected.canTransitionTo(CallStatus.missed), isFalse);
    });

    test('every status can always reach a terminal state', () {
      for (final status in CallStatus.values.where((s) => !s.isTerminal)) {
        final reachable = CallStatus.values.where(
          (next) => next.isTerminal && status.canTransitionTo(next),
        );
        expect(
          reachable,
          isNotEmpty,
          reason: '${status.name} would be able to get stuck forever',
        );
      }
    });
  });
}

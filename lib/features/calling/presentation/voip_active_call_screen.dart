import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metadata/features/calling/controllers/call_controller.dart';
import 'package:metadata/features/calling/models/call_exception.dart';
import 'package:metadata/features/calling/models/call_status.dart';
import 'package:metadata/features/calling/services/call_service.dart';
import 'package:metadata/widgets/call_controls.dart';

/// The live-call surface, used for both an outgoing call that has not been
/// answered yet ("Calling…") and a connected call (running duration).
///
/// It reads one thing — [callSessionProvider] — and writes through
/// [callControllerProvider]. No Firestore, no WebRTC, no navigation decisions:
/// the coordinator removes this route when the call reaches a terminal state,
/// which is what makes the other party's screen close automatically when you
/// hang up.
class VoipActiveCallScreen extends ConsumerWidget {
  const VoipActiveCallScreen({super.key, required this.callId});

  final String callId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(callSessionProvider);
    final controller = ref.read(callControllerProvider);
    final call = session.call;
    final uid = controller.currentUserId;

    final peerName = (call != null && uid != null) ? call.otherPartyName(uid) : 'Call';
    final peerPhoto = (call != null && uid != null) ? call.otherPartyPhotoUrl(uid) : null;

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFFBDBDBD),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                const SizedBox(height: 56),
                CallAvatar(
                  image: peerPhoto != null ? NetworkImage(peerPhoto) : null,
                  backgroundColor: Colors.grey.shade400,
                ),
                const SizedBox(height: 20),
                Text(
                  peerName,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _statusLine(session),
                  style: TextStyle(fontSize: 15, color: Colors.grey.shade800),
                ),
                const SizedBox(height: 4),
                Text(
                  session.isConnected ? 'Voice Connected' : '',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                ),
                const Spacer(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    CallToggleButton(
                      icon: session.isMuted ? Icons.mic_off : Icons.mic,
                      label: session.isMuted ? 'Unmute' : 'Mute',
                      active: session.isMuted,
                      onTap: () => _run(context, controller.toggleMute),
                    ),
                    CallToggleButton(
                      icon: session.isSpeakerOn ? Icons.volume_up : Icons.hearing,
                      label: 'Speaker',
                      active: session.isSpeakerOn,
                      onTap: () => _run(context, controller.toggleSpeaker),
                    ),
                  ],
                ),
                const SizedBox(height: 32),
                CircleCallButton(
                  color: Colors.red,
                  icon: Icons.call_end,
                  size: 72,
                  onTap: () => _run(context, controller.hangUp),
                ),
                const SizedBox(height: 48),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The timer only ever reflects [CallSessionSnapshot.elapsed], which the
  /// service starts when WebRTC reports a live media path — never when the
  /// user tapped call. A 20-second wait for an answer must not appear as 20
  /// seconds of conversation.
  String _statusLine(CallSessionSnapshot session) {
    final status = session.call?.status;
    if (session.isConnected) {
      final minutes = session.elapsed.inMinutes.toString().padLeft(2, '0');
      final seconds = (session.elapsed.inSeconds % 60).toString().padLeft(2, '0');
      return '$minutes:$seconds';
    }
    switch (status) {
      case CallStatus.initiating:
      case CallStatus.ringing:
        return 'Calling…';
      case CallStatus.accepted:
      case CallStatus.connecting:
      case CallStatus.connected:
        return 'Connecting…';
      case CallStatus.rejected:
        return 'Call rejected';
      case CallStatus.missed:
        return 'No answer';
      case CallStatus.cancelled:
      case CallStatus.ended:
        return 'Call ended';
      case CallStatus.failed:
        return 'Call failed';
      case null:
        return 'Ending…';
    }
  }

  Future<void> _run(BuildContext context, Future<void> Function() action) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
    } on CallException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}

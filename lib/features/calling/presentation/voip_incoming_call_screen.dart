import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metadata/features/calling/controllers/call_controller.dart';
import 'package:metadata/features/calling/models/call_exception.dart';
import 'package:metadata/features/calling/models/call_model.dart';
import 'package:metadata/widgets/call_controls.dart';

/// Ringing screen for an inbound in-app call.
///
/// Visual language deliberately matches the existing cellular
/// `CallingScreen` (white surface, large avatar, swipe-to-answer row) so a
/// call looks the same whether it came over the carrier or over the internet.
///
/// Accepting is handled by [CallCoordinator] rather than here: the screen
/// only reports intent, because answering also has to reconcile with CallKit,
/// the foreground service, and the possibility that the caller hung up in the
/// same instant.
class VoipIncomingCallScreen extends ConsumerStatefulWidget {
  const VoipIncomingCallScreen({super.key, required this.call});

  final CallModel call;

  @override
  ConsumerState<VoipIncomingCallScreen> createState() => _VoipIncomingCallScreenState();
}

class _VoipIncomingCallScreenState extends ConsumerState<VoipIncomingCallScreen> {
  bool _resolving = false;

  Future<void> _accept() async {
    if (_resolving) return;
    setState(() => _resolving = true);
    final controller = ref.read(callControllerProvider);
    try {
      await controller.accept(widget.call.callId);
    } on CallException catch (e) {
      if (!mounted) return;
      setState(() => _resolving = false);
      _showError(e.message);
    }
  }

  Future<void> _decline() async {
    if (_resolving) return;
    setState(() => _resolving = true);
    try {
      await ref.read(callControllerProvider).reject(widget.call.callId);
    } on CallException catch (e) {
      if (!mounted) return;
      _showError(e.message);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    // If the caller gives up while this screen is showing, the document flips
    // to a terminal status and the coordinator removes the route. Watching it
    // here as well keeps the label honest during the brief overlap.
    final live = ref.watch(_incomingCallProvider(widget.call.callId));
    final call = live.value ?? widget.call;
    final gone = call.status.isTerminal;
    final photoUrl = call.callerPhotoUrl;

    return PopScope(
      // A ringing call must be answered or declined, not dismissed with the
      // back gesture — silently leaving it ringing would strand the caller.
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                const SizedBox(height: 32),
                const Text(
                  'In Coming Call',
                  style: TextStyle(
                    fontSize: 22,
                    color: Colors.black87,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 40),
                CallAvatar(
                  image: photoUrl != null ? NetworkImage(photoUrl) : null,
                  backgroundColor: Colors.grey.shade300,
                  badge: const Icon(Icons.call_received, color: Colors.green, size: 20),
                ),
                const SizedBox(height: 20),
                Text(
                  call.callerName,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  gone ? 'Call ended' : 'Incoming Audio Call',
                  style: TextStyle(fontSize: 15, color: Colors.grey.shade600),
                ),
                const Spacer(),
                if (_resolving)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 24),
                    child: CircularProgressIndicator(),
                  ),
                SwipeToAnswerRow(
                  onAccept: (_resolving || gone) ? null : _accept,
                  onDecline: (_resolving || gone) ? null : _decline,
                ),
                const SizedBox(height: 48),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

final _incomingCallProvider =
    StreamProvider.autoDispose.family<CallModel, String>((ref, callId) {
      return ref
          .watch(callControllerProvider)
          .watchCall(callId)
          .where((call) => call != null)
          .cast<CallModel>();
    });

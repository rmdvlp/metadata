import 'package:flutter/material.dart';

/// Shown when an outgoing call ends without ever connecting. The OS only
/// tells a non-default-dialer app "disconnected" — it does not say whether
/// the line was busy, unanswered, or actively declined (see
/// `CallObserverPlugin.swift` / `IncomingCallBridge.kt`) — so this is a
/// deliberately generic "could not complete" state rather than a specific
/// Busy/No Answer/Rejected message.
class CallResultScreen extends StatelessWidget {
  const CallResultScreen({
    super.key,
    required this.callerName,
    required this.onRetry,
    required this.onCancel,
    this.avatarImage,
  });

  final String callerName;
  final ImageProvider? avatarImage;
  final VoidCallback onRetry;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFBDBDBD),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const SizedBox(height: 56),
              CircleAvatar(
                radius: 70,
                backgroundColor: Colors.grey.shade400,
                backgroundImage: avatarImage,
                child: avatarImage == null
                    ? const Icon(Icons.person, size: 70, color: Colors.white)
                    : null,
              ),
              const SizedBox(height: 24),
              Text(
                callerName,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Call could not be completed',
                style: TextStyle(fontSize: 15, color: Colors.black54),
              ),
              const SizedBox(height: 6),
              const Text(
                'The line may have been busy, unanswered, or the call was declined.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.black45),
              ),
              const Spacer(),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onCancel,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(26),
                        ),
                        side: const BorderSide(color: Colors.black26),
                      ),
                      child: const Text('Cancel', style: TextStyle(color: Colors.black87)),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: onRetry,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(26),
                        ),
                      ),
                      child: const Text('Retry'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

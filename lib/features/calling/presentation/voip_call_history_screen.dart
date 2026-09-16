import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metadata/models/call_log_model.dart';
import 'package:metadata/repositories/call_log_repository.dart';
import 'package:metadata/utils/date_formatting.dart';

/// History of in-app VoIP calls.
///
/// Reads the existing `users/{uid}/call_logs` collection rather than
/// introducing a second history store — cellular and in-app calls are both
/// "calls I had" and belong in one timeline. The `method` filter is applied
/// client-side so no extra composite index is required; personal call logs
/// are small enough that this is not worth an index.
final voipCallHistoryProvider = StreamProvider.autoDispose<List<CallLogEntry>>((ref) {
  return ref
      .watch(callLogRepositoryProvider)
      .watchCallLogs()
      .map((entries) => entries.where((e) => e.method == CallMethod.voip).toList());
});

class VoipCallHistoryScreen extends ConsumerWidget {
  const VoipCallHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(voipCallHistoryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Call History')),
      body: history.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const Center(child: Text('Could not load call history.')),
        data: (entries) {
          if (entries.isEmpty) {
            return const Center(child: Text('No in-app calls yet.'));
          }
          return ListView.separated(
            itemCount: entries.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) => _CallHistoryTile(entry: entries[index]),
          );
        },
      ),
    );
  }
}

class _CallHistoryTile extends StatelessWidget {
  const _CallHistoryTile({required this.entry});

  final CallLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final missed = entry.status == CallLogStatus.missed;
    final incoming = entry.direction == CallDirection.incoming;

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: missed ? Colors.red.shade50 : Colors.blue.shade50,
        child: Icon(
          missed
              ? Icons.call_missed
              : (incoming ? Icons.call_received : Icons.call_made),
          color: missed ? Colors.red : Colors.blue,
          size: 20,
        ),
      ),
      title: Text(
        entry.calleeName.isEmpty ? 'Unknown' : entry.calleeName,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: missed ? Colors.red : Colors.black87,
        ),
      ),
      subtitle: Text(_subtitle()),
      trailing: entry.duration > 0
          ? Text(
              _formatDuration(entry.duration),
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            )
          : null,
    );
  }

  String _subtitle() {
    final label = switch (entry.status) {
      CallLogStatus.missed => 'Missed',
      CallLogStatus.declined => 'Declined',
      CallLogStatus.received => 'Incoming',
      CallLogStatus.completed => entry.direction == CallDirection.incoming
          ? 'Incoming'
          : 'Outgoing',
      CallLogStatus.dialed => 'Outgoing',
    };
    final when = entry.startedAt;
    if (when == null) return label;
    return '$label · ${formatShortDate(when)}, ${formatTime(when)}';
  }

  String _formatDuration(int seconds) {
    final minutes = (seconds ~/ 60).toString().padLeft(2, '0');
    return '$minutes:${(seconds % 60).toString().padLeft(2, '0')}';
  }
}

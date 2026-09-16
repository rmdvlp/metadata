import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metadata/core/firebase/firebase_providers.dart';
import 'package:metadata/models/call_log_model.dart';
import 'package:metadata/models/contact_model.dart';
import 'package:metadata/repositories/contact_repository.dart';
import 'package:metadata/utils/date_formatting.dart';
import 'package:metadata/utils/phone_number.dart';

/// How long a call log lives. Anything older is both hidden from the feeds
/// and deleted from Firestore by [CallLogRepository.purgeExpiredCallLogs], so
/// "Recent Call Logs" is always a rolling seven-day window.
const Duration kCallLogRetention = Duration(days: 7);

final callLogRepositoryProvider = Provider<CallLogRepository>((ref) {
  return CallLogRepository(
    firestore: ref.watch(firebaseFirestoreProvider),
    auth: ref.watch(firebaseAuthProvider),
  );
});

class CallLogRepository {
  CallLogRepository({
    required FirebaseFirestore firestore,
    required FirebaseAuth auth,
  }) : _firestore = firestore,
       _auth = auth;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  CollectionReference<Map<String, dynamic>>? get _ref {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return null;
    return _firestore.collection('users').doc(uid).collection('call_logs');
  }

  /// Returns the new entry's document id, or null if there was no signed-in
  /// user to log against. The id is what lets the call be *updated* when it
  /// ends — with how long it lasted, and whether it ever connected — instead
  /// of a second row being added for the same call.
  Future<String?> logCallAttempt({
    required String contactId,
    required String calleeName,
    required String calleePhone,
  }) async {
    final ref = _ref;
    if (ref == null) return null;
    final entry = CallLogEntry(
      id: '',
      contactId: contactId,
      calleeName: calleeName,
      calleePhone: calleePhone,
    );
    final doc = await ref.add(entry.toCreateMap());
    return doc.id;
  }

  /// Returns the new entry's document id — see [logCallAttempt].
  Future<String?> logIncomingCall({
    required String? contactId,
    required String callerName,
    required String callerPhone,
    required CallLogStatus status,
  }) async {
    final ref = _ref;
    if (ref == null) return null;
    final entry = CallLogEntry(
      id: '',
      contactId: contactId ?? '',
      calleeName: callerName,
      calleePhone: callerPhone,
      status: status,
      direction: CallDirection.incoming,
    );
    final doc = await ref.add(entry.toCreateMap());
    return doc.id;
  }

  /// Fills in how a call actually turned out, once it's over.
  ///
  /// A call is logged the moment it starts, because that is the only moment
  /// guaranteed to happen — the process can be killed mid-call. What it cannot
  /// know at that point is the conversation length, so the entry is completed
  /// in place here rather than by adding a second entry (which is what made a
  /// single call show up twice in Recent Call Logs).
  Future<void> updateCallOutcome({
    required String id,
    CallLogStatus? status,
    int? durationSeconds,
  }) async {
    final ref = _ref;
    if (ref == null || id.isEmpty) return;
    final data = <String, dynamic>{
      if (status != null) 'status': status.name,
      if (durationSeconds != null && durationSeconds > 0)
        'duration': durationSeconds,
    };
    if (data.isEmpty) return;
    await ref.doc(id).update(data);
  }

  Stream<List<CallLogEntry>> watchCallLogs({String? contactId}) {
    final ref = _ref;
    if (ref == null) return Stream.value(const []);
    Query<Map<String, dynamic>> query = ref.orderBy('startedAt', descending: true);
    if (contactId != null) {
      query = query.where('contactId', isEqualTo: contactId);
    }
    return query.snapshots().map(
      (snap) => snap.docs.map(CallLogEntry.fromFirestore).toList(),
    );
  }

  /// Permanently deletes call logs older than [retention]. Called once per
  /// session at start-up, which is what keeps the collection — and therefore
  /// the unbounded `watchCallLogs` read behind the feeds — bounded.
  ///
  /// Entries whose `startedAt` is still a pending server timestamp never match
  /// the cutoff, so a call being written right now can't be swept away.
  /// Returns the number of documents deleted.
  Future<int> purgeExpiredCallLogs({
    Duration retention = kCallLogRetention,
    DateTime? now,
  }) async {
    final ref = _ref;
    if (ref == null) return 0;
    final cutoff = (now ?? DateTime.now()).subtract(retention);
    final snap = await ref
        .where('startedAt', isLessThan: Timestamp.fromDate(cutoff))
        .get();
    if (snap.docs.isEmpty) return 0;

    // Firestore caps a write batch at 500 operations.
    const chunkSize = 500;
    for (var start = 0; start < snap.docs.length; start += chunkSize) {
      final batch = _firestore.batch();
      for (final doc in snap.docs.skip(start).take(chunkSize)) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    }
    return snap.docs.length;
  }
}

/// One row in "Recent Call Logs": a single call — incoming, outgoing or
/// missed — joined to the saved contact it belongs to.
class RecentCallLog {
  const RecentCallLog({required this.entry, required this.contact});

  final CallLogEntry entry;
  final ContactModel contact;

  bool get isMissed => entry.status == CallLogStatus.missed;

  /// `declined` is an incoming call the user rejected, so it belongs on the
  /// incoming side even though no conversation happened.
  bool get isIncoming => entry.direction == CallDirection.incoming;

  DateTime? get occurredAt => entry.startedAt ?? entry.createdAt;

  /// How long the conversation lasted, e.g. `4:07`, or null when there was no
  /// conversation to measure (missed, declined, never answered) or the call is
  /// still in progress.
  String? get durationLabel =>
      entry.duration > 0 ? formatCallDuration(entry.duration) : null;

  String get statusLabel => switch (entry.status) {
    CallLogStatus.missed => 'Missed',
    CallLogStatus.declined => 'Declined',
    CallLogStatus.received => 'Incoming',
    CallLogStatus.completed => isIncoming ? 'Incoming' : 'Outgoing',
    CallLogStatus.dialed => 'Outgoing',
  };
}

/// Builds the "Recent Call Logs" feed: every call from the last [retention]
/// window, newest first, each resolved to a saved contact.
///
/// One row per call, not per person — calling the same contact three times
/// produces three rows, which is what makes Home's "30 then 10 more" paging
/// and the See All screen's full history meaningful.
///
/// The feed is driven by `call_logs` rather than the contact book, so synced
/// device contacts that were never called never appear. Calls to or from a
/// number with no saved contact (ad-hoc dialer numbers, unknown incoming
/// callers) still get a row, backed by a contact synthesized from the log
/// entry itself.
List<RecentCallLog> buildRecentCallLogs(
  List<CallLogEntry> entries,
  List<ContactModel> contacts, {
  DateTime? now,
  Duration retention = kCallLogRetention,
  int? limit,
}) {
  final byId = <String, ContactModel>{
    for (final c in contacts)
      if (c.id.isNotEmpty) c.id: c,
  };
  final byPhone = <String, ContactModel>{
    for (final c in contacts)
      if (normalizePhoneForMatching(c.phoneNumber).isNotEmpty)
        normalizePhoneForMatching(c.phoneNumber): c,
  };

  // Firestore already orders by startedAt descending, but a just-written entry
  // carries a pending server timestamp that reads as null locally and would
  // sort to the bottom. Treat null as "happened just now" so the call the user
  // has this second stays on top — and so the dedupe below keeps the right one.
  final ordered = [...entries]
    ..sort((a, b) {
      final at = a.startedAt ?? a.createdAt;
      final bt = b.startedAt ?? b.createdAt;
      if (at == null && bt == null) return 0;
      if (at == null) return -1;
      if (bt == null) return 1;
      return bt.compareTo(at);
    });

  final cutoff = (now ?? DateTime.now()).subtract(retention);
  final rows = <RecentCallLog>[];
  for (final entry in ordered) {
    // A pending server timestamp reads as null locally — that is the call the
    // user is placing right now, so it is never expired.
    final occurredAt = entry.startedAt ?? entry.createdAt;
    if (occurredAt != null && !occurredAt.isAfter(cutoff)) continue;

    final normalized = normalizePhoneForMatching(entry.calleePhone);
    final contact =
        (entry.contactId.isEmpty ? null : byId[entry.contactId]) ??
        (normalized.isEmpty ? null : byPhone[normalized]);

    rows.add(
      RecentCallLog(entry: entry, contact: contact ?? _contactFromLog(entry)),
    );
    if (limit != null && rows.length >= limit) break;
  }
  return rows;
}

/// Stand-in contact for a call to/from a number that was never saved. The id is
/// left empty, which callers use to suppress navigation into contact details.
ContactModel _contactFromLog(CallLogEntry entry) {
  final name = entry.calleeName.trim();
  return ContactModel(
    id: '',
    fullName: name.isNotEmpty
        ? name
        : (entry.calleePhone.isNotEmpty ? entry.calleePhone : 'Unknown'),
    phoneNumber: entry.calleePhone,
    updatedAt: entry.startedAt ?? entry.createdAt,
  );
}

/// The "Recent Call Logs" feed: the full last-seven-days history, newest
/// first. Home renders a paged slice of it; the See All screen renders all of
/// it.
/// The raw `call_logs` subscription, deliberately depending on nothing but the
/// repository.
///
/// Kept separate from [recentCallLogsProvider] so that a contacts update can
/// never tear this down. When the join lived inside a single StreamProvider
/// that also watched `allContactsProvider`, every contacts emission re-ran the
/// create function — cancelling this Firestore listener, opening a new one, and
/// resetting the provider to `AsyncLoading`. Since `snapshots()` fires twice on
/// open (cache, then server), the feeds visibly flipped skeleton → content →
/// skeleton → content on entry, which read as the screen jerking.
final callLogEntriesProvider = StreamProvider.autoDispose<List<CallLogEntry>>((
  ref,
) {
  return ref.watch(callLogRepositoryProvider).watchCallLogs();
});

/// Joins the call-log stream to the contact book.
///
/// A plain [Provider], so a contacts emission recomputes only this cheap join
/// and leaves the underlying subscription — and its `AsyncData` — untouched.
/// Exposes `AsyncValue` so consumers keep using `.when(...)` unchanged.
final recentCallLogsProvider =
    Provider.autoDispose<AsyncValue<List<RecentCallLog>>>((ref) {
      // Contacts only enrich the rows (photo, favorite, captured location) —
      // the name and number come from the log itself, so rows still render
      // correctly while the contact list is loading.
      final contacts =
          ref.watch(allContactsProvider).value ?? const <ContactModel>[];
      return ref
          .watch(callLogEntriesProvider)
          .whenData((entries) => buildRecentCallLogs(entries, contacts));
    });

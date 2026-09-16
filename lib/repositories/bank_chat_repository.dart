import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metadata/models/bank_detail.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Bank Chat storage — **device-local, by design**.
///
/// Banking details never touch Firestore, Storage, or any network call. That
/// is a requirement of the feature, not an optimisation: the app deliberately
/// does not connect to a bank, and account numbers are not ours to
/// synchronise across devices or hold on a server. Everything lives in
/// [SharedPreferences] on this handset and leaves it only when the user
/// themselves copies a field to the clipboard.
///
/// A consequence worth knowing: these entries are not backed up with the
/// account. Reinstalling the app, or signing in on a second phone, starts with
/// an empty Bank Chat.
class BankChatRepository {
  BankChatRepository(this._prefs);

  final SharedPreferences _prefs;

  /// Scoped per contact, so each person's Bank Chat is independent.
  static String _key(String contactId) => 'bank_chat_v1_$contactId';

  /// Always a *growable* list. [BankDetail.decodeList] hands back a const
  /// empty list when there is nothing stored, and [save]/[delete] mutate what
  /// they read — so returning that directly made the very first save on a
  /// contact throw "Cannot add to an unmodifiable list".
  List<BankDetail> read(String contactId) {
    if (contactId.isEmpty) return <BankDetail>[];
    return List<BankDetail>.of(
      BankDetail.decodeList(_prefs.getString(_key(contactId))),
    );
  }

  Future<void> _write(String contactId, List<BankDetail> details) async {
    if (contactId.isEmpty) return;
    if (details.isEmpty) {
      await _prefs.remove(_key(contactId));
      return;
    }
    await _prefs.setString(
      _key(contactId),
      BankDetail.encodeList(details.take(kMaxBankDetails).toList()),
    );
  }

  /// Adds a new entry, or replaces the one with the same id.
  ///
  /// Returns false when the entry is new and the contact already holds
  /// [kMaxBankDetails] — the caller shows the "limit reached" message rather
  /// than this silently dropping the write.
  Future<bool> save(String contactId, BankDetail detail) async {
    final details = read(contactId);
    final index = details.indexWhere((d) => d.id == detail.id);
    if (index >= 0) {
      details[index] = detail;
    } else {
      if (details.length >= kMaxBankDetails) return false;
      details.add(detail);
    }
    await _write(contactId, details);
    return true;
  }

  Future<void> delete(String contactId, String id) async {
    final details = read(contactId)..removeWhere((d) => d.id == id);
    await _write(contactId, details);
  }

  Future<void> clear(String contactId) => _write(contactId, const []);
}

/// The local store, injected by `main()`.
///
/// Nullable, and null by default, rather than throwing when unset. Two
/// reasons: a widget test that renders a contact screen has no business
/// booting the whole app just to satisfy Bank Chat, and a missing store must
/// degrade *visibly* rather than take a screen down. When this is null Bank
/// Chat reports itself unavailable and refuses to save — it never pretends a
/// write succeeded, so there is no path here that loses a user's banking
/// details.
final sharedPreferencesProvider = Provider<SharedPreferences?>((ref) => null);

/// Null when [sharedPreferencesProvider] has not been overridden.
final bankChatRepositoryProvider = Provider<BankChatRepository?>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return prefs == null ? null : BankChatRepository(prefs);
});

/// Whether Bank Chat can actually store anything on this device.
final bankChatAvailableProvider = Provider<bool>((ref) {
  return ref.watch(bankChatRepositoryProvider) != null;
});

/// The Bank Chat entries for one contact.
///
/// A [Notifier] rather than a stream: the store is local and synchronous, so
/// there is nothing to await and no snapshot to listen to — mutations just
/// rewrite the list and notify.
class BankChatNotifier extends Notifier<List<BankDetail>> {
  BankChatNotifier(this.contactId);

  final String contactId;

  @override
  List<BankDetail> build() {
    return ref.watch(bankChatRepositoryProvider)?.read(contactId) ??
        <BankDetail>[];
  }

  bool get isFull => state.length >= kMaxBankDetails;

  /// False when the entry was rejected — either the contact is already at
  /// [kMaxBankDetails], or there is no store to write to.
  Future<bool> save(BankDetail detail) async {
    final repo = ref.read(bankChatRepositoryProvider);
    if (repo == null) return false;
    final ok = await repo.save(contactId, detail);
    if (ok) state = repo.read(contactId);
    return ok;
  }

  Future<void> delete(String id) async {
    final repo = ref.read(bankChatRepositoryProvider);
    if (repo == null) return;
    await repo.delete(contactId, id);
    state = repo.read(contactId);
  }
}

final bankChatProvider =
    NotifierProvider.family<BankChatNotifier, List<BankDetail>, String>(
      BankChatNotifier.new,
    );

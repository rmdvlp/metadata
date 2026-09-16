import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metadata/features/calling/models/call_exception.dart';
import 'package:metadata/features/calling/models/voip_user.dart';

final firebaseFunctionsProvider = Provider<FirebaseFunctions>((ref) {
  return FirebaseFunctions.instance;
});

final voipDirectoryProvider = Provider<VoipDirectoryDataSource>((ref) {
  return VoipDirectoryDataSource(functions: ref.watch(firebaseFunctionsProvider));
});

/// Answers "does this phone number belong to someone I can call in-app?".
///
/// This goes through a callable Cloud Function rather than a client-readable
/// collection on purpose. A phone-number-to-user index that clients can query
/// directly is a phone book: anyone with an account could walk it and harvest
/// names and photos for arbitrary numbers. Keeping the index server-only
/// means lookups are authenticated, batched, and rate-limitable.
class VoipDirectoryDataSource {
  VoipDirectoryDataSource({required FirebaseFunctions functions}) : _functions = functions;

  final FirebaseFunctions _functions;

  /// Cached across the session so browsing contact lists does not re-query
  /// the same numbers on every rebuild. Cleared on sign-out via [clearCache].
  final Map<String, VoipUser?> _cache = {};

  static const int _batchLimit = 200;

  /// Resolves many numbers at once. Numbers already cached are served locally
  /// and never re-sent.
  Future<Map<String, VoipUser>> resolve(List<String> phoneNumbers) async {
    final unknown = phoneNumbers
        .where((p) => p.isNotEmpty && !_cache.containsKey(p))
        .toSet()
        .toList();

    for (var i = 0; i < unknown.length; i += _batchLimit) {
      final chunk = unknown.sublist(
        i,
        i + _batchLimit > unknown.length ? unknown.length : i + _batchLimit,
      );
      await _fetch(chunk);
    }

    final result = <String, VoipUser>{};
    for (final phone in phoneNumbers) {
      final user = _cache[phone];
      if (user != null) result[phone] = user;
    }
    return result;
  }

  Future<VoipUser?> resolveOne(String phoneNumber) async {
    final matches = await resolve([phoneNumber]);
    return matches[phoneNumber];
  }

  Future<void> _fetch(List<String> chunk) async {
    try {
      final response = await _functions
          .httpsCallable('resolveVoipUsers')
          .call<Map<String, dynamic>>({'phoneNumbers': chunk});

      final matches = (response.data['matches'] as Map?) ?? const {};
      // Seed every requested number, including misses, so a contact who is
      // not an app user is not looked up again and again.
      for (final phone in chunk) {
        final raw = matches[phone];
        _cache[phone] = raw is Map
            ? VoipUser.fromMap(Map<String, dynamic>.from(raw))
            : null;
      }
    } on FirebaseFunctionsException catch (e) {
      throw CallException(CallFailure.signalingUnavailable, cause: e);
    }
  }

  void clearCache() => _cache.clear();
}

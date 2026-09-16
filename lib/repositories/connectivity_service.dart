import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// True when the device currently has a network connection. This does not
/// guarantee Firestore reachability (e.g. captive portals), but it's the
/// same best-effort signal every offline-banner implementation uses — the
/// actual "did the write really land" guarantee comes from Firestore's own
/// offline persistence, which queues writes locally and flushes them once a
/// connection is available regardless of what this stream reports.
final connectivityStatusProvider = StreamProvider<bool>((ref) async* {
  final connectivity = Connectivity();
  yield _isOnline(await connectivity.checkConnectivity());
  yield* connectivity.onConnectivityChanged.map(_isOnline);
});

bool _isOnline(List<ConnectivityResult> results) {
  return results.any((r) => r != ConnectivityResult.none);
}

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

final dialerServiceProvider = Provider<DialerService>((ref) => DialerService());

/// Places real telephony calls. Deliberately stateless/swappable so a
/// future in-app VoIP integration (e.g. Agora) can replace it without
/// touching call sites.
class DialerService {
  static const _methodChannel = MethodChannel('com.metadata.calls/methods');

  /// On Android, tries to place the call directly (no extra tap needed —
  /// see `MainActivity.placeCallDirectly`), which only works once the
  /// CALL_PHONE runtime permission has been granted (via the "Allow Calls"
  /// permission prompt). Falls back to opening the native dialer pre-filled
  /// otherwise — same as always on iOS, where Apple gives no API to place a
  /// call without the user confirming in the system's own UI.
  Future<bool> callNumber(String phoneNumber) async {
    if (Platform.isAndroid) {
      final placedDirectly = await _tryPlaceCallDirectly(phoneNumber);
      if (placedDirectly) return true;
    }

    final uri = Uri(scheme: 'tel', path: phoneNumber);
    if (!await canLaunchUrl(uri)) return false;
    return launchUrl(uri);
  }

  Future<bool> _tryPlaceCallDirectly(String phoneNumber) async {
    try {
      final result = await _methodChannel.invokeMethod<bool>('placeCall', {
        'phoneNumber': phoneNumber,
      });
      return result ?? false;
    } catch (_) {
      return false;
    }
  }
}

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metadata/core/firebase/fcm_token.dart';

/// A stand-in for [FirebaseMessaging] covering only the two calls
/// [resolveFcmToken] makes. `noSuchMethod` absorbs the rest of the (large)
/// surface so the fake doesn't have to track the plugin's API.
class _FakeMessaging implements FirebaseMessaging {
  _FakeMessaging({
    this.apnsToken,
    this.getTokenThrows = false,
    this.apnsTokenAfter = 0,
  });

  String? apnsToken;
  final bool getTokenThrows;

  /// What a successful `getToken` returns. Fixed — no test needs to vary it.
  static const String fcmToken = 'fcm-token';

  /// Number of `getAPNSToken` calls to answer with null before [apnsToken]
  /// starts being returned — models APNs registration completing mid-wait.
  final int apnsTokenAfter;

  int apnsCalls = 0;
  int getTokenCalls = 0;

  @override
  Future<String?> getAPNSToken() async {
    apnsCalls++;
    if (apnsCalls <= apnsTokenAfter) return null;
    return apnsToken;
  }

  @override
  Future<String?> getToken({
    String? vapidKey,
    String? serviceWorkerScriptPath,
  }) async {
    getTokenCalls++;
    if (getTokenThrows) {
      throw FirebaseException(
        plugin: 'firebase_messaging',
        code: 'apns-token-not-set',
        message: 'APNS token has not been set yet.',
      );
    }
    return fcmToken;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('resolveFcmToken', () {
    test('on Android it asks for the token without waiting on APNs', () async {
      final messaging = _FakeMessaging();

      final token = await resolveFcmToken(messaging, isIOS: false);

      expect(token, 'fcm-token');
      expect(messaging.apnsCalls, 0, reason: 'APNs is an iOS-only concept');
    });

    test(
      'on iOS it waits for the APNs token before asking for the FCM one',
      () async {
        // Null for the first two polls, then APNs registration completes.
        final messaging = _FakeMessaging(apnsToken: 'apns', apnsTokenAfter: 2);

        final token = await resolveFcmToken(
          messaging,
          isIOS: true,
          apnsTimeout: const Duration(seconds: 5),
        );

        expect(token, 'fcm-token');
        expect(messaging.apnsCalls, 3);
      },
    );

    test(
      'gives up quietly when APNs never registers, rather than hanging or throwing',
      () async {
        // A Simulator, or a device with no push entitlement: no APNs token ever.
        final messaging = _FakeMessaging(apnsToken: null);

        final token = await resolveFcmToken(
          messaging,
          isIOS: true,
          apnsTimeout: const Duration(milliseconds: 600),
        );

        expect(token, isNull);
        expect(
          messaging.getTokenCalls,
          0,
          reason: 'getToken would only throw apns-token-not-set here',
        );
      },
    );

    test(
      'swallows apns-token-not-set instead of letting it abort the caller',
      () async {
        // The regression this helper exists for: the throw used to escape
        // MessagingService.initialize(), which aborted it before onMessage was
        // ever subscribed — so iOS silently lost every foreground notification
        // for the rest of the session.
        final messaging = _FakeMessaging(
          apnsToken: 'apns',
          getTokenThrows: true,
        );

        final token = await resolveFcmToken(messaging, isIOS: true);

        expect(token, isNull);
      },
    );
  });
}

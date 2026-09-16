import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metadata/repositories/phone_number_update_service.dart';
import 'package:metadata/screens/change_phone_number_screen.dart';

/// Changing the account's own number: the code has to go to the number the
/// user actually typed, and nothing may move until that code checks out.
const _screen = Size(1080, 2200);
const _currentNumber = '+15551234567';

class _FakeUpdater implements PhoneNumberUpdateService {
  /// The E.164 string handed to Firebase — i.e. the number that would
  /// receive the SMS.
  String? sentTo;
  int? sentResendToken;
  String? confirmedCode;
  int sendCount = 0;

  Object? sendError;
  Object? confirmError;

  @override
  String? currentPhoneNumber = _currentNumber;

  @override
  Future<PhoneVerificationOutcome> sendVerificationCode({
    required String phoneNumber,
    int? resendToken,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    sendCount++;
    sentTo = phoneNumber;
    sentResendToken = resendToken;
    final error = sendError;
    if (error != null) throw error;
    return const CodeSent(verificationId: 'verification-id', resendToken: 77);
  }

  @override
  Future<void> confirmCode({
    required String verificationId,
    required String smsCode,
  }) async {
    confirmedCode = smsCode;
    final error = confirmError;
    if (error != null) throw error;
  }

  @override
  Future<void> applyCredential(PhoneAuthCredential credential) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeUpdater updater;

  setUp(() => updater = _FakeUpdater());

  /// Pushes the screen onto a route stack so it has somewhere to pop back to.
  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(_screen);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          phoneNumberUpdateServiceProvider.overrideWithValue(updater),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<bool>(
                      builder: (_) => const ChangePhoneNumberScreen(
                        currentPhoneNumber: _currentNumber,
                      ),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Future<void> typeNumber(WidgetTester tester, String number) async {
    await tester.enterText(find.byType(TextField), number);
    await tester.pump();
  }

  /// Bounded rather than [WidgetTester.pumpAndSettle]: once a code has been
  /// sent the resend countdown ticks forever, so nothing ever "settles".
  /// Short enough that the countdown does not advance during it.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  Future<void> sendCode(WidgetTester tester) async {
    await tester.tap(find.text('Send Code'));
    await settle(tester);
  }

  testWidgets('the code goes to the number the user typed, in E.164', (
    tester,
  ) async {
    await pumpScreen(tester);
    await typeNumber(tester, '(555) 987-6543');
    await sendCode(tester);

    expect(updater.sentTo, '+15559876543');
  });

  testWidgets('a leading 0 is a trunk prefix, not part of the number', (
    tester,
  ) async {
    // Glued on naively this sends to +10300…, a number the user does not own
    // — so the SMS never arrives and nothing explains why.
    await pumpScreen(tester);
    await typeNumber(tester, '0300 1234567');
    await sendCode(tester);

    expect(updater.sentTo, '+13001234567');
  });

  testWidgets('a number typed in full keeps its own country code', (
    tester,
  ) async {
    await pumpScreen(tester);
    await typeNumber(tester, '+92 300 1234567');
    await sendCode(tester);

    expect(updater.sentTo, '+923001234567');
  });

  testWidgets('the code step names the number it was sent to', (tester) async {
    await pumpScreen(tester);
    await typeNumber(tester, '5559876543');
    await sendCode(tester);

    // So a wrong number is caught here rather than after waiting on an SMS.
    expect(find.textContaining('+15559876543'), findsOneWidget);
  });

  testWidgets('an unusable number never reaches Firebase', (tester) async {
    await pumpScreen(tester);
    await typeNumber(tester, '123');
    await sendCode(tester);

    expect(updater.sendCount, 0);
    expect(find.textContaining('valid phone number'), findsOneWidget);
  });

  testWidgets('an empty number never reaches Firebase', (tester) async {
    await pumpScreen(tester);
    await sendCode(tester);

    expect(updater.sendCount, 0);
    expect(find.text('Please enter a mobile number'), findsOneWidget);
  });

  testWidgets('re-entering the current number is refused', (tester) async {
    await pumpScreen(tester);
    await typeNumber(tester, _currentNumber);
    await sendCode(tester);

    expect(updater.sendCount, 0);
    expect(
      find.text('That is already the number on your account.'),
      findsOneWidget,
    );
  });

  testWidgets('the typed code is what gets confirmed, and the screen closes', (
    tester,
  ) async {
    await pumpScreen(tester);
    await typeNumber(tester, '5559876543');
    await sendCode(tester);

    await tester.enterText(find.byType(EditableText), '123456');
    await settle(tester);

    expect(updater.confirmedCode, '123456');
    expect(find.byType(ChangePhoneNumberScreen), findsNothing);
    expect(find.textContaining('Your number is now +15559876543'), findsOneWidget);
  });

  testWidgets('a wrong code leaves the user on the screen with a reason', (
    tester,
  ) async {
    updater.confirmError = FirebaseAuthException(
      code: 'invalid-verification-code',
    );

    await pumpScreen(tester);
    await typeNumber(tester, '5559876543');
    await sendCode(tester);

    await tester.enterText(find.byType(EditableText), '000000');
    await settle(tester);

    expect(find.byType(ChangePhoneNumberScreen), findsOneWidget);
    expect(find.text('That code is not right. Check it and try again.'),
        findsOneWidget);
  });

  testWidgets('a number already in use says so, in plain words', (
    tester,
  ) async {
    updater.sendError = FirebaseAuthException(
      code: 'credential-already-in-use',
    );

    await pumpScreen(tester);
    await typeNumber(tester, '5559876543');
    await sendCode(tester);

    expect(
      find.text('That number is already used by another account.'),
      findsOneWidget,
    );
  });
}

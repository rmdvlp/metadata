import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metadata/core/firebase/firebase_providers.dart';
import 'package:metadata/screens/edit_profile_screen.dart';
import 'package:metadata/screens/profile_screen.dart';

/// Renaming the device owner.
///
/// Profile itself is read-only now — photo, name and number were three
/// separate edit affordances and are one Edit Profile screen instead — so
/// every rename goes through that form.
const _uid = 'test-uid';
const _screen = Size(1080, 2200);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const contactsChannel = MethodChannel('flutter_contacts');

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          contactsChannel,
          (MethodCall call) async => 'denied',
        );
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(contactsChannel, null);
  });

  late FakeFirebaseFirestore firestore;
  late MockFirebaseAuth auth;

  DocumentReference<Map<String, dynamic>> userDoc() =>
      firestore.collection('users').doc(_uid);

  setUp(() async {
    firestore = FakeFirebaseFirestore();
    auth = MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: _uid));
    await userDoc().set({
      'uid': _uid,
      'displayName': 'Ada Lovelace',
      'phoneNumber': '+15551234567',
      'permissionsPrompted': true,
    });
  });

  Future<void> pumpProfile(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(_screen);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          firebaseAuthProvider.overrideWithValue(auth),
          firebaseFirestoreProvider.overrideWithValue(firestore),
        ],
        child: MaterialApp(
          builder: EasyLoading.init(),
          home: const ProfileScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// The blue pen beside the name — the only edit affordance on Profile.
  Future<void> openEditProfile(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();
  }

  /// The name field is the only [TextField] on the form — the number is a
  /// read-only row with its own Change action.
  Finder nameField() => find.descendant(
    of: find.byType(EditProfileScreen),
    matching: find.byType(TextField),
  );

  testWidgets('Profile offers one way in, not three', (tester) async {
    await pumpProfile(tester);

    // A single blue pen beside the name, covering the whole profile. The
    // second pen that used to sit on the number, and the camera badge on the
    // avatar, are gone.
    expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
    expect(find.byIcon(Icons.camera_alt_rounded), findsNothing);

    final pen = tester.getRect(find.byIcon(Icons.edit_outlined));
    final name = tester.getRect(find.text('Ada Lovelace'));
    expect(pen.left, greaterThan(name.right - 1), reason: 'pen follows name');
    expect(pen.center.dy, closeTo(name.center.dy, 2.0));
  });

  testWidgets('the pen opens the whole-profile form, not a name dialog', (
    tester,
  ) async {
    await pumpProfile(tester);
    await openEditProfile(tester);

    expect(find.byType(EditProfileScreen), findsOneWidget);
    // Everything editable is on that one screen.
    expect(find.text('Full Name'), findsOneWidget);
    expect(find.text('Phone Number'), findsOneWidget);
    // This account has no picture yet, so the photo action invites one.
    expect(find.text('Add Photo'), findsOneWidget);
  });

  testWidgets('the form opens pre-filled with the current name', (
    tester,
  ) async {
    await pumpProfile(tester);
    await openEditProfile(tester);

    expect(nameField(), findsOneWidget);
    expect(
      tester.widget<TextField>(nameField()).controller!.text,
      'Ada Lovelace',
    );
  });

  testWidgets('saving renames the user and returns to Profile', (tester) async {
    await pumpProfile(tester);
    await openEditProfile(tester);

    await tester.enterText(nameField(), 'Ada King');
    await tester.pump();
    await tester.tap(find.text('Save Changes'));
    await settle(tester);

    expect((await userDoc().get()).data()!['displayName'], 'Ada King');
    expect(find.byType(EditProfileScreen), findsNothing);
    expect(find.text('Ada King'), findsOneWidget);
  });

  testWidgets('Save stays disabled until something actually changes', (
    tester,
  ) async {
    await pumpProfile(tester);
    await openEditProfile(tester);

    // Nothing edited yet, so there is nothing to save.
    final button = tester.widget<ElevatedButton>(
      find.ancestor(
        of: find.text('Save Changes'),
        matching: find.byType(ElevatedButton),
      ),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('backing out of an edit discards it', (tester) async {
    await pumpProfile(tester);
    await openEditProfile(tester);

    await tester.enterText(nameField(), 'Discarded');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await tester.pumpAndSettle();

    // Unsaved edits are confirmed rather than silently thrown away.
    expect(find.text('Discard changes?'), findsOneWidget);
    await tester.tap(find.text('Discard'));
    await settle(tester);

    expect((await userDoc().get()).data()!['displayName'], 'Ada Lovelace');
  });

  testWidgets('an empty name is refused, not saved', (tester) async {
    await pumpProfile(tester);
    await openEditProfile(tester);

    await tester.enterText(nameField(), '   ');
    await tester.pump();
    await tester.tap(find.text('Save Changes'));
    await tester.pump();

    // Saving blank would bounce the user back through the name-setup gate on
    // next launch.
    expect(find.text('Please enter a name.'), findsOneWidget);
    expect((await userDoc().get()).data()!['displayName'], 'Ada Lovelace');
  });

  testWidgets('renaming leaves the phone number untouched', (tester) async {
    await pumpProfile(tester);
    await openEditProfile(tester);

    await tester.enterText(nameField(), 'Ada King');
    await tester.pump();
    await tester.tap(find.text('Save Changes'));
    await settle(tester);

    expect((await userDoc().get()).data()!['phoneNumber'], '+15551234567');
    expect(find.text('+15551234567'), findsOneWidget);
  });

  group('the phone number below the name', () {
    testWidgets('shows the number from the profile', (tester) async {
      await pumpProfile(tester);

      expect(find.text('+15551234567'), findsOneWidget);
    });

    testWidgets('falls back to the signed-in account when the profile field '
        'is empty', (tester) async {
      // A profile doc written without a number — previously this rendered a
      // blank line, because the null-check never fired for an empty string.
      await userDoc().set({
        'uid': _uid,
        'displayName': 'Ada Lovelace',
        'phoneNumber': '',
        'permissionsPrompted': true,
      });
      auth = MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: _uid, phoneNumber: '+15559998888'),
      );

      await pumpProfile(tester);

      expect(find.text('+15559998888'), findsOneWidget);
    });

    testWidgets('shows no invented number when it is genuinely unknown', (
      tester,
    ) async {
      await userDoc().set({
        'uid': _uid,
        'displayName': 'Ada Lovelace',
        'phoneNumber': '',
        'permissionsPrompted': true,
      });
      auth = MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: _uid));

      await pumpProfile(tester);

      // The old placeholder read as though it were the user's real number.
      expect(find.text('+1 000 000 0000'), findsNothing);
      expect(find.text('No number yet'), findsOneWidget);
    });
  });
}

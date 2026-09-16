import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metadata/core/firebase/firebase_providers.dart';
import 'package:metadata/core/firebase/firebase_services.dart';
import 'package:metadata/screens/change_phone_number_screen.dart';
import 'package:metadata/screens/edit_profile_screen.dart';
import 'package:metadata/screens/profile_screen.dart';
import 'package:metadata/widgets/contact_avatar.dart';

/// The device owner editing their own profile: the picture, and the number
/// the account is identified by.
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

  setUp(() {
    firestore = FakeFirebaseFirestore();
    auth = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: _uid, phoneNumber: '+15551234567'),
    );
  });

  Future<void> writeProfile({String? photoUrl}) {
    return userDoc().set({
      'uid': _uid,
      'displayName': 'Ada Lovelace',
      'phoneNumber': '+15551234567',
      'permissionsPrompted': true,
      'photoUrl': ?photoUrl,
    });
  }

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

  /// The blue pen beside the name — the only edit affordance on Profile.
  Future<void> openEditProfile(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();
  }

  group('the number on the edit form', () {
    testWidgets('is read-only, with a Change action of its own', (
      tester,
    ) async {
      await writeProfile();
      await pumpProfile(tester);
      await openEditProfile(tester);

      // The number is what the account signs in with, so unlike the name it
      // is not a field on this form — it has to receive a code first.
      expect(
        find.descendant(
          of: find.byType(EditProfileScreen),
          matching: find.byType(TextField),
        ),
        findsOneWidget,
        reason: 'the name is the only editable field',
      );
      expect(find.text('+15551234567'), findsOneWidget);
      expect(find.text('Change'), findsOneWidget);
    });

    testWidgets('Change opens the verification flow, not a text field', (
      tester,
    ) async {
      await writeProfile();
      await pumpProfile(tester);
      await openEditProfile(tester);

      await tester.tap(find.text('Change'));
      await tester.pumpAndSettle();

      expect(find.byType(ChangePhoneNumberScreen), findsOneWidget);
      expect(find.text('Send Code'), findsOneWidget);
    });

    testWidgets('the flow is told which number it is replacing', (
      tester,
    ) async {
      await writeProfile();
      await pumpProfile(tester);
      await openEditProfile(tester);

      await tester.tap(find.text('Change'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('currently uses +15551234567'),
        findsOneWidget,
      );
    });

    testWidgets('an account with no number still offers to add one', (
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
      await openEditProfile(tester);

      expect(find.text('No number on this account'), findsOneWidget);
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      expect(find.byType(ChangePhoneNumberScreen), findsOneWidget);
    });
  });

  group('the profile picture', () {
    /// Scoped to the edit form: Profile's own avatar is still in the tree
    /// underneath the pushed route.
    Future<void> tapAvatar(WidgetTester tester) async {
      await tester.tap(
        find.descendant(
          of: find.byType(EditProfileScreen),
          matching: find.byType(ContactAvatar),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('offers removing it only when there is one', (tester) async {
      await writeProfile();
      await pumpProfile(tester);
      await openEditProfile(tester);
      await tapAvatar(tester);

      // A "Remove Photo" row on an account with no photo is a dead control.
      expect(find.text('Remove Photo'), findsNothing);
      expect(find.text('Take Photo'), findsOneWidget);
      expect(find.text('Choose from Gallery'), findsOneWidget);
    });

    testWidgets('offers removing it once one is set', (tester) async {
      await writeProfile(photoUrl: 'https://example.com/me.jpg');
      await pumpProfile(tester);
      await openEditProfile(tester);
      await tapAvatar(tester);

      expect(find.text('Remove Photo'), findsOneWidget);
    });

    testWidgets('a staged removal is not applied until Save', (tester) async {
      await writeProfile(photoUrl: 'https://example.com/me.jpg');
      await pumpProfile(tester);
      await openEditProfile(tester);
      await tapAvatar(tester);

      await tester.tap(find.text('Remove Photo'));
      await tester.pumpAndSettle();

      // The form stages photo edits and commits them with Save, so backing
      // out has to leave the stored photo alone.
      expect(find.text('Photo will be removed when you save.'), findsOneWidget);
      expect(
        (await userDoc().get()).data()!['photoUrl'],
        'https://example.com/me.jpg',
      );
    });
  });

  group('createInitialProfile', () {
    UserProfileService service() => UserProfileService(
      firestore: firestore,
      auth: auth,
      // Never resolved: nothing here touches Storage, and a real instance
      // cannot be built in a test.
      storageReader: () => throw StateError('Storage must not be used'),
    );

    test('records the number Firebase verified, not the one typed', () async {
      // The login field holds whatever was typed; the auth record holds the
      // canonical E.164 Firebase actually signed the user in with.
      await service().createInitialProfile(phoneNumber: '555 123 4567');

      expect((await userDoc().get()).data()!['phoneNumber'], '+15551234567');
    });

    test('backfills a number missing from an existing profile', () async {
      await userDoc().set({
        'uid': _uid,
        'displayName': 'Ada Lovelace',
        'phoneNumber': '',
        'permissionsPrompted': true,
      });

      await service().createInitialProfile(phoneNumber: '+15551234567');

      // Sign-up used to be the only writer of this field, so a profile
      // created any other way kept an empty one forever.
      expect((await userDoc().get()).data()!['phoneNumber'], '+15551234567');
    });

    test('leaves the rest of an existing profile alone', () async {
      await userDoc().set({
        'uid': _uid,
        'displayName': 'Ada Lovelace',
        'phoneNumber': '',
        'permissionsPrompted': true,
      });

      await service().createInitialProfile(phoneNumber: '+15551234567');

      final data = (await userDoc().get()).data()!;
      expect(data['displayName'], 'Ada Lovelace');
      expect(data['permissionsPrompted'], isTrue);
    });

    test('does not overwrite a number already on the profile', () async {
      await userDoc().set({
        'uid': _uid,
        'displayName': 'Ada Lovelace',
        'phoneNumber': '+441234567890',
        'permissionsPrompted': true,
      });

      await service().createInitialProfile(phoneNumber: '+15551234567');

      expect((await userDoc().get()).data()!['phoneNumber'], '+441234567890');
    });
  });

  group('updatePhoneNumber', () {
    test('writes the new number onto the profile', () async {
      await writeProfile();

      await UserProfileService(
        firestore: firestore,
        auth: auth,
        storageReader: () => throw StateError('Storage must not be used'),
      ).updatePhoneNumber('+15559876543');

      expect((await userDoc().get()).data()!['phoneNumber'], '+15559876543');
    });
  });
}

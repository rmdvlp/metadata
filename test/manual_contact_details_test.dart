import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metadata/core/firebase/firebase_providers.dart';
import 'package:metadata/models/contact_model.dart';
import 'package:metadata/screens/capture_context.dart';
import 'package:metadata/screens/contact_screen.dart';
import 'package:metadata/screens/event_detail.dart';

/// A manually saved contact must be able to gain everything a captured one
/// has — location, role, encounter date and time — from its edit screen.
const _uid = 'test-uid';
const _contactId = 'c1';
const _screen = Size(1080, 2200);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const locationChannel = MethodChannel('lyokone/location');

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(locationChannel, (MethodCall call) async {
          switch (call.method) {
            case 'serviceEnabled':
            case 'requestService':
              return 1;
            case 'hasPermission':
            case 'requestPermission':
              return 0; // denied
            default:
              return null;
          }
        });
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(locationChannel, null);
  });

  late FakeFirebaseFirestore firestore;
  late MockFirebaseAuth auth;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    auth = MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: _uid));
  });

  DocumentReference<Map<String, dynamic>> contactDoc() => firestore
      .collection('users')
      .doc(_uid)
      .collection('contacts')
      .doc(_contactId);

  /// A contact saved with the plain "Save" button: no location, no role, no
  /// encounter date.
  ContactModel manualContact() => const ContactModel(
    id: _contactId,
    fullName: 'Ada Lovelace',
    phoneNumber: '+14155550101',
    notes: 'Met at the museum',
    capturesContext: false,
  );

  Future<void> pumpEdit(WidgetTester tester, ContactModel contact) async {
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
          home: ContactScreen(contact: contact),
        ),
      ),
    );
    await tester.pump();
  }

  group('editing a manually saved contact', () {
    testWidgets('offers both ways to add encounter details', (tester) async {
      await pumpEdit(tester, manualContact());

      expect(find.text('Encounter Details'), findsOneWidget);
      expect(find.text('Capture location automatically'), findsOneWidget);
      expect(find.text('Edit encounter details'), findsOneWidget);
    });

    testWidgets('the add form shows neither — the two buttons cover it', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(_screen);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: ContactScreen())),
      );
      await tester.pump();

      expect(find.text('Encounter Details'), findsNothing);
      expect(find.text('Edit encounter details'), findsNothing);
    });

    testWidgets('GPS capture opens the capture screen', (tester) async {
      await pumpEdit(tester, manualContact());

      await tester.tap(find.text('Capture location automatically'));
      await tester.pumpAndSettle();

      expect(find.byType(CaptureContextScreen), findsOneWidget);
    });

    testWidgets('the typed-in route opens the full details editor', (
      tester,
    ) async {
      await pumpEdit(tester, manualContact());

      await tester.tap(find.text('Edit encounter details'));
      await tester.pumpAndSettle();

      expect(find.byType(EventDetailScreen), findsOneWidget);
      expect(find.text('Edit Details'), findsOneWidget);
    });

    testWidgets('a contact that already has a place shows it instead of the '
        'prompt', (tester) async {
      await pumpEdit(
        tester,
        ContactModel(
          id: _contactId,
          fullName: 'Ada Lovelace',
          phoneNumber: '+14155550101',
          capturesContext: false,
          location: const ContactLocation(
            lat: 28.6139,
            lng: 77.2090,
            placeName: 'Sample Cafe',
            address: 'Connaught Place, Delhi',
          ),
        ),
      );

      expect(find.text('Sample Cafe'), findsOneWidget);
      expect(find.text('Capture location automatically'), findsNothing);
    });
  });

  group('the details editor keeps what it was not asked to change', () {
    testWidgets('an existing role and note survive a save', (tester) async {
      await contactDoc().set({
        'fullName': 'Ada Lovelace',
        'phoneNumber': '+14155550101',
        'role': 'Mentor',
        'notes': 'Met at the museum',
        'capturesContext': false,
        'createdAt': Timestamp.now(),
        'updatedAt': Timestamp.now(),
      });

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
            // Opened the way the edit screen opens it: seeded from the
            // contact. Saving writes role and notes unconditionally, so an
            // unseeded editor would blank them both.
            home: const EventDetailScreen(
              contactId: _contactId,
              initialRole: 'Mentor',
              initialNotes: 'Met at the museum',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save'));
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      final saved = (await contactDoc().get()).data()!;
      expect(saved['role'], 'Mentor');
      expect(saved['notes'], 'Met at the museum');
    });
  });
}

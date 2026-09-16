import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metadata/core/firebase/firebase_providers.dart';
import 'package:metadata/screens/capture_context.dart';
import 'package:metadata/screens/saved_contact_details_screen.dart';

const _uid = 'test-uid';
const _contactId = 'contact-1';
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
            case 'hasPermission':
            case 'requestPermission':
              return 1; // granted
            case 'getLocation':
              return <String, double>{
                'latitude': 28.6139,
                'longitude': 77.2090,
              };
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

  DocumentReference<Map<String, dynamic>> contactRef() => firestore
      .collection('users')
      .doc(_uid)
      .collection('contacts')
      .doc(_contactId);

  setUp(() async {
    firestore = FakeFirebaseFirestore();
    auth = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: _uid, phoneNumber: '+15551234567'),
    );
    await contactRef().set({
      'fullName': 'Ada Lovelace',
      'phoneNumber': '+14155550101',
      'source': 'manual',
      'capturesContext': true,
      'createdAt': Timestamp.now(),
      'updatedAt': Timestamp.now(),
    });
  });

  Future<void> pump(WidgetTester tester, Widget home) async {
    await tester.binding.setSurfaceSize(_screen);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          firebaseAuthProvider.overrideWithValue(auth),
          firebaseFirestoreProvider.overrideWithValue(firestore),
        ],
        child: MaterialApp(builder: EasyLoading.init(), home: home),
      ),
    );
    await tester.pump();
  }

  /// EasyLoading animates while shown, so pumpAndSettle would spin forever.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('Confirm Context stores the encounter time, not just the place', (
    tester,
  ) async {
    await pump(
      tester,
      const CaptureContextScreen(contactId: _contactId),
    );
    await settle(tester);

    final before = DateTime.now();
    await tester.tap(find.text('Confirm Context'));
    await settle(tester);

    final data = (await contactRef().get()).data()!;
    expect(data['location'], isNotNull);

    // The gap this closes: location was saved while eventDate stayed null, so
    // Contact Details showed "—" for Date and Time forever after.
    final eventDate = data['eventDate'];
    expect(eventDate, isNotNull, reason: 'encounter time must be persisted');
    final captured = (eventDate as Timestamp).toDate();
    expect(
      captured.isAfter(before.subtract(const Duration(minutes: 5))),
      isTrue,
      reason: 'should be the moment of capture',
    );
  });

  testWidgets('the saved time then actually renders on Contact Details', (
    tester,
  ) async {
    await pump(
      tester,
      const CaptureContextScreen(contactId: _contactId),
    );
    await settle(tester);

    await tester.tap(find.text('Confirm Context'));
    await settle(tester);

    // Confirm Context replaces itself with the details screen.
    expect(find.byType(SavedContactDetailsScreen), findsOneWidget);
    expect(find.text('Date'), findsOneWidget);
    expect(find.text('Time'), findsOneWidget);
    // An em dash in either slot would mean Date/Time are still empty.
    expect(find.text('—'), findsNothing);
  });
}

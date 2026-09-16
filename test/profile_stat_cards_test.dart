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
import 'package:metadata/screens/profile_screen.dart';
import 'package:metadata/screens/saved_contacts_screen.dart';

/// Profile's three counts are links: each opens Your Contacts on the tab that
/// lists exactly the contacts it counted.
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

  setUp(() async {
    firestore = FakeFirebaseFirestore();
    auth = MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: _uid));

    await firestore.collection('users').doc(_uid).set({
      'uid': _uid,
      'displayName': 'Test User',
      'phoneNumber': '+15551234567',
      'permissionsPrompted': true,
    });

    final contacts = firestore
        .collection('users')
        .doc(_uid)
        .collection('contacts');
    Future<void> add(
      String id,
      String name, {
      required ContactSource source,
      required bool capturesContext,
    }) {
      return contacts.doc(id).set({
        'fullName': name,
        'phoneNumber': '+1415555$id',
        'source': source.name,
        'capturesContext': capturesContext,
        'createdAt': Timestamp.now(),
        'updatedAt': Timestamp.now(),
      });
    }

    // 2 captured, 1 manual, 1 phone-book sync — so all (4) is deliberately
    // more than captured + manual (3).
    await add('0001', 'Captured Cara',
        source: ContactSource.manual, capturesContext: true);
    await add('0002', 'Captured Cyril',
        source: ContactSource.manual, capturesContext: true);
    await add('0003', 'Manual Mona',
        source: ContactSource.manual, capturesContext: false);
    await add('0004', 'Synced Sam',
        source: ContactSource.device, capturesContext: true);
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

  /// The pill for [label] is the active one when its text is white.
  bool tabIsActive(WidgetTester tester, String label) {
    return tester.widget<Text>(find.text(label)).style?.color == Colors.white;
  }

  testWidgets('the counts match what each tab lists', (tester) async {
    await pumpProfile(tester);

    // All Contact: 4 (includes the synced one). Captured: 2. Manual: 1.
    expect(find.text('4'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('All Contact opens Your Contacts on the All tab', (tester) async {
    await pumpProfile(tester);

    await tester.tap(find.text('All Contact'));
    await tester.pumpAndSettle();

    expect(find.byType(SavedContactsScreen), findsOneWidget);
    expect(tabIsActive(tester, 'All Contacts'), isTrue);
    expect(find.text('Captured Cara'), findsOneWidget);
    expect(find.text('Synced Sam'), findsOneWidget);
  });

  testWidgets('Captured opens Your Contacts on the Captured tab', (
    tester,
  ) async {
    await pumpProfile(tester);

    await tester.tap(find.text('Captured'));
    await tester.pumpAndSettle();

    expect(tabIsActive(tester, 'Captured'), isTrue);
    expect(find.text('Captured Cara'), findsOneWidget);
    expect(find.text('Captured Cyril'), findsOneWidget);
    expect(find.text('Manual Mona'), findsNothing);
  });

  testWidgets('Manual opens Your Contacts on the Manual tab', (tester) async {
    await pumpProfile(tester);

    await tester.tap(find.text('Manual'));
    await tester.pumpAndSettle();

    expect(tabIsActive(tester, 'Manual'), isTrue);
    expect(find.text('Manual Mona'), findsOneWidget);
    expect(find.text('Captured Cara'), findsNothing);
  });
}

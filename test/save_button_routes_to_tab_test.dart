import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metadata/core/firebase/firebase_providers.dart';
import 'package:metadata/screens/saved_contacts_screen.dart';
import 'package:metadata/widgets/contact_fab_column.dart';

/// End to end: which button saved the contact decides which tab it lands in.
///   Capture Context Automatically → Captured
///   Save                          → Manual
/// Both always appear under All Contacts.
const _uid = 'test-uid';
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
              return 0; // denied — the capture step short-circuits
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

  Widget wrap(Widget home) => ProviderScope(
    overrides: [
      firebaseAuthProvider.overrideWithValue(auth),
      firebaseFirestoreProvider.overrideWithValue(firestore),
    ],
    child: MaterialApp(builder: EasyLoading.init(), home: home),
  );

  /// EasyLoading animates while shown, so pumpAndSettle would spin forever.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// Walks the real path a user takes: the "+" FAB, the form, then the button.
  Future<void> saveContactWith(WidgetTester tester, String buttonLabel) async {
    await tester.binding.setSurfaceSize(_screen);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      wrap(const Scaffold(floatingActionButton: ContactFabColumn())),
    );
    await tester.pump();

    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pumpAndSettle();

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'Ada Lovelace');
    await tester.enterText(fields.at(1), '+14155550101');
    await tester.pump();

    await tester.tap(find.text(buttonLabel));
    await settle(tester);
  }

  /// Re-pumps Your Contacts against the same Firestore and opens [tab].
  Future<void> openContactsTab(WidgetTester tester, String tab) async {
    // Tear the old tree down first: swapping MaterialApp.home leaves the
    // previous Navigator's pushed routes (the form, the contact details)
    // sitting on top, and the contacts screen would never be visible.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(wrap(const SavedContactsScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.text(tab));
    await tester.pumpAndSettle();
  }

  testWidgets('Capture Context Automatically puts the contact in Captured', (
    tester,
  ) async {
    await saveContactWith(tester, 'Capture Context Automatically');

    await openContactsTab(tester, 'Captured');
    expect(find.text('Ada Lovelace'), findsOneWidget);

    await openContactsTab(tester, 'Manual');
    expect(find.text('Ada Lovelace'), findsNothing);

    await openContactsTab(tester, 'All Contacts');
    expect(find.text('Ada Lovelace'), findsOneWidget);
  });

  testWidgets('Save puts the contact in Manual', (tester) async {
    await saveContactWith(tester, 'Save');

    await openContactsTab(tester, 'Manual');
    expect(find.text('Ada Lovelace'), findsOneWidget);

    await openContactsTab(tester, 'Captured');
    expect(find.text('Ada Lovelace'), findsNothing);

    await openContactsTab(tester, 'All Contacts');
    expect(find.text('Ada Lovelace'), findsOneWidget);
  });
}

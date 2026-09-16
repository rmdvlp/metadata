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
import 'package:metadata/widgets/button.dart';
import 'package:metadata/widgets/contact_fab_column.dart';

const _uid = 'test-uid';
const _screen = Size(1080, 2200);

/// Stands in for Home: a route under the form, so a pop after saving is
/// observable.
class _Launcher extends StatelessWidget {
  const _Launcher();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: ElevatedButton(
            onPressed: () => openNewContactScreen(context),
            child: const Text('LAUNCHER'),
          ),
        ),
      ),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const locationChannel = MethodChannel('lyokone/location');

  setUpAll(() {
    // The capture step asks for location on init; report it denied so it
    // short-circuits without geocoding or a real device.
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
    auth = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: _uid, phoneNumber: '+15551234567'),
    );
  });

  Future<void> pumpApp(WidgetTester tester, Widget home) async {
    await tester.binding.setSurfaceSize(_screen);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          firebaseAuthProvider.overrideWithValue(auth),
          firebaseFirestoreProvider.overrideWithValue(firestore),
        ],
        // The save path shows the global blocking loader, which needs its
        // overlay installed.
        child: MaterialApp(builder: EasyLoading.init(), home: home),
      ),
    );
    await tester.pump();
  }

  /// EasyLoading animates continuously while shown, so pumpAndSettle would
  /// spin forever. Pump a bounded stretch of frames instead.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> fillForm(WidgetTester tester) async {
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'Ada Lovelace');
    await tester.enterText(fields.at(1), '+14155550101');
    await tester.enterText(fields.at(2), 'Met at the museum');
    await tester.pump();
  }

  Future<List<Map<String, dynamic>>> savedContacts() async {
    final snap = await firestore
        .collection('users')
        .doc(_uid)
        .collection('contacts')
        .get();
    return snap.docs.map((d) => d.data()).toList();
  }

  group('the + entry points', () {
    testWidgets('open the New Contact form directly, with no chooser popup', (
      tester,
    ) async {
      await pumpApp(
        tester,
        const Scaffold(floatingActionButton: ContactFabColumn()),
      );

      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pumpAndSettle();

      expect(find.text('New Contact'), findsOneWidget);
      // The popup this replaced is gone for good.
      expect(find.text('Add New Contact'), findsNothing);
      expect(find.text('Save Manually'), findsNothing);
      expect(find.text('Auto Capture'), findsNothing);
    });

    testWidgets('the form offers both ways to finish', (tester) async {
      await pumpApp(
        tester,
        const Scaffold(floatingActionButton: ContactFabColumn()),
      );

      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pumpAndSettle();

      expect(find.text('Capture Context Automatically'), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);
    });

    testWidgets('both buttons stay disabled until name and phone are filled', (
      tester,
    ) async {
      await pumpApp(tester, const _Launcher());
      await tester.tap(find.text('LAUNCHER'));
      await tester.pumpAndSettle();

      for (final label in ['Capture Context Automatically', 'Save']) {
        final button = tester.widget<CustomButton>(
          find.widgetWithText(CustomButton, label),
        );
        expect(button.onPressed, isNull, reason: '$label before filling');
      }

      await fillForm(tester);

      for (final label in ['Capture Context Automatically', 'Save']) {
        final button = tester.widget<CustomButton>(
          find.widgetWithText(CustomButton, label),
        );
        expect(button.onPressed, isNotNull, reason: '$label after filling');
      }
    });
  });

  group('Save', () {
    testWidgets('saves name, phone and notes then shows the contact details', (
      tester,
    ) async {
      await pumpApp(tester, const _Launcher());
      await tester.tap(find.text('LAUNCHER'));
      await tester.pumpAndSettle();

      await fillForm(tester);
      await tester.tap(find.text('Save'));
      await settle(tester);

      final contacts = await savedContacts();
      expect(contacts, hasLength(1));
      expect(contacts.single['fullName'], 'Ada Lovelace');
      expect(contacts.single['phoneNumber'], '+14155550101');
      expect(contacts.single['notes'], 'Met at the museum');

      // Lands on the saved contact, with no context-capture step in between.
      expect(find.byType(SavedContactDetailsScreen), findsOneWidget);
      expect(find.text('Saved Contact Details'), findsOneWidget);
      expect(find.text('Ada Lovelace'), findsOneWidget);
      expect(find.byType(CaptureContextScreen), findsNothing);
      expect(find.text('New Contact'), findsNothing);

      // The flag records which button saved it — that is what sorts it into
      // the Manual tab — but it no longer strips the contact of its
      // contextual-memory sections, which stay available to fill in later.
      expect(contacts.single['capturesContext'], isFalse);
      expect(find.text('Encounter Details'), findsOneWidget);
      expect(find.text('Timeline'), findsOneWidget);
    });

    testWidgets('back from the details screen skips the form it replaced', (
      tester,
    ) async {
      await pumpApp(tester, const _Launcher());
      await tester.tap(find.text('LAUNCHER'));
      await tester.pumpAndSettle();

      await fillForm(tester);
      await tester.tap(find.text('Save'));
      await settle(tester);

      await tester.tap(find.byIcon(Icons.arrow_back_rounded));
      await tester.pumpAndSettle();

      // Straight back to where the user started — never to a filled-in form
      // for a contact that already exists.
      expect(find.text('LAUNCHER'), findsOneWidget);
      expect(find.text('New Contact'), findsNothing);
    });
  });

  group('Capture Context Automatically', () {
    testWidgets('saves the same fields then continues into the capture step', (
      tester,
    ) async {
      await pumpApp(tester, const _Launcher());
      await tester.tap(find.text('LAUNCHER'));
      await tester.pumpAndSettle();

      await fillForm(tester);
      await tester.tap(find.text('Capture Context Automatically'));
      await settle(tester);

      final contacts = await savedContacts();
      expect(contacts, hasLength(1));
      expect(contacts.single['fullName'], 'Ada Lovelace');
      // Keeps contextual memory, so its details screen keeps all its sections.
      expect(contacts.single['capturesContext'], isTrue);

      expect(find.byType(CaptureContextScreen), findsOneWidget);
    });
  });
}

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metadata/core/firebase/firebase_providers.dart';
import 'package:metadata/screens/saved_contact_details_screen.dart';

/// Notes carry the same ⋮ Edit/Delete menu the timeline rows use, for both
/// the contact's own note and each note in the list.
const _uid = 'test-uid';
const _contactId = 'c1';
const _screen = Size(1080, 2200);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const locationChannel = MethodChannel('lyokone/location');

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(locationChannel, (MethodCall call) async => 0);
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(locationChannel, null);
  });

  late FakeFirebaseFirestore firestore;
  late MockFirebaseAuth auth;

  DocumentReference<Map<String, dynamic>> contactDoc() => firestore
      .collection('users')
      .doc(_uid)
      .collection('contacts')
      .doc(_contactId);

  setUp(() {
    firestore = FakeFirebaseFirestore();
    auth = MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: _uid));
  });

  Future<void> seed({String? contactNote, List<String> notes = const []}) async {
    await contactDoc().set({
      'fullName': 'Ada Lovelace',
      'phoneNumber': '+14155550101',
      'notes': contactNote,
      'source': 'manual',
      'capturesContext': true,
      'createdAt': Timestamp.now(),
      'updatedAt': Timestamp.now(),
    });
    for (var i = 0; i < notes.length; i++) {
      await contactDoc().collection('notes').doc('n$i').set({
        'text': notes[i],
        'createdAt': Timestamp.fromDate(DateTime(2026, 5, 10 + i)),
      });
    }
  }

  Future<void> pumpDetails(WidgetTester tester) async {
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
          home: const SavedContactDetailsScreen(contactId: _contactId),
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

  /// The screen has its own "Edit" button and a contact ⋮ menu, so menu items
  /// have to be matched as menu items rather than by bare text.
  Finder menuItem(String label) =>
      find.widgetWithText(PopupMenuItem<String>, label);

  /// Opens the ⋮ belonging to the row that shows [text].
  Future<void> openMenuFor(WidgetTester tester, String text) async {
    final menu = find
        .descendant(
          of: find.ancestor(
            of: find.text(text),
            matching: find.byType(Row),
          ).last,
          matching: find.byIcon(Icons.more_vert_rounded),
        )
        .first;
    await tester.tap(menu);
    await tester.pumpAndSettle();
  }

  testWidgets('a note row offers Edit and Delete behind the ⋮', (tester) async {
    await seed(notes: ['Met at the museum']);
    await pumpDetails(tester);

    await openMenuFor(tester, 'Met at the museum');

    expect(menuItem('Edit'), findsOneWidget);
    expect(menuItem('Delete'), findsOneWidget);
  });

  testWidgets('Delete removes that note', (tester) async {
    await seed(notes: ['Met at the museum', 'Keep me']);
    await pumpDetails(tester);

    await openMenuFor(tester, 'Met at the museum');
    await tester.tap(menuItem('Delete'));
    await settle(tester);

    final remaining = (await contactDoc().collection('notes').get()).docs
        .map((d) => d.data()['text'] as String)
        .toList();
    expect(remaining, ['Keep me']);
  });

  testWidgets('Edit opens the dialog pre-filled and saves the change', (
    tester,
  ) async {
    await seed(notes: ['Met at the museum']);
    await pumpDetails(tester);

    await openMenuFor(tester, 'Met at the museum');
    await tester.tap(menuItem('Edit'));
    await tester.pumpAndSettle();

    expect(find.text('Edit Note'), findsOneWidget);
    // Pre-filled with the current text, so an edit is a tweak not a retype.
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Met at the museum',
    );

    await tester.enterText(find.byType(TextField), 'Met at the gallery');
    await tester.tap(find.text('Save'));
    await settle(tester);

    final texts = (await contactDoc().collection('notes').get()).docs
        .map((d) => d.data()['text'] as String)
        .toList();
    expect(texts, ['Met at the gallery']);
  });

  testWidgets("the contact's own note has the same menu", (tester) async {
    await seed(contactNote: 'Typed on the form');
    await pumpDetails(tester);

    await openMenuFor(tester, 'Typed on the form');

    expect(menuItem('Edit'), findsOneWidget);
    expect(menuItem('Delete'), findsOneWidget);

    await tester.tap(menuItem('Delete'));
    await settle(tester);

    expect((await contactDoc().get()).data()!['notes'], isNull);
  });

  testWidgets('the loose edit and ✕ icons are gone from note rows', (
    tester,
  ) async {
    await seed(contactNote: 'Typed on the form', notes: ['Met at the museum']);
    await pumpDetails(tester);

    // Both actions now live behind the ⋮, so neither loose icon should sit on
    // a note row. (Scoped to the rows: the screen's own Edit button and the
    // Encounter Details pencil legitimately use the same icons elsewhere.)
    for (final text in ['Typed on the form', 'Met at the museum']) {
      final row = find.ancestor(of: find.text(text), matching: find.byType(Row)).last;

      expect(
        find.descendant(of: row, matching: find.byIcon(Icons.close_rounded)),
        findsNothing,
        reason: text,
      );
      expect(
        find.descendant(of: row, matching: find.byIcon(Icons.edit_outlined)),
        findsNothing,
        reason: text,
      );
      expect(
        find.descendant(of: row, matching: find.byIcon(Icons.more_vert_rounded)),
        findsOneWidget,
        reason: text,
      );
    }
  });
}

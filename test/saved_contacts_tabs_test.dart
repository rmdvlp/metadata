import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metadata/core/firebase/firebase_providers.dart';
import 'package:metadata/models/contact_model.dart';
import 'package:metadata/screens/saved_contacts_screen.dart';

const _uid = 'test-uid';
const _screen = Size(1080, 2200);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeFirebaseFirestore firestore;
  late MockFirebaseAuth auth;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    auth = MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: _uid));
  });

  CollectionReference<Map<String, dynamic>> contacts() =>
      firestore.collection('users').doc(_uid).collection('contacts');

  Future<void> seed(
    String id,
    String name, {
    required ContactSource source,
    required bool capturesContext,
  }) {
    return contacts().doc(id).set({
      'fullName': name,
      'phoneNumber': '+1415555${id.padLeft(4, '0')}',
      'source': source.name,
      'capturesContext': capturesContext,
      'createdAt': Timestamp.now(),
      'updatedAt': Timestamp.now(),
    });
  }

  /// One of each provenance, so every tab has something to include and
  /// something it must leave out.
  Future<void> seedAll() async {
    await seed('1', 'Captured Cara',
        source: ContactSource.manual, capturesContext: true);
    await seed('2', 'Manual Mona',
        source: ContactSource.manual, capturesContext: false);
    await seed('3', 'Synced Sam',
        source: ContactSource.device, capturesContext: true);
  }

  Future<void> pumpScreen(WidgetTester tester) async {
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
          home: const SavedContactsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openTab(WidgetTester tester, String label) async {
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  group('tabs sort contacts by how they were saved', () {
    testWidgets('All Contacts shows every contact', (tester) async {
      await seedAll();
      await pumpScreen(tester);

      expect(find.text('Captured Cara'), findsOneWidget);
      expect(find.text('Manual Mona'), findsOneWidget);
      expect(find.text('Synced Sam'), findsOneWidget);
    });

    testWidgets('Captured shows only Capture-Context-Automatically saves', (
      tester,
    ) async {
      await seedAll();
      await pumpScreen(tester);
      await openTab(tester, 'Captured');

      expect(find.text('Captured Cara'), findsOneWidget);
      expect(find.text('Manual Mona'), findsNothing);
      // Phone-book contacts were never saved through either button, so they
      // belong under All Contacts only.
      expect(find.text('Synced Sam'), findsNothing);
    });

    testWidgets('Manual shows only plain saves', (tester) async {
      await seedAll();
      await pumpScreen(tester);
      await openTab(tester, 'Manual');

      expect(find.text('Manual Mona'), findsOneWidget);
      expect(find.text('Captured Cara'), findsNothing);
      expect(find.text('Synced Sam'), findsNothing);
    });
  });

  group('select and delete', () {
    testWidgets('no delete icon until something is selected', (tester) async {
      await seedAll();
      await pumpScreen(tester);

      expect(find.byIcon(Icons.delete_outline_rounded), findsNothing);
      expect(find.text('Your Contacts'), findsOneWidget);
    });

    testWidgets('long-press selects and reveals the delete icon', (
      tester,
    ) async {
      await seedAll();
      await pumpScreen(tester);

      await tester.longPress(find.text('Captured Cara'));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.delete_outline_rounded), findsOneWidget);
      expect(find.text('1 selected'), findsOneWidget);
    });

    testWidgets('tapping adds more once selection has started', (tester) async {
      await seedAll();
      await pumpScreen(tester);

      await tester.longPress(find.text('Captured Cara'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Manual Mona'));
      await tester.pumpAndSettle();

      expect(find.text('2 selected'), findsOneWidget);
    });

    testWidgets('tapping a selected row deselects it', (tester) async {
      await seedAll();
      await pumpScreen(tester);

      await tester.longPress(find.text('Captured Cara'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Captured Cara'));
      await tester.pumpAndSettle();

      // Back to the ordinary app bar, with no selection left.
      expect(find.text('Your Contacts'), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline_rounded), findsNothing);
    });

    testWidgets('cancel drops the selection without deleting', (tester) async {
      await seedAll();
      await pumpScreen(tester);

      await tester.longPress(find.text('Captured Cara'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();

      expect(find.text('Your Contacts'), findsOneWidget);
      expect((await contacts().get()).docs, hasLength(3));
    });

    testWidgets('deleting removes exactly the selected contacts', (
      tester,
    ) async {
      await seedAll();
      await pumpScreen(tester);

      await tester.longPress(find.text('Captured Cara'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Manual Mona'));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.delete_outline_rounded));
      await tester.pumpAndSettle();
      expect(find.text('Delete 2 Contacts'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      // EasyLoading animates while shown, so pump a bounded stretch rather
      // than settling.
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      final remaining = (await contacts().get()).docs
          .map((d) => d.data()['fullName'] as String)
          .toList();
      expect(remaining, ['Synced Sam']);
    });

    testWidgets('cancelling the confirm dialog deletes nothing', (
      tester,
    ) async {
      await seedAll();
      await pumpScreen(tester);

      await tester.longPress(find.text('Captured Cara'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.delete_outline_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect((await contacts().get()).docs, hasLength(3));
      // The selection survives, so the user can adjust it and try again.
      expect(find.text('1 selected'), findsOneWidget);
    });

    testWidgets('a selection made in one tab still deletes from another', (
      tester,
    ) async {
      await seedAll();
      await pumpScreen(tester);

      await openTab(tester, 'Captured');
      await tester.longPress(find.text('Captured Cara'));
      await tester.pumpAndSettle();

      await openTab(tester, 'Manual');
      await tester.tap(find.text('Manual Mona'));
      await tester.pumpAndSettle();

      expect(find.text('2 selected'), findsOneWidget);
    });
  });
}

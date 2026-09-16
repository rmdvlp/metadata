import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metadata/core/firebase/firebase_providers.dart';
import 'package:metadata/screens/saved_contact_details_screen.dart';

const _uid = 'test-uid';
const _contactId = 'contact-1';
const _screen = Size(1080, 2200);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeFirebaseFirestore firestore;
  late MockFirebaseAuth auth;

  Future<void> seedContact({
    bool isBlocked = false,
    bool? capturesContext = true,
  }) async {
    await firestore
        .collection('users')
        .doc(_uid)
        .collection('contacts')
        .doc(_contactId)
        .set({
          'fullName': 'Ada Lovelace',
          'phoneNumber': '+14155550101',
          'notes': null,
          'photoUrl': null,
          'source': 'manual',
          'isFavorite': false,
          'isBlocked': isBlocked,
          // null omits the field entirely, standing in for a doc written
          // before the flag existed.
          'capturesContext': ?capturesContext,
          'createdAt': Timestamp.now(),
          'updatedAt': Timestamp.now(),
        });
  }

  setUp(() {
    firestore = FakeFirebaseFirestore();
    auth = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: _uid, phoneNumber: '+15551234567'),
    );
  });

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

  /// EasyLoading animates while shown, so pumpAndSettle would spin forever.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// `ElevatedButton.icon` returns a private subclass, which `find.byType`
  /// will not match — it compares runtime types exactly.
  Finder elevatedButtonLabelled(String label) => find.ancestor(
    of: find.text(label),
    matching: find.byWidgetPredicate((w) => w is ElevatedButton),
  );

  Future<bool> isBlockedInFirestore() async {
    final doc = await firestore
        .collection('users')
        .doc(_uid)
        .collection('contacts')
        .doc(_contactId)
        .get();
    return doc.data()?['isBlocked'] as bool? ?? false;
  }

  group('header actions', () {
    testWidgets('shows a three-dot menu instead of a bare delete button', (
      tester,
    ) async {
      await seedContact();
      await pumpDetails(tester);

      expect(find.byIcon(Icons.more_vert_rounded), findsOneWidget);
      // The old one-tap delete is gone from the header.
      expect(find.byIcon(Icons.delete_outline_rounded), findsNothing);
    });

    testWidgets('the menu offers block and delete', (tester) async {
      await seedContact();
      await pumpDetails(tester);

      await tester.tap(find.byIcon(Icons.more_vert_rounded));
      await tester.pumpAndSettle();

      expect(find.text('Block Contact'), findsOneWidget);
      expect(find.text('Delete Contact'), findsOneWidget);
      expect(find.byIcon(Icons.block_rounded), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline_rounded), findsOneWidget);
    });

    testWidgets('an already-blocked contact offers unblock instead', (
      tester,
    ) async {
      await seedContact(isBlocked: true);
      await pumpDetails(tester);

      await tester.tap(find.byIcon(Icons.more_vert_rounded));
      await tester.pumpAndSettle();

      expect(find.text('Unblock Contact'), findsOneWidget);
      expect(find.text('Block Contact'), findsNothing);
    });
  });

  group('call buttons', () {
    testWidgets('keeps Edit and Call, drops the extra phone button', (
      tester,
    ) async {
      await seedContact();
      await pumpDetails(tester);

      expect(find.text('Edit'), findsOneWidget);
      expect(find.text('Call'), findsOneWidget);
      expect(find.byIcon(Icons.wifi_calling_3_outlined), findsNothing);
    });
  });

  group('blocking', () {
    testWidgets('block asks first, then persists', (tester) async {
      await seedContact();
      await pumpDetails(tester);

      await tester.tap(find.byIcon(Icons.more_vert_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Block Contact'));
      await tester.pumpAndSettle();

      // Confirmation, not an immediate write.
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(await isBlockedInFirestore(), isFalse);

      await tester.tap(find.text('Block'));
      await settle(tester);

      expect(await isBlockedInFirestore(), isTrue);
    });

    testWidgets('cancelling the confirmation leaves the contact unblocked', (
      tester,
    ) async {
      await seedContact();
      await pumpDetails(tester);

      await tester.tap(find.byIcon(Icons.more_vert_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Block Contact'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await settle(tester);

      expect(await isBlockedInFirestore(), isFalse);
    });

    testWidgets('unblock takes effect without a confirmation', (tester) async {
      await seedContact(isBlocked: true);
      await pumpDetails(tester);

      await tester.tap(find.byIcon(Icons.more_vert_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Unblock Contact'));
      await settle(tester);

      expect(find.byType(AlertDialog), findsNothing);
      expect(await isBlockedInFirestore(), isFalse);
    });

    testWidgets('a blocked contact explains itself and cannot be called', (
      tester,
    ) async {
      await seedContact(isBlocked: true);
      await pumpDetails(tester);

      expect(find.textContaining('You blocked this contact'), findsOneWidget);
      expect(find.text('Unblock'), findsOneWidget);

      // The call action is disabled, not merely relabelled.
      final callButton = tester.widget<ElevatedButton>(
        elevatedButtonLabelled('Blocked').first,
      );
      expect(callButton.onPressed, isNull);
    });

    testWidgets('an unblocked contact keeps a working Call button', (
      tester,
    ) async {
      await seedContact();
      await pumpDetails(tester);

      expect(find.textContaining('You blocked this contact'), findsNothing);

      final callButton = tester.widget<ElevatedButton>(
        elevatedButtonLabelled('Call').first,
      );
      expect(callButton.onPressed, isNotNull);
    });
  });

  group('contextual memory sections', () {
    // Every contact gets them now, whichever button saved it: a manually
    // saved contact can be given a location, notes and timeline entries
    // later, and hiding the sections would put that out of reach.
    testWidgets('a manually saved contact shows all of them', (tester) async {
      await seedContact(capturesContext: false);
      await pumpDetails(tester);

      expect(find.text('Encounter Details'), findsOneWidget);
      expect(find.text('Notes'), findsOneWidget);
      expect(find.text('Timeline'), findsOneWidget);
      // ...including the affordances that fill them in.
      expect(find.text('Add Note'), findsOneWidget);
      expect(find.text('Add New'), findsOneWidget);

      // The contact itself is still fully usable.
      expect(find.text('Ada Lovelace'), findsOneWidget);
      expect(find.text('Edit'), findsOneWidget);
      expect(find.text('Call'), findsOneWidget);
      expect(find.byIcon(Icons.more_vert_rounded), findsOneWidget);
    });

    testWidgets('a captured contact shows all of them', (tester) async {
      await seedContact(capturesContext: true);
      await pumpDetails(tester);

      expect(find.text('Encounter Details'), findsOneWidget);
      expect(find.text('Notes'), findsOneWidget);
      expect(find.text('Timeline'), findsOneWidget);
    });

    testWidgets('a contact saved before the flag existed keeps its sections', (
      tester,
    ) async {
      await seedContact(capturesContext: null);
      await pumpDetails(tester);

      expect(find.text('Encounter Details'), findsOneWidget);
      expect(find.text('Notes'), findsOneWidget);
      expect(find.text('Timeline'), findsOneWidget);
    });
  });

  group('missing contact', () {
    testWidgets('offers a way back instead of a bare dead-end message', (
      tester,
    ) async {
      // Nothing seeded: the contact this route points at does not exist.
      await pumpDetails(tester);

      expect(find.text('Contact no longer available'), findsOneWidget);
      // The normal header lives in the body, so without these the screen is a
      // trap with no way off it.
      expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);
      expect(find.text('Go Back'), findsOneWidget);
    });

    testWidgets('the way back actually pops the route', (tester) async {
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
            home: Scaffold(
              body: Builder(
                builder: (context) => Center(
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            const SavedContactDetailsScreen(contactId: 'gone'),
                      ),
                    ),
                    child: const Text('LAUNCHER'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('LAUNCHER'));
      await tester.pumpAndSettle();
      expect(find.text('Contact no longer available'), findsOneWidget);

      await tester.tap(find.text('Go Back'));
      await tester.pumpAndSettle();

      expect(find.text('LAUNCHER'), findsOneWidget);
    });
  });

  group('deleting', () {
    testWidgets('returns to the previous screen rather than stranding', (
      tester,
    ) async {
      await seedContact();
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
            home: Scaffold(
              body: Builder(
                builder: (context) => Center(
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const SavedContactDetailsScreen(
                          contactId: _contactId,
                        ),
                      ),
                    ),
                    child: const Text('LAUNCHER'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('LAUNCHER'));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.more_vert_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete Contact'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await settle(tester);

      // Back where the user started — never left on the "no longer available"
      // placeholder that the deletion itself produces.
      expect(find.text('LAUNCHER'), findsOneWidget);
      expect(find.text('Contact no longer available'), findsNothing);

      final remaining = await firestore
          .collection('users')
          .doc(_uid)
          .collection('contacts')
          .get();
      expect(remaining.docs, isEmpty);
    });
  });
}

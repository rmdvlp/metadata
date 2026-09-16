import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metadata/core/firebase/firebase_providers.dart';
import 'package:metadata/models/contact_model.dart';
import 'package:metadata/screens/saved_contact_details_screen.dart';
import 'package:metadata/utils/contact_quarantine.dart';
import 'package:metadata/widgets/contact_avatar.dart';
import 'package:metadata/widgets/contact_tile.dart';
import 'package:metadata/widgets/quarantine_badge.dart';

const _uid = 'test-uid';
const _contactId = 'contact-1';
const _screen = Size(1080, 2200);

final DateTime _now = DateTime(2026, 9, 3);

ContactModel _contact({
  String id = _contactId,
  DateTime? lastContactedAt,
  DateTime? updatedAt,
  DateTime? createdAt,
}) {
  return ContactModel(
    id: id,
    fullName: 'Alfredo Dorwart',
    phoneNumber: '+27821234567',
    lastContactedAt: lastContactedAt,
    updatedAt: updatedAt,
    createdAt: createdAt,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('isQuarantined', () {
    test('a contact called recently is not quarantined', () {
      final contact = _contact(
        lastContactedAt: _now.subtract(const Duration(days: 30)),
      );
      expect(isQuarantined(contact, now: _now), isFalse);
    });

    test('two years of silence quarantines the contact', () {
      final contact = _contact(
        lastContactedAt: _now.subtract(const Duration(days: 800)),
      );
      expect(isQuarantined(contact, now: _now), isTrue);
    });

    test('the boundary is two years to the day, not a day sooner', () {
      // One day short: still a normal contact.
      expect(
        isQuarantined(
          _contact(
            lastContactedAt: _now.subtract(
              kQuarantineAfter - const Duration(days: 1),
            ),
          ),
          now: _now,
        ),
        isFalse,
      );
      // Exactly two years: quarantined.
      expect(
        isQuarantined(
          _contact(lastContactedAt: _now.subtract(kQuarantineAfter)),
          now: _now,
        ),
        isTrue,
      );
    });

    test('an edit does not count as having spoken to someone', () {
      // Notes tidied yesterday, but nobody has called in three years. The
      // whole reason lastContactedAt exists rather than reusing updatedAt.
      final contact = _contact(
        lastContactedAt: _now.subtract(const Duration(days: 1100)),
        updatedAt: _now.subtract(const Duration(days: 1)),
      );
      expect(isQuarantined(contact, now: _now), isTrue);
    });

    test('falls back to updatedAt, then createdAt, on older contacts', () {
      // Saved before lastContactedAt existed.
      expect(
        isQuarantined(
          _contact(updatedAt: _now.subtract(const Duration(days: 900))),
          now: _now,
        ),
        isTrue,
      );
      expect(
        isQuarantined(
          _contact(updatedAt: _now.subtract(const Duration(days: 10))),
          now: _now,
        ),
        isFalse,
      );
      // Saved once and never touched again.
      expect(
        isQuarantined(
          _contact(createdAt: _now.subtract(const Duration(days: 900))),
          now: _now,
        ),
        isTrue,
      );
    });

    test('a contact with no timestamps at all is never accused', () {
      // What a just-written doc looks like locally, before the server
      // resolves its timestamps — it must not flash "Quarantine".
      expect(isQuarantined(_contact(), now: _now), isFalse);
      expect(lastInteractionAt(_contact()), isNull);
    });

    test('the stand-in contact for an unsaved number is skipped', () {
      // Synthesized from a call-log row: there is no document to delete.
      final contact = _contact(
        id: '',
        updatedAt: _now.subtract(const Duration(days: 3000)),
      );
      expect(isQuarantined(contact, now: _now), isFalse);
    });
  });

  group('quarantineSilenceLabel', () {
    test('spells out whole years', () {
      expect(
        quarantineSilenceLabel(
          _contact(lastContactedAt: _now.subtract(const Duration(days: 740))),
          now: _now,
        ),
        'approximately two years ago',
      );
      expect(
        quarantineSilenceLabel(
          _contact(lastContactedAt: _now.subtract(const Duration(days: 1200))),
          now: _now,
        ),
        'approximately three years ago',
      );
    });

    test('switches to digits once spelling stops helping', () {
      expect(
        quarantineSilenceLabel(
          _contact(lastContactedAt: _now.subtract(const Duration(days: 4400))),
          now: _now,
        ),
        'more than 12 years ago',
      );
    });

    test('says nothing precise when the date is unknown', () {
      expect(quarantineSilenceLabel(_contact(), now: _now), 'a long time ago');
    });
  });

  group('the pill on a contact row', () {
    Future<void> pumpTile(
      WidgetTester tester,
      ContactModel contact, {
      VoidCallback? onTap,
      VoidCallback? onQuarantineTap,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ContactTile(
              contact: contact,
              subtitle: Text(contact.phoneNumber),
              onTap: onTap,
              onCallTap: () {},
              onFavoriteTap: () {},
              onQuarantineTap: onQuarantineTap,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('shows for a silent contact and not for an active one', (
      tester,
    ) async {
      await pumpTile(
        tester,
        _contact(
          lastContactedAt: DateTime.now().subtract(const Duration(days: 900)),
        ),
      );
      expect(find.text('Quarantine'), findsOneWidget);

      await pumpTile(
        tester,
        _contact(
          lastContactedAt: DateTime.now().subtract(const Duration(days: 9)),
        ),
      );
      expect(find.text('Quarantine'), findsNothing);
    });

    testWidgets('tapping it reviews the contact instead of opening the row', (
      tester,
    ) async {
      var rowOpened = 0;
      var reviewed = 0;
      await pumpTile(
        tester,
        _contact(
          lastContactedAt: DateTime.now().subtract(const Duration(days: 900)),
        ),
        onTap: () => rowOpened++,
        onQuarantineTap: () => reviewed++,
      );

      await tester.tap(find.text('Quarantine'));
      await tester.pumpAndSettle();

      expect(reviewed, 1);
      // Opening the contact *and* the prompt at once would leave the dialog
      // sitting over the wrong screen.
      expect(rowOpened, 0);
    });

    testWidgets('the tap target is comfortably larger than the label', (
      tester,
    ) async {
      await pumpTile(
        tester,
        _contact(
          lastContactedAt: DateTime.now().subtract(const Duration(days: 900)),
        ),
        onQuarantineTap: () {},
      );

      final target = tester.getRect(
        find
            .ancestor(
              of: find.text('Quarantine'),
              matching: find.byType(GestureDetector),
            )
            .first,
      );
      expect(target.height, greaterThan(28));
    });
  });

  group('the Keep or Remove Contact prompt', () {
    testWidgets('names the contact and how long the silence has been', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showKeepOrRemoveContactDialog(
                  context: context,
                  contactName: 'Alfredo Dorwart',
                  silenceLabel: 'approximately two years ago',
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Keep or Remove Contact?'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
      expect(find.text('Skip'), findsOneWidget);
      expect(
        find.textContaining(
          'You last communicated with Alfredo Dorwart approximately two '
          'years ago',
        ),
        findsOneWidget,
      );
    });

    testWidgets('each button reports its own decision', (tester) async {
      final decisions = <QuarantineDecision?>[];

      Future<void> open(WidgetTester tester) async {
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
      }

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  decisions.add(
                    await showKeepOrRemoveContactDialog(
                      context: context,
                      contactName: 'Alfredo',
                      silenceLabel: 'approximately two years ago',
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

      await open(tester);
      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();

      await open(tester);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(decisions, [QuarantineDecision.skip, QuarantineDecision.delete]);
    });
  });

  group('on Saved Contact Details', () {
    late FakeFirebaseFirestore firestore;
    late MockFirebaseAuth auth;

    DocumentReference<Map<String, dynamic>> contactDoc() => firestore
        .collection('users')
        .doc(_uid)
        .collection('contacts')
        .doc(_contactId);

    Future<void> seedContact({required Duration silentFor}) async {
      final last = DateTime.now().subtract(silentFor);
      await contactDoc().set({
        'fullName': 'Alfredo Dorwart',
        'phoneNumber': '+27821234567',
        'source': 'manual',
        'isFavorite': false,
        'isBlocked': false,
        'capturesContext': true,
        'lastContactedAt': Timestamp.fromDate(last),
        'createdAt': Timestamp.fromDate(last),
        'updatedAt': Timestamp.fromDate(last),
      });
    }

    setUp(() {
      firestore = FakeFirebaseFirestore();
      auth = MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: _uid));
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

    testWidgets('the pill sits between the photo and the name', (tester) async {
      await seedContact(silentFor: const Duration(days: 900));
      await pumpDetails(tester);

      expect(find.text('Quarantine'), findsOneWidget);

      final pill = tester.getRect(find.text('Quarantine'));
      final photo = tester.getRect(find.byType(ContactAvatar).first);
      final name = tester.getRect(find.text('Alfredo Dorwart'));

      expect(pill.top, greaterThan(photo.bottom - 1));
      expect(pill.bottom, lessThan(name.top));
    });

    testWidgets('an active contact gets no pill', (tester) async {
      await seedContact(silentFor: const Duration(days: 20));
      await pumpDetails(tester);

      expect(find.text('Quarantine'), findsNothing);
    });

    testWidgets('Skip keeps the contact and writes nothing', (tester) async {
      await seedContact(silentFor: const Duration(days: 900));
      await pumpDetails(tester);
      final before = (await contactDoc().get()).data();

      await tester.tap(find.text('Quarantine'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Skip'));
      await settle(tester);

      final after = (await contactDoc().get()).data();
      expect(after, isNotNull);
      // A "reviewed" flag would bump updatedAt — which for older contacts is
      // the quarantine clock itself, so Skip would reset what it reviewed.
      expect(after!['updatedAt'], before!['updatedAt']);
      // The pill reports a fact that Skip does not change.
      expect(find.text('Quarantine'), findsOneWidget);
    });

    testWidgets('Delete removes the contact', (tester) async {
      await seedContact(silentFor: const Duration(days: 900));
      await pumpDetails(tester);

      await tester.tap(find.text('Quarantine'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await settle(tester);

      expect((await contactDoc().get()).exists, isFalse);
    });
  });
}

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

/// Timeline rows: each rail dot must sit on its label's line, and every label
/// must start at the same x. The dot used to be pinned 4pt from the top while
/// the label centred inside a row stretched to the ⋮ button's 48pt tap
/// target, leaving the two visibly out of line.
const _uid = 'test-uid';
const _contactId = 'c1';
const _screen = Size(1080, 2200);

const _entries = [
  ('t1', 'FIRST MET', 'Central Park', 5),
  ('t2', 'FOLLOW UP', 'Blue Bottle Coffee', 12),
  ('t3', 'LUNCH', 'Sample Cafe', 20),
];

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

  setUp(() async {
    firestore = FakeFirebaseFirestore();
    auth = MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: _uid));

    final contact = firestore
        .collection('users')
        .doc(_uid)
        .collection('contacts')
        .doc(_contactId);
    await contact.set({
      'fullName': 'Ada Lovelace',
      'phoneNumber': '+14155550101',
      'capturesContext': true,
      'createdAt': Timestamp.now(),
      'updatedAt': Timestamp.now(),
    });
    for (final (id, label, title, day) in _entries) {
      await contact.collection('timeline').doc(id).set({
        'label': label,
        'title': title,
        'subtitle': 'Somewhere in town',
        'date': Timestamp.fromDate(DateTime(2026, 5, day)),
      });
    }
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

  testWidgets('every dot is centred on its own label', (tester) async {
    await pumpDetails(tester);

    for (final (id, label, _, _) in _entries) {
      final dot = tester.getCenter(find.byKey(ValueKey('timeline-dot-$id')));
      final text = tester.getCenter(find.text(label));

      expect(
        dot.dy,
        closeTo(text.dy, 1.0),
        reason: '$label: dot at ${dot.dy}, label at ${text.dy}',
      );
    }
  });

  testWidgets('all dots share one vertical rail', (tester) async {
    await pumpDetails(tester);

    final xs = _entries
        .map((e) => tester.getCenter(find.byKey(ValueKey('timeline-dot-${e.$1}'))).dx)
        .toSet();

    expect(xs, hasLength(1), reason: 'dots drifted horizontally: $xs');
  });

  testWidgets('all labels start at the same x', (tester) async {
    await pumpDetails(tester);

    final lefts = _entries
        .map((e) => tester.getTopLeft(find.text(e.$2)).dx)
        .toSet();

    expect(lefts, hasLength(1), reason: 'labels are ragged: $lefts');
  });

  testWidgets('the label sits to the right of the rail, never overlapping it', (
    tester,
  ) async {
    await pumpDetails(tester);

    for (final (id, label, _, _) in _entries) {
      final dotRight = tester
          .getRect(find.byKey(ValueKey('timeline-dot-$id')))
          .right;
      final labelLeft = tester.getTopLeft(find.text(label)).dx;

      expect(labelLeft, greaterThan(dotRight), reason: label);
    }
  });

  testWidgets('the header line keeps its own height', (tester) async {
    await pumpDetails(tester);

    // The ⋮ button claims a 48pt tap target by default, which stretched this
    // row and pushed the label off the dot. Pinning the height is what keeps
    // the two in line.
    for (final (id, _, _, _) in _entries) {
      final header = tester.getSize(
        find.byKey(ValueKey('timeline-header-$id')),
      );
      expect(header.height, 24, reason: id);
    }
  });

  testWidgets('the date and ⋮ are pushed hard right, not left mid-row', (
    tester,
  ) async {
    await pumpDetails(tester);

    for (final (id, _, _, _) in _entries) {
      final header = tester.getRect(find.byKey(ValueKey('timeline-header-$id')));
      final menu = tester.getRect(
        find.descendant(
          of: find.byKey(ValueKey('timeline-header-$id')),
          matching: find.byIcon(Icons.more_vert_rounded),
        ),
      );
      final date = tester.getRect(
        find.descendant(
          of: find.byKey(ValueKey('timeline-header-$id')),
          matching: find.byType(Text),
        ).at(1),
      );

      // The menu ends at the row's right edge...
      expect(menu.right, closeTo(header.right, 4.0), reason: '$id menu');
      // ...and the date sits immediately before it, well past the midpoint.
      expect(
        date.left,
        greaterThan(header.left + header.width / 2),
        reason: '$id date',
      );
      expect(date.right, lessThanOrEqualTo(menu.left + 1));
    }
  });
}

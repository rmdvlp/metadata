import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:metadata/core/firebase/firebase_providers.dart';
import 'package:metadata/screens/event_detail.dart';

/// The Edit Details screen has to actually edit: the map pin follows taps and
/// fills in the coordinates, date and time are pickable, and a role is
/// required before saving.
const _uid = 'test-uid';
const _contactId = 'c1';
const _screen = Size(1080, 2200);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

  Future<void> seedContact() => contactDoc().set({
    'fullName': 'Ada Lovelace',
    'phoneNumber': '+14155550101',
    'capturesContext': false,
    'createdAt': Timestamp.now(),
    'updatedAt': Timestamp.now(),
  });

  Future<void> pumpScreen(
    WidgetTester tester, {
    String? role,
    DateTime? initialDateTime,
  }) async {
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
          home: EventDetailScreen(
            contactId: _contactId,
            initialLat: 28.6139,
            initialLng: 77.2090,
            initialRole: role,
            initialDateTime: initialDateTime,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// Fields in document order: place, address, latitude, longitude, role,
  /// notes.
  const latitudeField = 2;
  const longitudeField = 3;

  String fieldText(WidgetTester tester, int index) {
    return tester
        .widget<TextFormField>(find.byType(TextFormField).at(index))
        .controller!
        .text;
  }

  group('the map is interactive', () {
    testWidgets('it is wired to an onTap handler', (tester) async {
      await seedContact();
      await pumpScreen(tester);

      // The bug was a MapOptions with no onTap at all: taps did nothing, so
      // the pin never moved and no field ever updated.
      final map = tester.widget<FlutterMap>(find.byType(FlutterMap));
      expect(map.options.onTap, isNotNull);
    });

    testWidgets('it tells the user the map is tappable', (tester) async {
      await seedContact();
      await pumpScreen(tester);

      expect(find.text('Tap the map to move the pin'), findsOneWidget);
    });

    testWidgets('tapping fills in latitude and longitude', (tester) async {
      await seedContact();
      await pumpScreen(tester);

      final map = tester.widget<FlutterMap>(find.byType(FlutterMap));
      map.options.onTap!(
        TapPosition(const Offset(0, 0), const Offset(0, 0)),
        const LatLng(51.5074, -0.1278),
      );
      await tester.pump();

      expect(fieldText(tester, latitudeField), '51.5074');
      expect(fieldText(tester, longitudeField), '-0.1278');
    });

    testWidgets('the pin follows the tap', (tester) async {
      await seedContact();
      await pumpScreen(tester);

      final map = tester.widget<FlutterMap>(find.byType(FlutterMap));
      map.options.onTap!(
        TapPosition(const Offset(0, 0), const Offset(0, 0)),
        const LatLng(51.5074, -0.1278),
      );
      await tester.pump();

      final layer = tester.widget<MarkerLayer>(find.byType(MarkerLayer));
      expect(layer.markers.single.point.latitude, closeTo(51.5074, 0.0001));
      expect(layer.markers.single.point.longitude, closeTo(-0.1278, 0.0001));
    });

    testWidgets('typing coordinates moves the pin too', (tester) async {
      await seedContact();
      await pumpScreen(tester);

      await tester.enterText(find.byType(TextFormField).at(latitudeField), '40.7128');
      await tester.enterText(find.byType(TextFormField).at(longitudeField), '-74.0060');
      await tester.pump();

      final layer = tester.widget<MarkerLayer>(find.byType(MarkerLayer));
      expect(layer.markers.single.point.latitude, closeTo(40.7128, 0.0001));
      expect(layer.markers.single.point.longitude, closeTo(-74.0060, 0.0001));
    });
  });

  group('date and time are editable', () {
    testWidgets('tapping Date opens a picker and the choice sticks', (
      tester,
    ) async {
      await seedContact();
      await pumpScreen(tester, initialDateTime: DateTime(2026, 5, 14, 10, 30));

      expect(find.text('14/05/2026'), findsOneWidget);

      await tester.tap(find.text('14/05/2026'));
      await tester.pumpAndSettle();
      // The picker is open; pick the 20th of the same month.
      await tester.tap(find.text('20'));
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(find.text('20/05/2026'), findsOneWidget);
      // The time is untouched by a date change.
      expect(find.text('10:30'), findsOneWidget);
    });

    testWidgets('tapping Time opens a picker', (tester) async {
      await seedContact();
      await pumpScreen(tester, initialDateTime: DateTime(2026, 5, 14, 10, 30));

      await tester.tap(find.text('10:30'));
      await tester.pumpAndSettle();

      // A time picker is on screen — it offers Cancel/OK.
      expect(find.text('OK'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    });

    testWidgets('the chosen date and time are what get saved', (tester) async {
      await seedContact();
      await pumpScreen(
        tester,
        role: 'Mentor',
        initialDateTime: DateTime(2026, 5, 14, 10, 30),
      );

      await tester.tap(find.text('14/05/2026'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('20'));
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save'));
      await settle(tester);

      final saved = (await contactDoc().get()).data()!;
      final eventDate = (saved['eventDate'] as Timestamp).toDate();
      expect(eventDate.day, 20);
      expect(eventDate.month, 5);
      expect(eventDate.year, 2026);
      expect(eventDate.hour, 10);
      expect(eventDate.minute, 30);
    });
  });

  group('role is required', () {
    testWidgets('saving without one is refused and writes nothing', (
      tester,
    ) async {
      await seedContact();
      await pumpScreen(tester);

      await tester.tap(find.text('Save'));
      await tester.pump();

      expect(find.text('Please enter a role.'), findsOneWidget);
      expect((await contactDoc().get()).data()!.containsKey('role'), isFalse);
    });

    testWidgets('it is no longer labelled optional', (tester) async {
      await seedContact();
      await pumpScreen(tester);

      expect(find.text('Role'), findsOneWidget);
      expect(find.text('Role (Optional)'), findsNothing);
    });

    testWidgets('saving with one goes through', (tester) async {
      await seedContact();
      await pumpScreen(tester, role: 'Mentor');

      await tester.tap(find.text('Save'));
      await settle(tester);

      expect((await contactDoc().get()).data()!['role'], 'Mentor');
    });
  });
}

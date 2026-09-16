import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metadata/core/firebase/firebase_providers.dart';
import 'package:metadata/models/encounter_details.dart';
import 'package:metadata/models/timeline_entry.dart';
import 'package:metadata/screens/all_contacts_screen.dart';
import 'package:metadata/screens/calling_screen.dart';
import 'package:metadata/screens/capture_context.dart';
import 'package:metadata/screens/contact_screen.dart';
import 'package:metadata/screens/event_detail.dart';
import 'package:metadata/screens/home_screen.dart';
import 'package:metadata/screens/login_screen.dart';
import 'package:metadata/screens/name_screen.dart';
import 'package:metadata/screens/notification_screen.dart';
import 'package:metadata/screens/otp_screen.dart';
import 'package:metadata/screens/profile_screen.dart';
import 'package:metadata/screens/recent_call_logs_screen.dart';
import 'package:metadata/screens/saved_contact_details_screen.dart';
import 'package:metadata/screens/settings_screen.dart';
import 'package:metadata/screens/support_center_screen.dart';

const _testUid = 'test-uid';
const _testContactId = 'test-contact-1';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel locationChannel = MethodChannel('lyokone/location');
  const MethodChannel contactsChannel = MethodChannel('flutter_contacts');

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(locationChannel, (MethodCall call) async {
          switch (call.method) {
            case 'serviceEnabled':
              return 1;
            case 'requestService':
              return 1;
            case 'hasPermission':
              return 1;
            case 'requestPermission':
              return 1;
            case 'getLocation':
              return <String, double>{
                'latitude': 28.6139,
                'longitude': 77.2090,
              };
            default:
              return null;
          }
        });

    // Home screen fires a background contacts sync on first frame; report
    // permission as denied so it short-circuits without a real device.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(contactsChannel, (MethodCall call) async {
          switch (call.method) {
            case 'permissions.check':
            case 'permissions.request':
              return 'denied';
            default:
              return null;
          }
        });
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(locationChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(contactsChannel, null);
  });

  late FakeFirebaseFirestore fakeFirestore;
  late MockFirebaseAuth mockAuth;

  Future<void> pumpScreen(WidgetTester tester, Widget screen) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          firebaseAuthProvider.overrideWithValue(mockAuth),
          firebaseFirestoreProvider.overrideWithValue(fakeFirestore),
        ],
        child: MaterialApp(home: screen),
      ),
    );
    await tester.pump();
  }

  testWidgets('all major screens render without crashing', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1080, 2200));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    final mockUser = MockUser(
      uid: _testUid,
      phoneNumber: '+15551234567',
      displayName: 'Test User',
    );
    mockAuth = MockFirebaseAuth(mockUser: mockUser, signedIn: true);
    fakeFirestore = FakeFirebaseFirestore();

    await fakeFirestore.collection('users').doc(_testUid).set({
      'uid': _testUid,
      'phoneNumber': '+15551234567',
      'displayName': 'Test User',
      'permissionsPrompted': true,
      'settings': {
        'metadataCapture': true,
        'endToEndEncryption': true,
        'stealthMode': false,
        'incomingCallCard': true,
        'anniversaryReminders': true,
        'captureContextAutomatically': true,
        'locationAccess': true,
        'contactsAccess': true,
        'shareMetadata': false,
      },
    });

    await fakeFirestore
        .collection('users')
        .doc(_testUid)
        .collection('contacts')
        .doc(_testContactId)
        .set({
          'fullName': 'Jane Doe',
          'phoneNumber': '+15559876543',
          'notes': 'Met at a conference',
          'photoUrl': null,
          'source': 'manual',
          'location': {
            'lat': 28.6139,
            'lng': 77.2090,
            'address': 'Connaught Place, Delhi',
            'placeName': 'Sample Cafe',
          },
          'eventDate': Timestamp.now(),
          'createdAt': Timestamp.now(),
          'updatedAt': Timestamp.now(),
        });

    final EncounterDetails details = EncounterDetails(
      placeName: 'Cafe',
      address: 'Main Street',
      longitude: '77.2090',
      latitude: '28.6139',
      date: '24/07/2026',
      time: '10:30',
      note: 'Sample note',
      timeline: [
        TimelineEntry(
          id: 'timeline-1',
          label: 'FIRST MET',
          title: 'Demo Event',
          subtitle: 'Central Park',
          date: DateTime(2026, 5, 14),
        ),
      ],
    );

    final List<Widget> screens = <Widget>[
      const LoginScreen(),
      const OtpScreen(phoneNumber: '+919999999999', verificationId: 'test-verification-id'),
      const NameScreen(),
      const HomeScreen(),
      const ContactScreen(),
      const AllContactsScreen(),
      const NotificationScreen(),
      const RecentCallLogsScreen(),
      const SettingsScreen(),
      const ProfileScreen(),
      const SupportCenterScreen(),
      const CaptureContextScreen(contactId: _testContactId),
      const EventDetailScreen(contactId: _testContactId),
      const SavedContactDetailsScreen(contactId: _testContactId),
      CallingScreen(
        callerName: 'Riya Sharma',
        phoneNumber: '+91 98765 43210',
        encounterDetails: details,
      ),
      CallingScreen(
        callerName: 'Unknown caller',
        phoneNumber: '+1 555 000 1234',
        isIncoming: true,
        encounterDetails: EncounterDetails.unknownCaller(),
      ),
    ];

    for (final Widget screen in screens) {
      await pumpScreen(tester, screen);
      expect(find.byType(screen.runtimeType), findsOneWidget);
    }
  });
}

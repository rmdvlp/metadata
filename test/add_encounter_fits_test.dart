import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metadata/models/timeline_entry.dart';
import 'package:metadata/screens/add_encounter_screen.dart';

/// The Add Encounter form has to fit on screen — map, every field, and both
/// buttons visible at once with no scrolling. The scroll view stays for the
/// keyboard-open case, but at rest there must be nothing to scroll.
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
              return 0; // denied — no geocoding, no real device
            default:
              return null;
          }
        });
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(locationChannel, null);
  });

  /// Pumps in edit mode so the screen skips its async location lookup and
  /// settles deterministically; the layout is identical either way.
  Future<double> scrollExtentAt(
    WidgetTester tester,
    Size size, {
    required EdgeInsets padding,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(size: size, padding: padding),
            child: AddEncounterScreen(
              contactId: 'c1',
              existing: TimelineEntry(
                id: 't1',
                label: 'MET',
                title: 'Blue Bottle Coffee',
                subtitle: '1 Main St, Springfield',
                date: DateTime(2026, 5, 14, 10, 30),
                lat: 28.6139,
                lng: 77.2090,
                role: 'Met',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    return tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .maxScrollExtent;
  }

  const phones = <String, (Size, EdgeInsets)>{
    'iPhone SE': (Size(375, 667), EdgeInsets.only(top: 20)),
    'iPhone 13': (Size(390, 844), EdgeInsets.only(top: 47, bottom: 34)),
    'Pixel 5': (Size(393, 851), EdgeInsets.only(top: 40, bottom: 24)),
  };

  phones.forEach((name, spec) {
    final (size, padding) = spec;
    testWidgets('the form fits without scrolling on $name', (tester) async {
      expect(await scrollExtentAt(tester, size, padding: padding), 0);
    });
  });

  testWidgets('Role is presented as required, not optional', (tester) async {
    await scrollExtentAt(
      tester,
      const Size(375, 667),
      padding: const EdgeInsets.only(top: 20),
    );

    expect(find.text('Role'), findsOneWidget);
    expect(find.text('Role (Optional)'), findsNothing);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metadata/screens/contact_screen.dart';

/// The New Contact form has to fit on screen: name, phone, notes and both
/// finish buttons visible at once, with no scrolling. The scroll view stays in
/// place for the keyboard-open case, but at rest it must have nothing to
/// scroll.
void main() {
  /// Pumps the form at a real device's logical size, including the status-bar
  /// and home-indicator insets the SafeArea eats — without them the test
  /// screen is 50-90pt taller than the phone and would pass on a layout that
  /// scrolls in the user's hand.
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
            child: const ContactScreen(),
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

  testWidgets('both finish buttons are on screen, not just in the tree', (
    tester,
  ) async {
    await scrollExtentAt(
      tester,
      const Size(375, 667),
      padding: const EdgeInsets.only(top: 20),
    );

    for (final label in ['Capture Context Automatically', 'Save']) {
      final rect = tester.getRect(find.text(label));
      expect(
        rect.bottom,
        lessThanOrEqualTo(667),
        reason: '$label is below the fold',
      );
    }
  });
}

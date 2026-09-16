import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metadata/models/contact_model.dart';
import 'package:metadata/widgets/contact_tile.dart';

ContactModel _contact({bool isBlocked = false}) => ContactModel(
  id: 'c1',
  fullName: 'Ada Lovelace',
  phoneNumber: '+14155550101',
  isBlocked: isBlocked,
);

Future<void> _pumpTile(
  WidgetTester tester, {
  required bool isBlocked,
  required VoidCallback onCallTap,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ContactTile(
          contact: _contact(isBlocked: isBlocked),
          subtitle: const Text('subtitle'),
          onCallTap: onCallTap,
          onFavoriteTap: () {},
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('a blocked contact is marked and cannot be called from the list',
      (tester) async {
    var called = false;
    await _pumpTile(tester, isBlocked: true, onCallTap: () => called = true);

    expect(find.text('Blocked'), findsOneWidget);

    final callButton = tester.widget<IconButton>(find.byType(IconButton));
    expect(callButton.onPressed, isNull);

    await tester.tap(find.byType(IconButton));
    await tester.pump();
    expect(called, isFalse);
  });

  testWidgets('an ordinary contact has no badge and calls normally', (
    tester,
  ) async {
    var called = false;
    await _pumpTile(tester, isBlocked: false, onCallTap: () => called = true);

    expect(find.text('Blocked'), findsNothing);

    await tester.tap(find.byType(IconButton));
    await tester.pump();
    expect(called, isTrue);
  });

  testWidgets('a long name still leaves room for the blocked badge', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ContactTile(
            contact: const ContactModel(
              id: 'c1',
              fullName: 'Bartholomew Featherstonehaugh-Cholmondeley',
              phoneNumber: '+14155550101',
              isBlocked: true,
            ),
            subtitle: const Text('subtitle'),
            onCallTap: () {},
            onFavoriteTap: () {},
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull, reason: 'no RenderFlex overflow');
    expect(find.text('Blocked'), findsOneWidget);
  });
}

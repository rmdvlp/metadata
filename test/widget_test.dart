import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:metadata/screens/contact_screen.dart';
import 'package:metadata/widgets/contact_avatar.dart';

void main() {
  testWidgets('contact screen shows the add new contact form', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1080, 2200));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: ContactScreen())),
    );

    expect(find.text('New Contact'), findsOneWidget);
    expect(find.text('Add Photo (optional)'), findsOneWidget);
    expect(find.text('Full Name'), findsOneWidget);
    expect(find.text('Phone Number'), findsOneWidget);
    expect(find.byType(ContactAvatar), findsOneWidget);
    expect(find.byType(TextFormField), findsNWidgets(3));
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metadata/utils/app_colors.dart';
import 'package:metadata/widgets/app_back_button.dart';

void main() {
  group('AppBackButton', () {
    testWidgets('is a 40pt grey circle with a blue rounded arrow', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Center(child: AppBackButton())),
        ),
      );

      expect(tester.getSize(find.byType(AppBackButton)), const Size(40, 40));
      final icon = tester.widget<Icon>(find.byType(Icon));
      expect(icon.icon, Icons.arrow_back_rounded);
      expect(icon.color, AppColors.primaryBlue);
      final decoration =
          tester.widget<Container>(find.byType(Container)).decoration
              as BoxDecoration;
      expect(decoration.color, AppColors.mutedGray);
      expect(decoration.shape, BoxShape.circle);
    });

    testWidgets('in an app bar it sits on the 16pt content margin', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(
              leading: const AppBackButton.appBar(),
              leadingWidth: AppBackButton.leadingWidth,
              title: const Text('Title'),
            ),
          ),
        ),
      );

      final rect = tester.getRect(find.byType(InkWell));
      expect(rect.left, 16);
      expect(rect.size, const Size(40, 40));
    });

    testWidgets('pops the route by default', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => Scaffold(
                      appBar: AppBar(
                        leading: const AppBackButton.appBar(),
                        leadingWidth: AppBackButton.leadingWidth,
                      ),
                      body: const Text('second'),
                    ),
                  ),
                ),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(find.text('second'), findsOneWidget);

      await tester.tap(find.byType(AppBackButton));
      await tester.pumpAndSettle();
      expect(find.text('second'), findsNothing);
      expect(find.text('go'), findsOneWidget);
    });

    testWidgets('an explicit onPressed wins over popping', (tester) async {
      var tapped = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(child: AppBackButton(onPressed: () => tapped++)),
          ),
        ),
      );

      await tester.tap(find.byType(AppBackButton));
      expect(tapped, 1);
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metadata/utils/app_images.dart';
import 'package:metadata/widgets/auth_shell.dart';

/// iPhone 14-ish metrics: a notch to clear and a keyboard tall enough to eat
/// most of the illustration slot.
const Size _screen = Size(390, 844);
const double _keyboardInset = 336;

Widget _harness({required double bottomInset, required double formHeight}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(
        size: _screen,
        padding: const EdgeInsets.only(top: 47),
        viewInsets: EdgeInsets.only(bottom: bottomInset),
      ),
      child: AuthShell(
        illustrationAsset: AppImages.otp,
        child: SizedBox(height: formHeight, width: double.infinity),
      ),
    ),
  );
}

Size? _illustrationSize(WidgetTester tester) {
  final images = find.byType(Image);
  if (images.evaluate().isEmpty) return null;
  return tester.getSize(images.first);
}

void main() {
  testWidgets('illustration fills its slot when the keyboard is closed', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(_screen);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_harness(bottomInset: 0, formHeight: 300));

    expect(tester.takeException(), isNull);
    // 0.68 * 390 = 265.2, the shell's intended illustration size.
    expect(_illustrationSize(tester)!.height, closeTo(265.2, 0.5));
  });

  testWidgets('illustration gives way to the form when the keyboard opens', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(_screen);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_harness(bottomInset: 0, formHeight: 300));
    expect(_illustrationSize(tester), isNotNull);

    await tester.pumpWidget(
      _harness(bottomInset: _keyboardInset, formHeight: 300),
    );

    expect(tester.takeException(), isNull, reason: 'no RenderFlex overflow');
    expect(_illustrationSize(tester), isNull);
  });

  testWidgets('illustration scales down rather than overflowing a short '
      'screen', (tester) async {
    // No keyboard here — a small device with a tall form still has to fit the
    // illustration into whatever the card leaves behind.
    const small = Size(360, 640);
    await tester.binding.setSurfaceSize(small);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: small,
            padding: EdgeInsets.only(top: 24),
          ),
          child: AuthShell(
            illustrationAsset: AppImages.otp,
            child: const SizedBox(height: 380, width: double.infinity),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull, reason: 'no RenderFlex overflow');
    final side = _illustrationSize(tester)!.height;
    expect(side, greaterThan(0));
    // Smaller than the 0.68-of-width it would take on a roomier screen.
    expect(side, lessThan(0.68 * small.width));
  });

  testWidgets('illustration is dropped when a tall form plus keyboard leaves '
      'no room', (tester) async {
    await tester.binding.setSurfaceSize(_screen);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _harness(bottomInset: _keyboardInset, formHeight: 700),
    );

    expect(tester.takeException(), isNull, reason: 'no RenderFlex overflow');
    expect(_illustrationSize(tester), isNull);
  });

  testWidgets('form content stays scrollable above an open keyboard', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(_screen);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _harness(bottomInset: _keyboardInset, formHeight: 700),
    );

    final scrollable = find.byType(SingleChildScrollView);
    expect(scrollable, findsOneWidget);
    // The card never grows past the viewport; the overflow scrolls instead.
    expect(tester.getSize(scrollable).height, lessThanOrEqualTo(_screen.height));

    await tester.drag(scrollable, const Offset(0, -200));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}

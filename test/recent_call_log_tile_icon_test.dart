import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metadata/models/call_log_model.dart';
import 'package:metadata/models/contact_model.dart';
import 'package:metadata/repositories/call_log_repository.dart';
import 'package:metadata/utils/app_images.dart';
import 'package:metadata/widgets/recent_call_log_tile.dart';

RecentCallLog _row(
  CallLogStatus status,
  CallDirection direction, {
  bool blocked = false,
}) {
  return RecentCallLog(
    entry: CallLogEntry(
      id: 'l1',
      contactId: 'c1',
      calleeName: 'Ada',
      calleePhone: '+14155550101',
      status: status,
      direction: direction,
      startedAt: DateTime(2026, 8, 10, 9),
    ),
    contact: ContactModel(
      id: 'c1',
      fullName: 'Ada',
      phoneNumber: '+14155550101',
      isBlocked: blocked,
    ),
  );
}

Finder _assetImage(String assetName) {
  return find.byWidgetPredicate(
    (widget) =>
        widget is Image &&
        widget.image is AssetImage &&
        (widget.image as AssetImage).assetName == assetName,
  );
}

void main() {
  Future<void> pumpTile(WidgetTester tester, RecentCallLog log) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(body: RecentCallLogTile(log: log)),
        ),
      ),
    );
    await tester.pump();
  }

  group('trailing call button shows the call outcome', () {
    testWidgets('an outgoing call shows the outgoing arrow', (tester) async {
      await pumpTile(tester, _row(CallLogStatus.dialed, CallDirection.outgoing));

      expect(_assetImage(AppImages.callOutgoing), findsOneWidget);
      expect(_assetImage(AppImages.callCalling), findsNothing);
    });

    testWidgets('a received call shows the incoming arrow', (tester) async {
      await pumpTile(
        tester,
        _row(CallLogStatus.received, CallDirection.incoming),
      );

      expect(_assetImage(AppImages.callIncoming), findsOneWidget);
    });

    testWidgets('a completed call follows its direction', (tester) async {
      await pumpTile(
        tester,
        _row(CallLogStatus.completed, CallDirection.incoming),
      );
      expect(_assetImage(AppImages.callIncoming), findsOneWidget);

      await pumpTile(
        tester,
        _row(CallLogStatus.completed, CallDirection.outgoing),
      );
      expect(_assetImage(AppImages.callOutgoing), findsOneWidget);
    });

    testWidgets('a missed call shows the missed icon', (tester) async {
      await pumpTile(tester, _row(CallLogStatus.missed, CallDirection.incoming));

      expect(find.byIcon(Icons.call_missed_rounded), findsOneWidget);
      // The old duplicate arrow in the subtitle is gone.
      expect(_assetImage(AppImages.callIncoming), findsNothing);
    });

    testWidgets('a declined call shows the declined icon', (tester) async {
      await pumpTile(
        tester,
        _row(CallLogStatus.declined, CallDirection.incoming),
      );

      expect(find.byIcon(Icons.phone_disabled_rounded), findsOneWidget);
    });

    testWidgets('the outcome icon still starts a call on tap', (tester) async {
      await pumpTile(tester, _row(CallLogStatus.dialed, CallDirection.outgoing));

      final button = tester.widget<IconButton>(find.byType(IconButton));
      expect(button.onPressed, isNotNull);
    });

    testWidgets('a blocked contact keeps the disabled phone image', (
      tester,
    ) async {
      await pumpTile(
        tester,
        _row(CallLogStatus.missed, CallDirection.incoming, blocked: true),
      );

      expect(_assetImage(AppImages.callCalling), findsOneWidget);
      expect(find.byIcon(Icons.call_missed_rounded), findsNothing);
      expect(
        tester.widget<IconButton>(find.byType(IconButton)).onPressed,
        isNull,
      );
    });
  });
}

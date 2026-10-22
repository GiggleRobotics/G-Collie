import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:g_collie_flutter/ui.dart';

void main() {
  testWidgets(
    'calendar preserves unknown values, real zeros and monthly totals',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final now = DateTime.now();
      final prefix = '${now.year}-${now.month.toString().padLeft(2, '0')}';
      final daily = [
        {
          'date': '$prefix-01',
          'usage': {'total': 100},
        },
        {
          'date': '$prefix-02',
          'usage': {'total': 0},
        },
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: CollieCalendar(daily: daily, mode: 'daily'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('100'), findsOneWidget);
      expect(find.text('0'), findsOneWidget);
      expect(find.text('—'), findsWidgets);
      await tester.tap(find.text('3').first);
      await tester.pump();
      expect(find.text('$prefix-03 · 未返回用量'), findsOneWidget);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: CollieCalendar(daily: daily, mode: 'monthly'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('12月'), findsOneWidget);
      expect(find.text('2 天有记录'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

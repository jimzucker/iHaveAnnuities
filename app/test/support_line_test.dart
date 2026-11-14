// Copyright 2026 Jim Zucker
// SPDX-License-Identifier: LicenseRef-Proprietary
// Optional support line on the detail page's index chart: the lowest close in
// the last 3 months, remembered on/off setting, and the chip. Synthetic data.

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ihaveannuities/core/models.dart';
import 'package:ihaveannuities/core/payoff.dart';
import 'package:ihaveannuities/data/market.dart';
import 'package:ihaveannuities/data/portfolio_store.dart';
import 'package:ihaveannuities/ui/holding_detail.dart';
import 'package:ihaveannuities/ui/index_period_chart.dart';

int _e(int y, int m, int d) =>
    DateTime.utc(y, m, d).millisecondsSinceEpoch ~/ 1000;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('supportLevel', () {
    test('is the lowest close in the 3 months up to the latest close', () {
      final s = [
        (DateTime(2026, 7, 1), 50.0), // older than 3 months: ignored
        (DateTime(2026, 8, 13), 90.0), // exactly 3 months back: counted
        (DateTime(2026, 9, 1), 95.0),
        (DateTime(2026, 10, 1), 88.0), // the lowest in the window
        (DateTime(2026, 11, 13), 100.0),
      ];
      expect(supportLevel(s), 88.0);
    });

    test('the window start is inclusive', () {
      final s = [
        (DateTime(2026, 8, 13), 70.0),
        (DateTime(2026, 11, 13), 100.0),
      ];
      expect(supportLevel(s), 70.0);
    });

    test('no data gives no line', () => expect(supportLevel(const []), isNull));
  });

  group('supportLabel', () {
    test('NDX also shows the matching QQQ price', () {
      // 26,800 / 41.1 = 652.07 -> $652
      expect(supportLabel(26800, 'NDX'), 'support 26,800.00 (QQQ ≈ \$652)');
    });
    test('other indexes show the level only', () {
      expect(supportLabel(6500, 'SPX'), 'support 6,500.00');
    });
  });

  test('the on/off setting is off by default and remembered', () async {
    final store = PortfolioStore();
    await store.init();
    expect(store.showSupport, isFalse);
    await store.setShowSupport(true);
    expect(store.showSupport, isTrue);

    final again = PortfolioStore();
    await again.init();
    expect(again.showSupport, isTrue);
  });

  group('chip', () {
    final hist = '{"asOf":"2026-06-20","daily":{"NDX":'
        '[[${_e(2026, 6, 1)},100.0],[${_e(2026, 6, 10)},97.0],'
        '[${_e(2026, 6, 19)},101.0]]},"intraday":{}}';
    final h = Holding(
      issuer: 'TESTCO',
      index: 'NDX',
      account: AccountType.ira,
      cap: 0.20,
      participation: 1.0,
      floor: -0.10,
      floorType: FloorType.hard,
      strike: 100,
      currentLevel: 101,
      openDate: DateTime(2026, 6, 1),
      lastReset: DateTime(2026, 6, 1),
      maturity: DateTime(2029, 6, 1),
      nextReset: DateTime(2029, 6, 1),
      resetFreq: ResetFreq.inception,
      initial: 10.0,
      realized: 0.0,
    );

    Future<void> pump(WidgetTester tester,
            {bool on = false, ValueChanged<bool>? onChanged, Holding? holding}) async {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: SizedBox(
                  width: 800,
                  child: IndexPeriodChart(
                      holding: holding ?? h,
                      client: MockClient((_) async => http.Response(hist, 200)),
                      showSupport: on,
                      onSupportChanged: onChanged)))));
      await tester.pumpAndSettle();
    }

    testWidgets('tapping it asks to turn the line on, then off',
        (tester) async {
      final asked = <bool>[];
      await pump(tester, onChanged: asked.add);
      expect(tester.widget<FilterChip>(find.byType(FilterChip)).selected, isFalse);
      await tester.tap(find.text('Support'));
      expect(asked, [true]);

      await pump(tester, on: true, onChanged: asked.add);
      expect(tester.widget<FilterChip>(find.byType(FilterChip)).selected, isTrue);
      await tester.tap(find.text('Support'));
      expect(asked, [true, false]);
      expect(tester.takeException(), isNull);
    });

    testWidgets('label near the strike still draws (moved to the left end)',
        (tester) async {
      // Strike 97.5, 3-month low 97: the two labels would be about a pixel
      // apart, which triggers the left-end placement.
      await pump(tester,
          on: true, onChanged: (_) {}, holding: h.copyWith(strike: 97.5));
      expect(tester.takeException(), isNull);
    });

    testWidgets('on the detail page the chip turns the setting on and off',
        (tester) async {
      tester.view.physicalSize = const Size(1000, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final store = PortfolioStore(
          client: MockClient((_) async => http.Response(hist, 200)))
        ..debugSeed([h],
            Market(asOf: DateTime(2026, 6, 20), spx: 1, ndx: 101, rut: 1));
      addTearDown(store.dispose);
      await tester.pumpWidget(ChangeNotifierProvider.value(
        value: store,
        child: MaterialApp(home: HoldingDetail(holding: store.holdings.single)),
      ));
      await tester.pumpAndSettle();

      expect(store.showSupport, isFalse);
      await tester.tap(find.text('Support'));
      await tester.pumpAndSettle();
      expect(store.showSupport, isTrue);
      expect(tester.widget<FilterChip>(find.byType(FilterChip)).selected, isTrue);
      expect((await SharedPreferences.getInstance()).getBool('showSupport.v1'),
          isTrue);

      await tester.tap(find.text('Support'));
      await tester.pumpAndSettle();
      expect(store.showSupport, isFalse);
    });

    testWidgets('no chip when the caller gives no way to change it',
        (tester) async {
      await pump(tester);
      expect(find.byType(FilterChip), findsNothing);
    });
  });
}

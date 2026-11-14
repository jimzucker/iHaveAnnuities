// Copyright 2026 Jim Zucker
// SPDX-License-Identifier: LicenseRef-Proprietary
// The detail page's description and both charts must describe each protection
// type the way the payoff engine computes it. A Floor below 0% is a maximum
// loss (losses count one for one until the floor), not a buffer; None has no
// loss-free zone. Synthetic data only.

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
import 'package:ihaveannuities/ui/payoff_chart.dart';

int _e(int y, int m, int d) =>
    DateTime.utc(y, m, d).millisecondsSinceEpoch ~/ 1000;

// SPX since the last reset (2026-06-01), ending just under the strike of 100.
final _histJson = '{"asOf":"2026-06-20","daily":{"SPX":'
    '[[${_e(2026, 6, 1)},100.0],[${_e(2026, 6, 10)},101.0],'
    '[${_e(2026, 6, 19)},99.76]]},"intraday":{}}';

Holding _h(FloorType type, double floor) => Holding(
      issuer: 'TESTCO',
      index: 'SPX',
      account: AccountType.nonQual,
      cap: 0.42,
      participation: 2.0,
      floor: floor,
      floorType: type,
      strike: 100,
      currentLevel: 99.76, // -0.24% from strike
      openDate: DateTime(2026, 6, 1),
      lastReset: DateTime(2026, 6, 1),
      maturity: DateTime(2029, 6, 1),
      nextReset: DateTime(2029, 6, 1),
      resetFreq: ResetFreq.inception,
      initial: 10.0,
      realized: 0.0,
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // The payoff engine is the reference the display must agree with.
  test('engine: at -0.24% a -15% Floor loses 0.24%, a -15% buffer loses 0', () {
    expect(_h(FloorType.floor, -0.15).projGain, closeTo(-0.0024, 1e-9));
    expect(_h(FloorType.hard, -0.15).projGain, 0.0);
  });

  group('detail page description', () {
    Future<void> pump(WidgetTester tester, Holding h) async {
      tester.view.physicalSize = const Size(1000, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final store = PortfolioStore(
          client: MockClient((_) async => http.Response('x', 500)))
        ..debugSeed([h],
            Market(asOf: DateTime(2026, 6, 20), spx: 99.76, ndx: 1, rut: 1));
      addTearDown(store.dispose);
      await tester.pumpWidget(ChangeNotifierProvider.value(
        value: store,
        child: MaterialApp(home: HoldingDetail(holding: store.holdings.single)),
      ));
      await tester.pumpAndSettle();
    }

    final cases = {
      (FloorType.floor, -0.15):
          'losses count one for one, up to a maximum loss of 15.00%',
      (FloorType.hard, -0.15): 'a 15.00% buffer absorbs the first losses',
      (FloorType.soft, -0.15):
          'protected unless it falls past 15.00% (then full loss)',
      (FloorType.none, 0.0): 'you take the full index loss (no protection)',
      (FloorType.floor, 0.0): 'no loss if it falls',
    };
    cases.forEach((c, phrase) {
      testWidgets('${c.$1.name} ${c.$2}: "$phrase"', (tester) async {
        await pump(tester, _h(c.$1, c.$2));
        expect(find.textContaining(phrase), findsOneWidget);
        if (c.$1 == FloorType.floor) {
          expect(find.textContaining('buffer'), findsNothing);
        }
      });
    });
  });

  group('index chart legend and caption', () {
    Future<void> pump(WidgetTester tester, Holding h) async {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: SizedBox(
                  width: 800,
                  child: IndexPeriodChart(
                      holding: h,
                      client: MockClient(
                          (_) async => http.Response(_histJson, 200)))))));
      await tester.pumpAndSettle();
    }

    // (type, floor) -> (shows 'no loss', shows 'loss', caption phrase)
    final cases = {
      (FloorType.floor, -0.15): (false, true, 'Red = loss zone'),
      (FloorType.none, 0.0): (false, true, 'Red = loss zone'),
      (FloorType.hard, -0.15): (true, true, 'Green = no-loss zone'),
      (FloorType.soft, -0.15): (true, true, 'Green = no-loss zone'),
      (FloorType.floor, 0.0): (true, false, 'Green = no-loss zone'),
    };
    cases.forEach((c, want) {
      testWidgets('${c.$1.name} ${c.$2}', (tester) async {
        await pump(tester, _h(c.$1, c.$2));
        // The real chart drew (not the fallback payoff diagram).
        expect(find.textContaining('since the last reset'), findsOneWidget);
        expect(find.text('no loss'), want.$1 ? findsOneWidget : findsNothing);
        expect(find.text('loss'), want.$2 ? findsOneWidget : findsNothing);
        expect(find.textContaining(want.$3), findsOneWidget);
      });
    });
  });

  group('payoff chart legend', () {
    Future<void> pump(WidgetTester tester, Holding h) =>
        tester.pumpWidget(MaterialApp(
            home: Scaffold(
                body: SizedBox(width: 600, child: PayoffChart(holding: h)))));

    testWidgets('a -15% Floor is labelled max loss, not buffer', (tester) async {
      await pump(tester, _h(FloorType.floor, -0.15));
      expect(find.text('max loss'), findsOneWidget);
      expect(find.text('buffer'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a -15% buffer is still labelled buffer', (tester) async {
      await pump(tester, _h(FloorType.hard, -0.15));
      expect(find.text('buffer'), findsOneWidget);
      expect(find.text('max loss'), findsNothing);
    });
  });
}

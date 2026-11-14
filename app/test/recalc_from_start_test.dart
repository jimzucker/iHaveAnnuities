// Copyright 2026 Jim Zucker
// SPDX-License-Identifier: LicenseRef-Proprietary
// "Recompute from start": PortfolioStore.recalcFromStart (point-to-point
// replay, point-to-point-once contracts, history unavailable) and the confirm
// dialog on the holding detail screen. Synthetic data only.

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ihaveannuities/core/models.dart';
import 'package:ihaveannuities/core/payoff.dart';
import 'package:ihaveannuities/core/reset_event.dart';
import 'package:ihaveannuities/data/market.dart';
import 'package:ihaveannuities/data/portfolio_store.dart';
import 'package:ihaveannuities/ui/holding_detail.dart';

final _market = Market(
    asOf: DateTime(2026, 6, 20), spx: 130.0, ndx: 200.0, rut: 50.0);

int _e(int y, int m, int d) =>
    DateTime.utc(y, m, d).millisecondsSinceEpoch ~/ 1000;

// SPX: 100 on the open date, 105 on the first anniversary, 126 on the second.
final _histJson = '{"asOf":"2026-06-20","daily":{"SPX":'
    '[[${_e(2024, 6, 16)},100.0],[${_e(2025, 6, 16)},105.0],'
    '[${_e(2026, 6, 16)},126.0],[${_e(2026, 6, 20)},130.0]]},"intraday":{}}';

MockClient _historyOk() => MockClient((_) async => http.Response(_histJson, 200));
MockClient _historyDown() => MockClient((_) async => http.Response('x', 500));

/// An annual point-to-point contract whose stored realized/strike/dates have
/// drifted (bogus on purpose) so a recompute has something to repair.
Holding _annual() => Holding(
      issuer: 'TESTCO',
      index: 'SPX',
      account: AccountType.nonQual,
      cap: 0.10,
      participation: 1.0,
      floor: 0,
      floorType: FloorType.floor,
      strike: 999, // drifted
      currentLevel: 130,
      openDate: DateTime(2024, 6, 16),
      lastReset: DateTime(2023, 1, 1), // drifted
      maturity: DateTime(2030, 6, 16),
      nextReset: DateTime(2029, 1, 1), // drifted
      resetFreq: ResetFreq.annual,
      initial: 10.0,
      realized: 99.0, // drifted
    );

/// A point-to-point-once contract: credited only at maturity, never during.
Holding _once() => Holding(
      issuer: 'ONCECO',
      index: 'SPX',
      account: AccountType.ira,
      cap: 0.30,
      participation: 1.0,
      floor: -0.10,
      floorType: FloorType.hard,
      strike: 777, // drifted
      currentLevel: 130,
      openDate: DateTime(2024, 6, 16),
      lastReset: DateTime(2025, 1, 1), // drifted
      maturity: DateTime(2029, 6, 16),
      nextReset: DateTime(2029, 6, 16),
      resetFreq: ResetFreq.inception,
      initial: 10.0,
      realized: 5.0, // drifted
    );

ResetEvent _staleEvent(Holding h) => ResetEvent(
      holdingKey: h.key,
      label: h.position,
      date: DateTime(2023, 1, 1),
      isIncomeNote: false,
      periodReturn: 0.5,
      realizedAddedK: 5.0,
      realizedAfterK: 99.0,
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('recalcFromStart', () {
    test('replays an annual contract from its open date', () async {
      final h = _annual();
      final other = _once();
      final otherEvent = _staleEvent(other);
      final store = PortfolioStore(client: _historyOk())
        ..debugSeed([h, other], _market,
            resetHistory: [_staleEvent(h), otherEvent]);
      addTearDown(store.dispose);

      final n = await store.recalcFromStart(h);

      // Two anniversaries (16-Jun-25, 16-Jun-26) fall on or before asOf 20-Jun-26.
      expect(n, 2);
      final r = store.holdings.firstWhere((x) => x.key == h.key);
      // Strike re-derived from the open-date level: 100.
      // Year 1: 105/100 − 1 = +5% (under the 10% cap) → 10 × 0.05 = 0.5.
      // Year 2: 126/105 − 1 = +20% → capped 10% on the reinvested base
      //         (10 + 0.5) × 0.10 = 1.05. Realized = 0.5 + 1.05 = 1.55.
      expect(r.realized, closeTo(1.55, 1e-9));
      expect(r.strike, 126.0); // strike resets to the last reset-date level
      expect(r.lastReset, DateTime(2026, 6, 16));
      expect(r.nextReset, DateTime(2027, 6, 16));
      expect(r.currentLevel, 130.0); // revalued at today's market price

      // This holding's stale event is replaced by the two replayed ones
      // (newest first); the other holding's history is kept untouched.
      final mine =
          store.resetHistory.where((e) => e.holdingKey == h.key).toList();
      expect(mine.map((e) => e.date),
          [DateTime(2026, 6, 16), DateTime(2025, 6, 16)]);
      expect(mine.map((e) => e.newStrike), [126.0, 105.0]);
      expect(mine.map((e) => e.oldStrike), [105.0, 100.0]);
      expect(mine.last.realizedAddedK, closeTo(0.5, 1e-9));
      expect(mine.first.realizedAddedK, closeTo(1.05, 1e-9));
      expect(store.resetHistory.where((e) => e.holdingKey == other.key),
          [otherEvent]);

      // The other holding is not changed.
      final o = store.holdings.firstWhere((x) => x.key == other.key);
      expect(o.realized, 5.0);
      expect(o.strike, 777);
    });

    test('a point-to-point-once contract keeps its single credit date',
        () async {
      final h = _once();
      final store = PortfolioStore(client: _historyOk())
        ..debugSeed([h], _market, resetHistory: [_staleEvent(h)]);
      addTearDown(store.dispose);

      final n = await store.recalcFromStart(h);

      // Credited only at maturity (16-Jun-29, after asOf) → nothing to replay.
      expect(n, 0);
      final r = store.holdings.single;
      expect(r.realized, 0.0); // drifted 5.0 cleared back to inception
      expect(r.strike, 100.0); // open-date level (was a drifted 777)
      expect(r.lastReset, DateTime(2024, 6, 16)); // = open date
      expect(r.nextReset, DateTime(2029, 6, 16)); // kept, not advanced
      expect(store.resetHistory, isEmpty); // stale event dropped
    });

    test('history unavailable: returns -1, sets status, changes nothing',
        () async {
      final h = _annual();
      final stale = _staleEvent(h);
      final store = PortfolioStore(client: _historyDown())
        ..debugSeed([h], _market, resetHistory: [stale]);
      addTearDown(store.dispose);
      var notified = 0;
      store.addListener(() => notified++);

      final n = await store.recalcFromStart(h);

      expect(n, -1);
      expect(store.status, 'History unavailable; cannot recompute.');
      expect(notified, 1);
      final r = store.holdings.single;
      expect(r.realized, 99.0);
      expect(r.strike, 999);
      expect(r.lastReset, DateTime(2023, 1, 1));
      expect(r.nextReset, DateTime(2029, 1, 1));
      expect(store.resetHistory, [stale]);
    });
  });

  group('Recompute from start dialog', () {
    Future<PortfolioStore> pumpDetail(
        WidgetTester tester, http.Client client) async {
      tester.view.physicalSize = const Size(1000, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final store = PortfolioStore(client: client)
        ..debugSeed([_annual()], _market);
      addTearDown(store.dispose);
      await tester.pumpWidget(ChangeNotifierProvider.value(
        value: store,
        child: MaterialApp(home: HoldingDetail(holding: store.holdings.single)),
      ));
      await tester.pumpAndSettle();
      return store;
    }

    Future<void> openDialog(WidgetTester tester) async {
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Recompute from start'));
      await tester.pumpAndSettle();
      expect(find.text('Recompute from start?'), findsOneWidget);
    }

    testWidgets('Cancel leaves the holding unchanged', (tester) async {
      final store = await pumpDetail(tester, _historyOk());
      await openDialog(tester);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Recompute from start?'), findsNothing);
      expect(store.holdings.single.realized, 99.0);
      expect(store.holdings.single.strike, 999);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('Recompute replays and reports the count', (tester) async {
      final store = await pumpDetail(tester, _historyOk());
      await openDialog(tester);

      await tester.tap(find.text('Recompute'));
      await tester.pumpAndSettle();

      expect(store.holdings.single.realized, closeTo(1.55, 1e-9));
      expect(find.text('Recomputed from start — 2 resets replayed.'),
          findsOneWidget);
    });

    testWidgets('Recompute with history down shows the store status',
        (tester) async {
      final store = await pumpDetail(tester, _historyDown());
      await openDialog(tester);

      await tester.tap(find.text('Recompute'));
      await tester.pumpAndSettle();

      expect(store.holdings.single.realized, 99.0);
      expect(find.text('History unavailable; cannot recompute.'),
          findsOneWidget);
    });
  });
}

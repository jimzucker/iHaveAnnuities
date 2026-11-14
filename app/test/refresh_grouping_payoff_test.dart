// Copyright 2026 Jim Zucker
// SPDX-License-Identifier: LicenseRef-Proprietary
// Coverage for three gaps: refreshing prices when the app comes back to the
// foreground (onResume), ordering table groups when some subtotals are missing
// or equal, and the payoff chart for None / Soft protection and income notes.

import 'dart:convert';
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ihaveannuities/core/models.dart';
import 'package:ihaveannuities/core/payoff.dart';
import 'package:ihaveannuities/data/biometric.dart';
import 'package:ihaveannuities/data/market.dart';
import 'package:ihaveannuities/data/portfolio_store.dart';
import 'package:ihaveannuities/data/vault.dart';
import 'package:ihaveannuities/ui/payoff_chart.dart';
import 'package:ihaveannuities/ui/portfolio_table.dart';

const _marketJson =
    '{"asOf":"2026-06-12","tradingDay":true,"spx":7431.46,"ndx":29635.95,"rut":2943.99}';

int _epoch(int y, int m, int d) =>
    DateTime.utc(y, m, d).millisecondsSinceEpoch ~/ 1000;

/// A fake server that counts market.json and history.json requests, and can be
/// switched between "down" (every request 500s) and "up".
class _Server {
  _Server({this.up = true, this.historyJson = '{"daily":{},"intraday":{}}'});
  bool up;
  String historyJson;
  int marketHits = 0, historyHits = 0;

  http.Client get client => MockClient((req) async {
        final isHistory = req.url.path.contains('history');
        if (isHistory) {
          historyHits++;
        } else if (req.url.path.contains('market')) {
          marketHits++;
        }
        if (!up) return http.Response('down', 500);
        return http.Response(isHistory ? historyJson : _marketJson, 200);
      });
}

class _FakeBio implements BiometricAuthenticator {
  final Uint8List secret = Uint8List.fromList(List.filled(32, 7));
  @override
  Future<bool> isSupported() async => false;
  @override
  Future<BiometricEnrollment?> enroll() async => null;
  @override
  Future<Uint8List?> authenticate(String credentialId) async => null;
}

Holding _holding({
  required String issuer,
  String index = 'SPX',
  double strike = 100,
  double initial = 100,
  double? cap,
  double floor = 0,
  FloorType floorType = FloorType.hard,
  DateTime? nextReset,
  DateTime? lastReset,
  DateTime? openDate,
  ResetFreq resetFreq = ResetFreq.annual,
  bool isIncomeNote = false,
}) =>
    Holding(
      issuer: issuer,
      index: index,
      account: AccountType.nonQual,
      cap: cap,
      participation: 1.0,
      floor: floor,
      floorType: floorType,
      strike: strike,
      currentLevel: strike,
      openDate: openDate ?? DateTime(2024, 6, 12),
      lastReset: lastReset ?? DateTime(2025, 6, 12),
      maturity: DateTime(2032, 6, 12),
      nextReset: nextReset ?? DateTime(2030, 6, 12),
      resetFreq: resetFreq,
      initial: initial,
      isIncomeNote: isIncomeNote,
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // ---------------------------------------------------------------- gap 5
  group('onResume (coming back to the app)', () {
    test('prices never loaded → fetches them and catches up a due reset',
        () async {
      // Same point-to-point contract as the catch-up test in data_test: index
      // 100 → 106 by the 2026-06-10 reset, so +6% of 10 is credited.
      final h = _holding(
        issuer: 'AXA',
        cap: 0.10,
        initial: 10,
        openDate: DateTime(2024, 6, 16),
        lastReset: DateTime(2025, 6, 16),
        nextReset: DateTime(2026, 6, 10),
      );
      SharedPreferences.setMockInitialValues(
          {'portfolio.v1': jsonEncode([h.toJson()])});
      final server = _Server(
          up: false,
          historyJson: '{"asOf":"2026-06-12","daily":{"SPX":'
              '[[${_epoch(2025, 6, 16)},100.0],[${_epoch(2026, 6, 10)},106.0]]},'
              '"intraday":{}}');
      final store = PortfolioStore(client: server.client);
      addTearDown(store.dispose);
      await store.init(); // server down: no prices, nothing rolled
      expect(store.market, isNull);
      expect(store.holdings.single.realized, 0);
      final marketBefore = server.marketHits;

      server.up = true;
      await store.onResume();

      expect(server.marketHits, marketBefore + 1);
      expect(store.market?.asOf, DateTime(2026, 6, 12));
      final r = store.holdings.single;
      expect(r.realized, closeTo(0.6, 1e-6)); // reset caught up on return
      expect(r.lastReset, DateTime(2026, 6, 10));
    });

    test('prices fetched moments ago → does not fetch again', () async {
      final server = _Server();
      final store = PortfolioStore(client: server.client);
      addTearDown(store.dispose);
      await store.init(); // successful fetch just now
      expect(store.market, isNotNull);
      final marketBefore = server.marketHits;
      final historyBefore = server.historyHits;

      await store.onResume();

      expect(server.marketHits, marketBefore);
      expect(server.historyHits, historyBefore);
    });

    test('vault locked → refreshes prices but does not touch holdings',
        () async {
      final server = _Server();
      final store = PortfolioStore(
          client: server.client,
          vault: Vault(kdfIterations: 1000),
          biometric: _FakeBio())
        ..debugSeed([
          _holding(issuer: 'AAA', nextReset: DateTime(2026, 6, 10)),
        ], Market(asOf: DateTime(2026, 6, 12), spx: 7431.46, ndx: 29635.95,
            rut: 2943.99));
      addTearDown(store.dispose);
      await store.enableEncryption('pass1');
      await store.lock();
      expect(store.vaultState, VaultState.locked);

      await store.onResume(); // never refreshed via the network → stale

      expect(server.marketHits, 1);
      expect(server.historyHits, 0); // no reset catch-up while locked
      expect(store.holdings, isEmpty);
      expect(store.vaultState, VaultState.locked);
    });
  });

  // ---------------------------------------------------------------- gap 6
  group('group ordering by subtotal', () {
    final cs = ColorScheme.fromSeed(seedColor: Colors.blue);
    final asOf = DateTime(2026, 6, 12);
    // SPX at 120 so each holding's gain is set by its strike.
    final market = Market(
        asOf: asOf, spx: 120, ndx: 29635.95, rut: 2943.99);

    List<String> groupOrder(PortfolioStore store) {
      final seen = <String>[];
      for (final h in PortfolioTable.orderedHoldings(store, asOf, cs)) {
        if (!seen.contains(h.issuer)) seen.add(h.issuer);
      }
      return seen;
    }

    int col(String label) => PortfolioTable.columnLabels(cs).indexOf(label);

    test('Yield: groups with no Yield go last, in first-appearance order',
        () async {
      // 'ZED' and 'ALPHA' have no principal, so their XIRR is null. ZED is
      // seeded first, so it must stay ahead of ALPHA (not alphabetical).
      final store = PortfolioStore()
        ..debugSeed([
          _holding(issuer: 'ZED', initial: 0),
          _holding(issuer: 'HIGH', strike: 100), // +20%
          _holding(issuer: 'ALPHA', initial: 0),
          _holding(issuer: 'LOW', strike: 110), // about +9%
        ], market);
      expect(store.xirrFor(store.holdings.where((h) => h.issuer == 'ZED')),
          isNull);
      expect(store.xirrFor(store.holdings.where((h) => h.issuer == 'HIGH')),
          isNotNull);
      await store.setGroupBy('Issuer');

      await store.setSort(col('Yield'), true);
      expect(groupOrder(store), ['LOW', 'HIGH', 'ZED', 'ALPHA']);

      await store.setSort(col('Yield'), false);
      expect(groupOrder(store), ['HIGH', 'LOW', 'ZED', 'ALPHA']);
    });

    test('equal subtotals keep first-appearance order', () async {
      // Both groups total 100 Initial. Ascending, A's 30 is seen first;
      // descending, B's 100 is seen first.
      final store = PortfolioStore()
        ..debugSeed([
          _holding(issuer: 'B', initial: 100),
          _holding(issuer: 'A', initial: 30),
          _holding(issuer: 'A', initial: 70),
        ], market);
      await store.setGroupBy('Issuer');

      await store.setSort(col('Initial'), true);
      expect(groupOrder(store), ['A', 'B']);

      await store.setSort(col('Initial'), false);
      expect(groupOrder(store), ['B', 'A']);
    });
  });

  // ---------------------------------------------------------------- gap 7
  group('payoff chart', () {
    Future<void> pump(WidgetTester tester, Holding h) =>
        tester.pumpWidget(MaterialApp(
            home: Scaffold(
                body: SizedBox(width: 600, child: PayoffChart(holding: h)))));

    testWidgets('no protection shows the full-loss legend', (tester) async {
      await pump(
          tester,
          _holding(
              issuer: 'N', cap: 0.12, floor: -1, floorType: FloorType.none));
      expect(find.text('full loss'), findsOneWidget);
      expect(find.text('barrier'), findsNothing);
      expect(find.text('buffer'), findsNothing);
      expect(find.bySemanticsLabel(RegExp('Protection: None')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('soft protection shows the barrier legend', (tester) async {
      await pump(
          tester,
          _holding(
              issuer: 'S', cap: 0.12, floor: -0.30, floorType: FloorType.soft));
      expect(find.text('barrier'), findsOneWidget);
      expect(find.text('full loss'), findsNothing);
      expect(find.bySemanticsLabel(RegExp('Protection: Soft')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('income note draws a flat coupon line', (tester) async {
      await pump(
          tester,
          _holding(
              issuer: 'I',
              cap: 0.12,
              floor: -0.30,
              floorType: FloorType.soft,
              resetFreq: ResetFreq.monthly,
              isIncomeNote: true));
      expect(find.byType(PayoffChart), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

// Copyright 2026 Jim Zucker
// SPDX-License-Identifier: LicenseRef-Proprietary
// Coverage for models serialization, Market, and PortfolioStore.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ihaveannuities/core/models.dart';
import 'package:ihaveannuities/core/payoff.dart';
import 'package:ihaveannuities/data/market.dart';
import 'package:ihaveannuities/data/portfolio_store.dart';
import 'package:ihaveannuities/data/tracker_xlsx.dart';
import 'package:ihaveannuities/ui/portfolio_table.dart'
    show BandAggregates, PortfolioTable;
import 'package:ihaveannuities/ui/format.dart' show indexLabel;

const _marketJson =
    '{"asOf":"2026-06-12","tradingDay":true,"spx":7431.46,"ndx":29635.95,"rut":2943.99}';

Holding _sample() => Holding(
      issuer: 'AIG',
      index: '^NDX',
      account: AccountType.ira,
      cap: 0.11,
      participation: 1.0,
      floor: -0.10,
      floorType: FloorType.hard,
      strike: 100,
      currentLevel: 110,
      openDate: DateTime(2024, 1, 2),
      lastReset: DateTime(2026, 1, 2),
      maturity: DateTime(2030, 1, 2),
      nextReset: DateTime(2027, 1, 2),
      resetFreq: ResetFreq.inception,
      initial: 100,
    );

void main() {
  group('models', () {
    test('toJson/fromJson round-trip', () {
      final h = _sample();
      final j = Holding.fromJson(h.toJson());
      expect(j.position, h.position);
      expect(j.cap, h.cap);
      expect(j.floorType, h.floorType);
      expect(j.account, h.account);
      expect(j.resetFreq, h.resetFreq);
      expect(j.currentLevel, h.currentLevel);
      expect(j.maturity, h.maturity);
      expect(j.projGain, closeTo(h.projGain, 1e-12));
    });

    test('fromJson tolerates missing optionals', () {
      final j = Holding.fromJson({
        'position': 'x',
        'openDate': '2024-01-01T00:00:00.000',
        'lastReset': '2024-01-01T00:00:00.000',
        'maturity': '2030-01-01T00:00:00.000',
        'nextReset': '2027-01-01T00:00:00.000',
      });
      expect(j.participation, 1.0);
      expect(j.cap, isNull);
      expect(j.account, AccountType.nonQual);
    });

    test('copyWith replaces only currentLevel', () {
      final h = _sample().copyWith(currentLevel: 120);
      expect(h.currentLevel, 120);
      expect(h.strike, 100);
      // no-arg keeps the original level (covers the ?? fallback branch)
      expect(_sample().copyWith().currentLevel, _sample().currentLevel);
    });

    test('baseIndex resolves each symbol', () {
      String bi(String i) {
        final j = _sample().toJson();
        j['index'] = i;
        final h = Holding.fromJson(j);
        expect(h.index, i); // guard: index actually round-tripped
        return h.baseIndex;
      }
      expect(bi('SPX'), 'SPX');
      expect(bi('NDX'), 'NDX');
      expect(bi('RUT'), 'RUT');
      expect(bi('^GSPC'), 'SPX');
      expect(bi('^NDX'), 'NDX');
      expect(bi('^RUT'), 'RUT');
      expect(bi('SPX/NDX/RUT'), 'SPX');         // v1.0 worst-of label
      expect(bi('worst-of SPX/NDX/RUT'), 'SPX'); // legacy worst-of label
      expect(bi('DOW'), 'DJI');
      expect(bi('^DJI'), 'DJI');
      expect(bi('COMP'), 'COMP');                // Nasdaq Composite, not the 100
      expect(bi('^IXIC'), 'COMP');
      expect(bi('Nasdaq Composite'), 'COMP');
    });

    test('enum labels (v1.0)', () {
      expect(ResetFreq.inception.label, 'Once');
      expect(ResetFreq.annual.label, 'Annual');
      expect(ResetFreq.monthly.label, 'Monthly');
      expect(AccountType.roth.label, 'ROTH');
      expect(AccountType.ira.label, 'IRA');
    });

    test('fromJson tolerates legacy resetFreq y4/y5/y6', () {
      final h = _sample();
      final base = h.toJson();
      for (final legacy in ['y4', 'y5', 'y6']) {
        final j = Map<String, dynamic>.from(base)..['resetFreq'] = legacy;
        expect(Holding.fromJson(j).resetFreq, ResetFreq.inception);
      }
    });
  });

  group('Market', () {
    test('parse + priceFor + bySymbol', () {
      final m = Market.parse(_marketJson);
      expect(m.spx, 7431.46);
      expect(m.priceFor('NDX'), 29635.95);
      expect(m.priceFor('RUT'), 2943.99);
      expect(m.priceFor('SPX'), 7431.46);
      expect(m.bySymbol['SPX'], 7431.46);
      expect(m.tradingDay, isTrue);
    });

    test('parses dow + comp and prices them', () {
      final m = Market.parse('{"asOf":"2026-06-12","spx":7431.46,'
          '"ndx":29635.95,"rut":2943.99,"dow":44012.10,"comp":23501.75}');
      expect(m.dow, 44012.10);
      expect(m.comp, 23501.75);
      expect(m.priceFor('DJI'), 44012.10);
      expect(m.priceFor('COMP'), 23501.75);
      expect(m.bySymbol['DJI'], 44012.10);
      expect(m.bySymbol['COMP'], 23501.75);
    });

    test('autoRefreshDue fires once per day after the trigger hour', () {
      DateTime at(int h, [int day = 16]) => DateTime(2026, 6, day, h);
      // Before 17:00 → never due.
      expect(PortfolioStore.autoRefreshDue(at(9), null), isFalse);
      // At/after 17:00 with no prior refresh → due.
      expect(PortfolioStore.autoRefreshDue(at(17), null), isTrue);
      expect(PortfolioStore.autoRefreshDue(at(20), null), isTrue);
      // Already refreshed after today's trigger → not due again today.
      expect(PortfolioStore.autoRefreshDue(at(20), at(17, 16)), isFalse);
      // Last refresh was before today's trigger → due.
      expect(PortfolioStore.autoRefreshDue(at(18), at(16, 16)), isTrue);
      // New day, last refresh was yesterday evening → due again.
      expect(PortfolioStore.autoRefreshDue(at(18, 17), at(18, 16)), isTrue);
    });

    test('older payload without dow/comp is null-safe', () {
      final m = Market.parse(_marketJson); // no dow/comp keys
      expect(m.dow, isNull);
      expect(m.comp, isNull);
      expect(m.priceFor('DJI'), m.spx); // falls back to SPX
      expect(m.priceFor('COMP'), m.spx);
      expect(m.bySymbol.containsKey('DJI'), isFalse);
    });

    test('fetch success', () async {
      final c = MockClient((_) async => http.Response(_marketJson, 200));
      final m = await Market.fetch(client: c);
      expect(m.ndx, 29635.95);
    });

    test('fetch throws on non-200', () async {
      final c = MockClient((_) async => http.Response('nope', 404));
      expect(() => Market.fetch(client: c), throwsA(isA<HttpException>()));
    });
  });

  group('PortfolioStore', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('init loads cache then applies market prices', () async {
      final c = MockClient((_) async => http.Response(_marketJson, 200));
      final store = PortfolioStore(client: c);
      final holdings =
          parseTracker(File('../data/example-portfolio.xlsx').readAsBytesSync());
      await store.replaceAll(holdings);

      final store2 = PortfolioStore(client: c);
      await store2.init();
      expect(store2.holdings.length, holdings.length);
      expect(store2.market, isNotNull);
      // NDX holdings revalued to the live NDX price.
      final ndx = store2.holdings.firstWhere((h) => h.baseIndex == 'NDX');
      expect(ndx.currentLevel, 29635.95);
    });

    test('catch-up rolls a worst-of income-note coupon on load and logs it',
        () async {
      // NATBANK example, $000 units, reset due as of the market asOf (2026-06-12).
      final note = Holding(
        issuer: 'NATBANK',
        index: 'SPX/NDX/RUT',
        account: AccountType.nonQual,
        cap: 0.1325, // 1.104%/mo
        participation: 1.0,
        floor: -0.30,
        floorType: FloorType.soft,
        strike: 6583,
        currentLevel: 6583,
        openDate: DateTime(2026, 4, 16),
        lastReset: DateTime(2026, 5, 12),
        maturity: DateTime(2029, 4, 16),
        nextReset: DateTime(2026, 6, 12),
        resetFreq: ResetFreq.monthly,
        initial: 10.0,
        realized: 0.1104,
        isIncomeNote: true,
      );
      SharedPreferences.setMockInitialValues(
          {'portfolio.v1': jsonEncode([note.toJson()])});
      int e(int y, int m, int d) =>
          DateTime.utc(y, m, d).millisecondsSinceEpoch ~/ 1000;
      // SPX 7431.46 on the reset date → worst leg +12.9%, barrier (−30%) holds.
      final histJson = '{"asOf":"2026-06-12","daily":{"SPX":'
          '[[${e(2026, 5, 12)},7000.0],[${e(2026, 6, 12)},7431.46]]},"intraday":{}}';
      final c = MockClient((req) async => http.Response(
          req.url.path.contains('history') ? histJson : _marketJson, 200));
      final store = PortfolioStore(client: c);
      addTearDown(store.dispose);
      await store.init();

      final h = store.holdings.single;
      expect(h.realized, closeTo(0.2220, 1e-4)); // coupon reinvested
      expect(h.lastReset, DateTime(2026, 6, 12));
      expect(h.nextReset, DateTime(2026, 7, 12));
      expect(h.strike, 6583); // strikes never reset
      expect(store.resetHistory, hasLength(1));
      expect(store.resetHistory.single.realizedAddedK, closeTo(0.1116, 1e-4));
      expect(store.resetHistory.single.missed, isFalse);

      // Persisted + idempotent: a fresh load doesn't roll or log again.
      final store2 = PortfolioStore(client: c);
      addTearDown(store2.dispose);
      await store2.init();
      expect(store2.holdings.single.realized, closeTo(0.2220, 1e-4));
      expect(store2.resetHistory, hasLength(1));
    });

    test('catch-up rolls a point-to-point note from market history', () async {
      final h = Holding(
        issuer: 'AXA',
        index: 'SPX',
        account: AccountType.nonQual,
        cap: 0.10,
        participation: 1.0,
        floor: 0,
        floorType: FloorType.hard,
        strike: 100,
        currentLevel: 100,
        openDate: DateTime(2024, 6, 16),
        lastReset: DateTime(2025, 6, 16),
        maturity: DateTime(2030, 6, 16),
        nextReset: DateTime(2026, 6, 10),
        resetFreq: ResetFreq.annual,
        initial: 10.0,
        realized: 0.0,
      );
      SharedPreferences.setMockInitialValues(
          {'portfolio.v1': jsonEncode([h.toJson()])});
      int e(int y, int m, int d) =>
          DateTime.utc(y, m, d).millisecondsSinceEpoch ~/ 1000;
      final histJson = '{"asOf":"2026-06-12","daily":{"SPX":'
          '[[${e(2025, 6, 16)},100.0],[${e(2026, 6, 10)},106.0]]},"intraday":{}}';
      final c = MockClient((req) async => http.Response(
          req.url.path.contains('history') ? histJson : _marketJson, 200));
      final store = PortfolioStore(client: c);
      addTearDown(store.dispose);
      await store.init();

      final r = store.holdings.single;
      // index 106 vs strike 100 → +6% credited (< 10% cap); strike resets to 106.
      expect(r.realized, closeTo(0.6, 1e-6)); // 10 * 0.06
      expect(r.strike, 106.0);
      expect(r.nextReset, DateTime(2027, 6, 10));
      expect(store.resetHistory.single.newStrike, 106.0);
      expect(store.resetHistory.single.oldStrike, 100.0);
    });

    test('recalcFromStart replays a contract from its open date', () async {
      // An income note opened 16-Apr with drifted/missing realized; recompute
      // should replay May + Jun coupons (asOf 2026-06-12 → 1 due... build it so
      // two coupons fall before asOf).
      final note = Holding(
        issuer: 'NATBANK',
        index: 'SPX/NDX/RUT',
        account: AccountType.nonQual,
        cap: 0.1325,
        participation: 1.0,
        floor: -0.30,
        floorType: FloorType.soft,
        strike: 6583,
        currentLevel: 6583,
        openDate: DateTime(2026, 4, 16),
        lastReset: DateTime(2026, 4, 16),
        maturity: DateTime(2029, 4, 16),
        nextReset: DateTime(2027, 1, 1), // wrong/drifted on purpose
        resetFreq: ResetFreq.monthly,
        initial: 10.0,
        realized: 99.0, // bogus realized to be overwritten
        isIncomeNote: true,
      );
      SharedPreferences.setMockInitialValues(
          {'portfolio.v1': jsonEncode([note.toJson()])});
      int e(int y, int m, int d) =>
          DateTime.utc(y, m, d).millisecondsSinceEpoch ~/ 1000;
      // asOf 20-Jun so both the 16-May and 16-Jun resets fall due; SPX above
      // the barrier on every reset date → both coupons paid.
      const market =
          '{"asOf":"2026-06-20","spx":7431.46,"ndx":29635.95,"rut":2943.99}';
      final histJson = '{"asOf":"2026-06-20","daily":{"SPX":'
          '[[${e(2026, 4, 16)},7000.0],[${e(2026, 5, 16)},7100.0],'
          '[${e(2026, 6, 16)},7250.0],[${e(2026, 6, 20)},7431.46]]},"intraday":{}}';
      final c = MockClient((req) async => http.Response(
          req.url.path.contains('history') ? histJson : market, 200));
      final store = PortfolioStore(client: c);
      addTearDown(store.dispose);
      await store.init();

      final n = await store.recalcFromStart(store.holdings.single);
      expect(n, 2); // 16-May + 16-Jun coupons
      final h = store.holdings.single;
      // realized reset to 0 then two coupons reinvested: 10*(1.0110417^2 - 1).
      const rate = 0.1325 / 12;
      expect(h.realized, closeTo(10 * ((1 + rate) * (1 + rate) - 1), 1e-6));
      expect(h.lastReset, DateTime(2026, 6, 16));
      expect(h.nextReset, DateTime(2026, 7, 16));
      expect(store.resetHistory.where((x) => !x.missed).length, 2);
    });

    test('refreshMarket sets status on error', () async {
      final c = MockClient((_) async => http.Response('x', 500));
      final store = PortfolioStore(client: c);
      await store.refreshMarket();
      expect(store.status, isNotNull);
    });

    test('import / export / upsert / remove / clear + totals', () async {
      final store = PortfolioStore();
      final bytes = File('../data/example-portfolio.xlsx').readAsBytesSync();
      final n = await store.importXlsx(bytes);
      expect(n, 9);
      expect(store.totalInitial, closeTo(900.0, 1e-6));
      expect(store.totalProjValue, greaterThan(0));
      // Unrealized total excludes realized: value = initial + realized + gain.
      expect(store.totalProjGain,
          closeTo(store.totalProjValue - 900.0 - store.totalRealized, 1e-6));

      // export round-trips back through the parser
      final exported = store.exportXlsx();
      expect(parseTracker(exported).length, 9);

      final first = store.holdings.first;
      final edited = first.copyWith(currentLevel: first.currentLevel);
      await store.upsert(edited, replacing: first);
      expect(store.holdings.length, 9);

      await store.upsert(_sample());
      expect(store.holdings.length, 10);

      await store.remove(store.holdings.last);
      expect(store.holdings.length, 9);

      await store.clearLocal();
      expect(store.isEmpty, isTrue);
    });

    test('sort defaults to Next Reset asc and is remembered', () async {
      final store = PortfolioStore();
      expect(store.sortColumn, PortfolioStore.defaultSortColumn);
      expect(store.sortAscending, isTrue);
      await store.setSort(1, false);

      final c = MockClient((_) async => http.Response('x', 500));
      final s2 = PortfolioStore(client: c);
      await s2.init();
      expect(s2.sortColumn, 1);
      expect(s2.sortAscending, isFalse);
    });

    test('groupBy defaults to none and is remembered', () async {
      final store = PortfolioStore();
      expect(store.groupBy, '');
      await store.setGroupBy('Issuer');
      expect(store.groupBy, 'Issuer');
      // Unknown dimensions are rejected (fall back to no grouping).
      await store.setGroupBy('Nonsense');
      expect(store.groupBy, '');
      await store.setGroupBy('Type');

      final c = MockClient((_) async => http.Response('x', 500));
      final s2 = PortfolioStore(client: c);
      await s2.init();
      expect(s2.groupBy, 'Type');
    });

    test('groupValueOf maps every dimension to its display value', () {
      final h = _sample(); // AIG · ^NDX · IRA · Hard · inception reset
      expect(PortfolioTable.groupValueOf(h, 'Issuer'), 'AIG');
      expect(PortfolioTable.groupValueOf(h, 'Type'), h.account.label);
      expect(PortfolioTable.groupValueOf(h, 'Index'), indexLabel('^NDX'));
      expect(PortfolioTable.groupValueOf(h, 'Protection'), h.protectionType);
      expect(PortfolioTable.groupValueOf(h, 'Reset Freq'), h.resetFreq.label);
      // Unknown / no dimension → empty bucket (ungrouped).
      expect(PortfolioTable.groupValueOf(h, ''), '');
    });

    test('pivot groups default collapsed; toggle + collapse/expand all', () async {
      final store = PortfolioStore();
      // Summary-first: nothing expanded → every group reads collapsed.
      expect(store.allGroupsCollapsed, isTrue);
      expect(store.isGroupCollapsed('IRA'), isTrue);

      store.toggleGroupCollapsed('IRA');
      expect(store.isGroupCollapsed('IRA'), isFalse);
      expect(store.allGroupsCollapsed, isFalse);

      store.expandAllGroups({'IRA', 'ROTH'});
      expect(store.isGroupCollapsed('ROTH'), isFalse);

      store.collapseAllGroups();
      expect(store.allGroupsCollapsed, isTrue);
      expect(store.isGroupCollapsed('IRA'), isTrue);

      // Changing the group-by dimension resets the view to collapsed.
      store.toggleGroupCollapsed('IRA');
      await store.setGroupBy('Issuer');
      expect(store.allGroupsCollapsed, isTrue);
    });

    test('TOTAL band reconciles with the hero card (regression guard)', () {
      // Uses the real sample (NATBANK carries realized income), so a ÷base vs
      // ÷principal drift on Unrealized % would break this — which is the point.
      final holdings = parseTracker(
          File('../data/example-portfolio.xlsx').readAsBytesSync());
      final store = PortfolioStore()
        ..debugSeed(holdings,
            Market(asOf: DateTime(2026, 6, 12), spx: 7431.46, ndx: 29635.95,
                rut: 2943.99, dow: 44012.10, comp: 23501.75));
      final agg = BandAggregates.of(store.holdings);

      // Dollars — the exact getters the hero renders.
      expect(agg.initial, store.totalInitial);
      expect(agg.realized, store.totalRealized);
      expect(agg.projValue, store.totalProjValue);
      expect(agg.unrealizedDollars, closeTo(store.totalProjGain, 1e-9));

      // Percentages — the hero divides both by principal; the TOTAL band must
      // match (so Return% − Unrealized% = Realized%, all over principal).
      final heroReturn =
          (store.totalProjValue - store.totalInitial) / store.totalInitial;
      final heroUnrealized = store.totalProjGain / store.totalInitial;
      expect(agg.returnPct, closeTo(heroReturn, 1e-12));
      expect(agg.unrealizedPct, closeTo(heroUnrealized, 1e-12));

      // Index Gain — principal-weighted average index move.
      final idxWeighted = store.holdings
              .fold(0.0, (s, h) => s + h.indexGain * h.initial) /
          store.totalInitial;
      expect(agg.indexGain, closeTo(idxWeighted, 1e-12));

      // Yield — the grand-total XIRR is the same value the hero headline uses.
      expect(store.xirrFor(store.holdings), store.portfolioXirr);
    });

    test('xirrFor: whole-book subset equals portfolioXirr; groups solvable', () {
      final a = _sample(); // opened 2024-01-02, initial 100
      final b = Holding(
        issuer: 'BNP',
        index: '^GSPC',
        account: AccountType.roth,
        cap: null,
        participation: 1.0,
        floor: -0.30,
        floorType: FloorType.soft,
        strike: 100,
        currentLevel: 120,
        openDate: DateTime(2025, 1, 2),
        lastReset: DateTime(2025, 1, 2),
        maturity: DateTime(2030, 1, 2),
        nextReset: DateTime(2027, 1, 2),
        resetFreq: ResetFreq.inception,
        initial: 50,
      );
      final store = PortfolioStore()
        ..debugSeed([a, b],
            Market(asOf: DateTime(2026, 6, 12), spx: 7431.46, ndx: 29635.95,
                rut: 2943.99, dow: 44012.10, comp: 23501.75));

      // The grand-total Yield uses xirrFor(all) — it must equal the hero's value.
      expect(store.xirrFor(store.holdings), store.portfolioXirr);
      // Each single-holding group resolves to a finite rate.
      for (final h in store.holdings) {
        final r = store.xirrFor([h]);
        expect(r, isNotNull);
        expect(r!.isFinite, isTrue);
      }
      // An empty group has no rate.
      expect(store.xirrFor(const []), isNull);
    });

    test('init ignores corrupt cache', () async {
      SharedPreferences.setMockInitialValues({'portfolio.v1': 'not json'});
      final c = MockClient((_) async => http.Response(_marketJson, 200));
      final store = PortfolioStore(client: c);
      await store.init();
      expect(store.isEmpty, isTrue);
    });
  });
}

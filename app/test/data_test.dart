// Copyright 2026 Jim Zucker
// SPDX-License-Identifier: Apache-2.0
// Coverage for models serialization, Market, and PortfolioStore.

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
      expect(ResetFreq.inception.label, 'Inception');
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
      expect(n, 8);
      expect(store.totalInitial, closeTo(800.0, 1e-6));
      expect(store.totalProjValue, greaterThan(0));
      // Unrealized total excludes realized: value = initial + realized + gain.
      expect(store.totalProjGain,
          closeTo(store.totalProjValue - 800.0 - store.totalRealized, 1e-6));

      // export round-trips back through the parser
      final exported = store.exportXlsx();
      expect(parseTracker(exported).length, 8);

      final first = store.holdings.first;
      final edited = first.copyWith(currentLevel: first.currentLevel);
      await store.upsert(edited, replacing: first);
      expect(store.holdings.length, 8);

      await store.upsert(_sample());
      expect(store.holdings.length, 9);

      await store.remove(store.holdings.last);
      expect(store.holdings.length, 8);

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

    test('init ignores corrupt cache', () async {
      SharedPreferences.setMockInitialValues({'portfolio.v1': 'not json'});
      final c = MockClient((_) async => http.Response(_marketJson, 200));
      final store = PortfolioStore(client: c);
      await store.init();
      expect(store.isEmpty, isTrue);
    });
  });
}

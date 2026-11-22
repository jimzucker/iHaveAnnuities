// Copyright 2026 Jim Zucker
// SPDX-License-Identifier: LicenseRef-Proprietary
// Broker name and annual broker fee: the fee math, saving and loading
// (including data saved before these fields existed), the spreadsheet
// round-trip, the form, the detail page and grouping by broker. Synthetic data.

import 'dart:convert';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ihaveannuities/core/models.dart';
import 'package:ihaveannuities/core/payoff.dart';
import 'package:ihaveannuities/core/reset_event.dart';
import 'package:ihaveannuities/core/reset_rollover.dart';
import 'package:ihaveannuities/data/market.dart';
import 'package:ihaveannuities/data/portfolio_store.dart';
import 'package:ihaveannuities/data/tracker_xlsx.dart';
import 'package:ihaveannuities/data/xlsx_reader.dart';
import 'package:ihaveannuities/ui/format.dart';
import 'package:ihaveannuities/ui/holding_detail.dart';
import 'package:ihaveannuities/ui/holding_form.dart';
import 'package:ihaveannuities/ui/portfolio_screen.dart';
import 'package:ihaveannuities/ui/portfolio_table.dart';

Holding _h({
  String issuer = 'TESTCO',
  String broker = '',
  double fee = 0,
  double initial = 100,
  double realized = 20,
  DateTime? inception,
}) =>
    Holding(
      issuer: issuer,
      index: 'SPX',
      account: AccountType.ira,
      cap: 0.20,
      participation: 1.0,
      floor: -0.10,
      floorType: FloorType.hard,
      strike: 100,
      currentLevel: 105,
      openDate: DateTime(2026, 1, 1),
      lastReset: DateTime(2026, 1, 1),
      maturity: DateTime(2030, 1, 1), // 1461 days = exactly 4.0 years
      nextReset: DateTime(2027, 1, 1),
      resetFreq: ResetFreq.annual,
      initial: initial,
      realized: realized,
      inceptionDate: inception,
      broker: broker,
      brokerFee: fee,
    );

final _market = Market(asOf: DateTime(2026, 6, 12), spx: 105, ndx: 1, rut: 1);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('fee math', () {
    test('fee per year is the rate on initial + realized', () {
      // (100 + 20) × 1% = 1.2 ($000) = $1,200 a year
      expect(_h(fee: 0.01).brokerFeePerYearK, closeTo(1.2, 1e-12));
    });

    test('fee over the term runs from the open date to maturity', () {
      final h = _h(fee: 0.01); // 4 full years at 1.2 a year
      expect(h.brokerFeeTermK(), closeTo(4.8, 1e-12));
    });

    test('a rolled contract counts the term from its inception date', () {
      // 2022-01-01 to 2030-01-01 = 2922 days = 8.0 years
      final h = _h(fee: 0.01, inception: DateTime(2022, 1, 1));
      expect(h.brokerFeeTermK(), closeTo(9.6, 1e-12));
    });

    test('maturity on or before the start gives no term fee', () {
      final h = Holding.fromJson({
        ..._h(fee: 0.01).toJson(),
        'maturity': DateTime(2025, 1, 1).toIso8601String(),
      });
      expect(h.brokerFeeTermK(), 0);
    });

    test('the fee does not change value, returns or yield', () {
      final plain = _h();
      final withFee = _h(broker: 'ACME', fee: 0.02);
      expect(withFee.projValueK, plain.projValueK);
      expect(withFee.projGainDollarsK, plain.projGainDollarsK);
      expect(withFee.totalReturnPct, plain.totalReturnPct);
      expect(withFee.lifeToDateYield(DateTime(2026, 6, 1)),
          plain.lifeToDateYield(DateTime(2026, 6, 1)));
    });

    test('no fee entered means zero fees', () {
      expect(_h().brokerFeePerYearK, 0);
      expect(_h().brokerFeeTermK(), 0);
      expect(_h().brokerFeesToDateK(DateTime(2028, 1, 1)), 0);
    });
  });

  group('saving and loading', () {
    test('saved data from before this change loads with no broker and no fee',
        () {
      // Exactly the keys an older app version wrote.
      final old = _h().toJson()
        ..remove('broker')
        ..remove('brokerFee');
      final h = Holding.fromJson(old);
      expect(h.broker, '');
      expect(h.brokerFee, 0.0);
    });

    test('a holding with no broker saves exactly what older versions saved',
        () {
      final keys = _h().toJson().keys;
      expect(keys, isNot(contains('broker')));
      expect(keys, isNot(contains('brokerFee')));
    });

    test('broker and fee survive a save and load', () {
      final back = Holding.fromJson(
          jsonDecode(jsonEncode(_h(broker: 'ACME', fee: 0.0125).toJson()))
              as Map<String, dynamic>);
      expect(back.broker, 'ACME');
      expect(back.brokerFee, 0.0125);
    });

    test('an integer fee in saved JSON still loads', () {
      final back = Holding.fromJson({..._h().toJson(), 'brokerFee': 0});
      expect(back.brokerFee, 0.0);
    });

    test('a reset keeps the broker and fee', () {
      final h = _h(broker: 'ACME', fee: 0.01);
      final rolled = applyReset(h, (_, _) => 110.0).holding;
      expect(rolled.nextReset.isAfter(h.nextReset), isTrue); // it did roll
      expect(rolled.broker, 'ACME');
      expect(rolled.brokerFee, 0.01);
    });

    test('the store loads a portfolio saved by an older version', () async {
      final old = _h().toJson()
        ..remove('broker')
        ..remove('brokerFee');
      SharedPreferences.setMockInitialValues({
        'portfolio.v1': jsonEncode([old]),
        'groupBy.v1': 'Issuer',
      });
      final store = PortfolioStore(
          client: MockClient((_) async => http.Response('x', 500)));
      await store.init();
      expect(store.holdings, hasLength(1));
      expect(store.holdings.single.broker, '');
      expect(store.holdings.single.brokerFee, 0.0);
      expect(store.groupBy, 'Issuer'); // an older saved grouping still works
    });

    test('grouping by Broker is remembered', () async {
      final store = PortfolioStore();
      await store.init();
      await store.setGroupBy('Broker');
      final again = PortfolioStore();
      await again.init();
      expect(again.groupBy, 'Broker');
    });
  });

  group('spreadsheet', () {
    test('Broker and Broker Fee columns round-trip', () {
      final bytes = writeTracker(
          [_h(broker: 'ACME', fee: 0.015), _h(issuer: 'OTHER')],
          asOf: DateTime(2026, 6, 12),
          prices: const {'SPX': 105, 'NDX': 1, 'RUT': 1});
      final back = parseTracker(bytes);
      expect(back[0].broker, 'ACME');
      expect(back[0].brokerFee, closeTo(0.015, 1e-12));
      expect(back[1].broker, ''); // blank cells read as none
      expect(back[1].brokerFee, 0.0);
    });

    test('a file without the broker columns still imports', () {
      final hs = parseTracker(
          File('../data/example-portfolio.xlsx').readAsBytesSync());
      expect(hs, isNotEmpty);
      expect(hs.every((h) => h.broker.isEmpty && h.brokerFee == 0), isTrue);
    });

    test('the new columns come last, after Inception', () {
      expect(headers.sublist(headers.length - 4),
          ['Inception', 'Broker', 'Broker Fee', 'P/L (\$000)']);
    });

    test('the export has each holding\'s P/L and the total', () {
      final hs = [_h(broker: 'ACME', fee: 0.01), _h(issuer: 'OTHER')];
      final asOf = DateTime(2028, 1, 1);
      final rows = XlsxReader.decode(writeTracker(hs,
          asOf: asOf,
          prices: const {'SPX': 105, 'NDX': 1, 'RUT': 1}))['Annuity Tracker']!;
      final hi = rows.indexWhere((r) => r.contains('Issuer'));
      final col = rows[hi].indexOf('P/L (\$000)');
      expect(rows[hi + 1][col], closeTo(hs[0].profitLossK(asOf), 1e-9));
      expect(rows[hi + 2][col], closeTo(hs[1].profitLossK(asOf), 1e-9));
      final total = rows.firstWhere((r) => r.isNotEmpty && r.first == 'TOTAL');
      expect(total[col],
          closeTo(hs[0].profitLossK(asOf) + hs[1].profitLossK(asOf), 1e-9));
      // Re-importing ignores the P/L column (it is worked out, not entered).
      expect(parseTracker(writeTracker(hs,
              asOf: asOf, prices: const {'SPX': 105, 'NDX': 1, 'RUT': 1}))
          .first
          .realized, 20);
    });
  });

  group('grouping', () {
    test('Broker is a grouping choice', () {
      expect(PortfolioStore.groupDimensions, contains('Broker'));
    });

    test('holdings group by broker; no broker groups as "No broker"', () {
      expect(PortfolioTable.groupValueOf(_h(broker: 'ACME'), 'Broker'), 'ACME');
      expect(PortfolioTable.groupValueOf(_h(), 'Broker'), 'No broker');
    });

    test('the group header adds the fees per year only when there are fees',
        () {
      final members = [_h(broker: 'ACME', fee: 0.01), _h(broker: 'ACME')];
      expect(PortfolioTable.groupLabel('ACME', members),
          'ACME  (2) · fees ${moneyK(1.2)}/yr');
      expect(PortfolioTable.groupLabel('X', [_h()]), 'X  (1)');
    });

    testWidgets('the table shows a header per broker with its fees',
        (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final store = PortfolioStore()
        ..debugSeed([
          _h(issuer: 'A', broker: 'ACME', fee: 0.01),
          _h(issuer: 'B'),
        ], _market);
      await store.setHideSummary(true);
      await store.setGroupBy('Broker');
      await tester.pumpWidget(ChangeNotifierProvider.value(
          value: store, child: const MaterialApp(home: PortfolioScreen())));
      await tester.pumpAndSettle();
      expect(find.text('ACME  (1) · fees ${moneyK(1.2)}/yr'), findsOneWidget);
      expect(find.text('No broker  (1)'), findsOneWidget);
    });
  });

  group('detail page', () {
    Future<void> pump(WidgetTester tester, Holding h) async {
      tester.view.physicalSize = const Size(1400, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final store = PortfolioStore(
          client: MockClient((_) async => http.Response('x', 500)))
        ..debugSeed([h], _market);
      addTearDown(store.dispose);
      await tester.pumpWidget(ChangeNotifierProvider.value(
        value: store,
        child: MaterialApp(home: HoldingDetail(holding: store.holdings.single)),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('shows the broker, the rate, the fee per year and over the term',
        (tester) async {
      await pump(tester, _h(broker: 'ACME', fee: 0.01));
      expect(find.text('ACME'), findsOneWidget);
      expect(find.text('1.000%/yr'), findsOneWidget); // 3 decimals
      // 2026-01-01 to 2026-06-12 is 162 of 365 days of the first year.
      expect(
          find.text('${moneyK(1.2 * 162 / 365)} to date · '
              '${moneyK(4.8)} over term'),
          findsOneWidget);
    });

    testWidgets('shows P/L, marked "after fees" when there is a fee',
        (tester) async {
      final h = _h(broker: 'ACME', fee: 0.01);
      await pump(tester, h);
      expect(find.text('P/L'), findsOneWidget);
      expect(find.text(moneyK(h.profitLossK(_market.asOf))), findsOneWidget);
      expect(find.text('after fees'), findsOneWidget);
    });

    testWidgets('shows P/L without "after fees" when there is no fee',
        (tester) async {
      await pump(tester, _h());
      expect(find.text('P/L'), findsOneWidget);
      expect(find.text('after fees'), findsNothing);
    });

    testWidgets('shows nothing about brokers when none was entered',
        (tester) async {
      await pump(tester, _h());
      expect(find.text('Broker'), findsNothing);
      expect(find.text('Broker fee'), findsNothing);
    });
  });

  group('form', () {
    Future<Holding?> fill(WidgetTester tester,
        {Holding? initial, String? broker, String? fee}) async {
      tester.view.physicalSize = const Size(1000, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      Holding? saved;
      await tester.pumpWidget(MaterialApp(
          home: Builder(
              builder: (context) => TextButton(
                  onPressed: () async {
                    saved = await Navigator.of(context).push<Holding>(
                        MaterialPageRoute(
                            builder: (_) => HoldingForm(initial: initial)));
                  },
                  child: const Text('open')))));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      if (initial == null) {
        await tester.enterText(
            find.widgetWithText(TextFormField, 'Issuer'), 'TESTCO');
        await tester.enterText(
            find.widgetWithText(TextFormField, 'Strike'), '100');
        await tester.enterText(
            find.widgetWithText(TextFormField, 'Cap %'), '20');
      }
      if (broker != null) {
        await tester.enterText(
            find.widgetWithText(TextFormField, 'Broker'), broker);
      }
      if (fee != null) {
        await tester.enterText(
            find.widgetWithText(TextFormField, 'Annual fee %'), fee);
      }
      await tester.tap(find.text('SAVE'));
      await tester.pumpAndSettle();
      return saved;
    }

    testWidgets('saves the broker and the fee as a fraction', (tester) async {
      final h = await fill(tester, broker: ' ACME ', fee: '1.25');
      expect(h, isNotNull);
      expect(h!.broker, 'ACME');
      expect(h.brokerFee, closeTo(0.0125, 1e-12));
    });

    testWidgets('leaving them alone saves no broker and no fee',
        (tester) async {
      final h = await fill(tester);
      expect(h!.broker, '');
      expect(h.brokerFee, 0.0);
    });

    testWidgets('a negative fee is stopped with a message', (tester) async {
      final h = await fill(tester, fee: '-1');
      expect(h, isNull); // the form stayed open
      expect(find.text('Must be ≥ 0'), findsOneWidget);
    });

    testWidgets('editing keeps the broker and fee already entered',
        (tester) async {
      final h = await fill(tester, initial: _h(broker: 'ACME', fee: 0.01));
      expect(h!.broker, 'ACME');
      expect(h.brokerFee, closeTo(0.01, 1e-12));
    });
  });

  group('P/L', () {
    // _h: initial 100, realized 20, SPX 105 vs strike 100 → +5% on 120 = 6.0
    test('0.6% on \$100,000 for 2 years is \$1,200', () {
      final h = _h(fee: 0.006, initial: 100, realized: 0);
      expect(h.brokerFeesToDateK(DateTime(2028, 1, 1)), closeTo(1.2, 1e-12));
      expect(moneyK(h.brokerFeesToDateK(DateTime(2028, 1, 1))), r'$1,200');
    });

    test('a full year is the whole rate; the year in progress is by days',
        () {
      final h = _h(fee: 0.01); // 1.2 a year on 120
      // 1 full year, then 2027-01-01 to 2027-07-01 = 181 of 365 days.
      expect(h.brokerFeesToDateK(DateTime(2027, 7, 1)),
          closeTo(1.2 + 1.2 * 181 / 365, 1e-12));
    });

    test('each year is charged on the balance when that year began', () {
      // Realized is 20 today: 8 credited on 2027-01-01, 12 on 2028-01-01.
      ResetEvent ev(DateTime d, double added, String key) => ResetEvent(
          holdingKey: key,
          label: 'x',
          date: d,
          isIncomeNote: false,
          periodReturn: 0,
          realizedAddedK: added,
          realizedAfterK: 0);
      final h = _h(fee: 0.006); // initial 100, realized 20
      final history = [
        ev(DateTime(2027, 1, 1), 8, h.key),
        ev(DateTime(2028, 1, 1), 12, h.key),
        ev(DateTime(2027, 1, 1), 999, 'another holding'), // ignored
      ];
      // Year 1 on 100, year 2 on 108 (the 2027-01-01 credit counts that day),
      // year 3 on 120.
      expect(h.brokerFeesToDateK(DateTime(2029, 1, 1), history),
          closeTo(0.006 * (100 + 108 + 120), 1e-12));
      // P/L uses the same fees.
      expect(h.profitLossK(DateTime(2029, 1, 1), history),
          closeTo(20 + h.projGainDollarsK - 0.006 * 328, 1e-12));
      // Over the term, later years use today's balance: + 2029 on 120.
      expect(h.brokerFeeTermK(history),
          closeTo(0.006 * (100 + 108 + 120 + 120), 1e-12));
      // Without the history every year uses today's balance.
      expect(h.brokerFeesToDateK(DateTime(2029, 1, 1)),
          closeTo(0.006 * 360, 1e-12));
    });

    test('a start on Feb 29 has its anniversaries on Feb 28', () {
      final h = Holding.fromJson({
        ..._h(fee: 0.01, realized: 0).toJson(),
        'openDate': DateTime(2024, 2, 29).toIso8601String(),
      });
      // 2024-02-29 → 2025-02-28 is one full year, then 1 day into year two
      // (2025-02-28 → 2026-02-28, 365 days).
      expect(h.brokerFeesToDateK(DateTime(2025, 3, 1)),
          closeTo(1.0 + 1.0 / 365, 1e-12));
    });

    test('no fees before the start; fees stop at maturity', () {
      final h = _h(fee: 0.01);
      expect(h.brokerFeesToDateK(DateTime(2025, 6, 1)), 0);
      expect(h.brokerFeesToDateK(DateTime(2035, 1, 1)),
          closeTo(h.brokerFeeTermK(), 1e-12));
    });

    test('P/L is realized + unrealized − fees so far', () {
      final h = _h(fee: 0.01);
      final asOf = DateTime(2028, 1, 1);
      expect(h.projGainDollarsK, closeTo(6.0, 1e-9));
      expect(h.profitLossK(asOf), closeTo(20 + 6.0 - 2.4, 1e-9)); // 2 years
    });

    test('with no fee, P/L is realized + unrealized', () {
      expect(_h().profitLossK(DateTime(2028, 1, 1)), closeTo(26.0, 1e-9));
    });

    test('group and total P/L add up the holdings', () {
      final hs = [_h(fee: 0.01), _h()];
      final asOf = DateTime(2028, 1, 1);
      expect(BandAggregates.of(hs, asOf: asOf).profitLoss,
          closeTo(hs[0].profitLossK(asOf) + hs[1].profitLossK(asOf), 1e-9));
      expect(BandAggregates.of(hs).profitLoss, 0); // no date, no P/L
    });

    final cs = ColorScheme.fromSeed(seedColor: Colors.blue);

    test('P/L sits after Unrealized \$, at the position the store expects', () {
      final labels = PortfolioTable.columnLabels(cs);
      expect(labels.indexOf('P/L'), PortfolioStore.plColumn);
      expect(labels[PortfolioStore.plColumn - 1], 'Unrealized \$');
      // The default sort is still Index Gain, as before P/L was added.
      expect(labels[PortfolioStore.defaultSortColumn], 'Index Gain');
    });

    // Column order before P/L was added (saved sort settings use these).
    const oldLabels = [
      'Issuer', 'Type', 'Index', 'Protection', 'Initial', 'Realized',
      'Unrealized \$', 'Total Value', 'Return %', 'Unrealized %',
      'Index Gain', 'Yield', 'Next Reset', 'Days to Reset',
    ];
    for (final (old, name) in oldLabels.indexed) {
      test('a sort saved by an older version on "$name" still sorts by "$name"',
          () async {
        SharedPreferences.setMockInitialValues({'sortColumn.v1': old});
        final store = PortfolioStore();
        await store.init();
        expect(PortfolioTable.columnLabels(cs)[store.sortColumn], name);
      });
    }

    test('a new sort is saved under the new setting and wins on reload',
        () async {
      SharedPreferences.setMockInitialValues({'sortColumn.v1': 3});
      final store = PortfolioStore();
      await store.init();
      await store.setSort(PortfolioStore.plColumn, false);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('sortColumn.v2'), PortfolioStore.plColumn);
      expect(prefs.getInt('sortColumn.v1'), 3); // older versions keep theirs
      final again = PortfolioStore();
      await again.init();
      expect(again.sortColumn, PortfolioStore.plColumn);
    });

    test('sorting by P/L orders groups by their P/L subtotal', () async {
      final store = PortfolioStore()
        ..debugSeed([
          _h(issuer: 'A', broker: 'SMALL', realized: 0),
          _h(issuer: 'B', broker: 'BIG', realized: 50),
        ], _market);
      await store.setGroupBy('Broker');
      await store.setSort(PortfolioStore.plColumn, false); // biggest first
      final order = PortfolioTable.orderedHoldings(
              store, _market.asOf, cs)
          .map((h) => h.broker)
          .toList();
      expect(order, ['BIG', 'SMALL']);
    });

    test('Broker, Fee % and Fees to Date are the last three columns', () {
      final labels = PortfolioTable.columnLabels(cs);
      expect(labels.sublist(labels.length - 3),
          ['Broker', 'Fee %', 'Fees to Date']);
    });

    test('grouping by Broker sorts by the Broker column', () {
      expect(
          PortfolioTable.columnLabels(cs)[
              PortfolioTable.columnIndexForDimension('Broker', cs)],
          'Broker');
    });

    test('group and total fees to date add up the holdings', () {
      final hs = [_h(fee: 0.01), _h(fee: 0.02)];
      final asOf = DateTime(2028, 1, 1);
      expect(
          BandAggregates.of(hs, asOf: asOf).feesToDate,
          closeTo(
              hs[0].brokerFeesToDateK(asOf) + hs[1].brokerFeesToDateK(asOf),
              1e-9));
    });

    test('sorting by Fees to Date orders groups by their fee subtotal',
        () async {
      final store = PortfolioStore()
        ..debugSeed([
          _h(issuer: 'A', broker: 'LOW', fee: 0.005),
          _h(issuer: 'B', broker: 'HIGH', fee: 0.02),
        ], _market);
      await store.setGroupBy('Broker');
      await store.setSort(
          PortfolioTable.columnLabels(cs).indexOf('Fees to Date'), false);
      expect(
          PortfolioTable.orderedHoldings(store, _market.asOf, cs)
              .map((h) => h.broker)
              .toList(),
          ['HIGH', 'LOW']);
    });

    for (final full in [true, false]) {
      testWidgets(
          'the ${full ? 'full' : 'compact'} table shows broker, fee and fees '
          'to date, with a fees total', (tester) async {
        tester.view.physicalSize = const Size(3600, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        final hs = [_h(issuer: 'A', broker: 'ACME', fee: 0.01), _h(issuer: 'B')];
        final store = PortfolioStore()..debugSeed(hs, _market);
        await store.setHideSummary(true);
        await store.setFullColumns(full);
        await tester.pumpWidget(ChangeNotifierProvider.value(
            value: store, child: const MaterialApp(home: PortfolioScreen())));
        await tester.pumpAndSettle();
        final fees = moneyK(hs[0].brokerFeesToDateK(_market.asOf));
        expect(find.text('Fees to Date'), findsOneWidget);
        expect(find.text('Fee %'), findsOneWidget);
        expect(find.text('ACME'), findsOneWidget);
        expect(find.text('1.000%'), findsOneWidget);
        expect(find.text(fees), findsNWidgets(2)); // the row and the TOTAL
      });
    }

    testWidgets('the table shows P/L per row and in the TOTAL row',
        (tester) async {
      tester.view.physicalSize = const Size(2400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final hs = [_h(issuer: 'A', fee: 0.01), _h(issuer: 'B')];
      final store = PortfolioStore()..debugSeed(hs, _market);
      await store.setHideSummary(true);
      await tester.pumpWidget(ChangeNotifierProvider.value(
          value: store, child: const MaterialApp(home: PortfolioScreen())));
      await tester.pumpAndSettle();
      final asOf = _market.asOf;
      expect(find.text('P/L'), findsWidgets);
      expect(find.text(moneyK(hs[0].profitLossK(asOf))), findsOneWidget);
      expect(find.text(moneyK(hs[1].profitLossK(asOf))), findsOneWidget);
      expect(
          find.text(moneyK(hs[0].profitLossK(asOf) + hs[1].profitLossK(asOf))),
          findsOneWidget);
    });
  });

  test('payoff engine is unaffected by the fee', () {
    final h = _h(fee: 0.05);
    expect(
        h.projGain,
        payoffReturn(h.indexGain,
            cap: h.cap,
            participation: h.participation,
            floor: h.floor,
            floorType: h.floorType));
  });
}

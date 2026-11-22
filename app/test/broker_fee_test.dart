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
import 'package:ihaveannuities/core/reset_rollover.dart';
import 'package:ihaveannuities/data/market.dart';
import 'package:ihaveannuities/data/portfolio_store.dart';
import 'package:ihaveannuities/data/tracker_xlsx.dart';
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
      final h = _h(fee: 0.01);
      expect(h.termYears, closeTo(4.0, 1e-12));
      expect(h.brokerFeeTermK, closeTo(4.8, 1e-12));
    });

    test('a rolled contract counts the term from its inception date', () {
      // 2022-01-01 to 2030-01-01 = 2922 days = 8.0 years
      final h = _h(fee: 0.01, inception: DateTime(2022, 1, 1));
      expect(h.termYears, closeTo(8.0, 1e-12));
      expect(h.brokerFeeTermK, closeTo(9.6, 1e-12));
    });

    test('maturity on or before the start gives no term fee', () {
      final h = Holding.fromJson({
        ..._h(fee: 0.01).toJson(),
        'maturity': DateTime(2025, 1, 1).toIso8601String(),
      });
      expect(h.termYears, 0);
      expect(h.brokerFeeTermK, 0);
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
      expect(_h().brokerFeeTermK, 0);
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
      expect(headers.sublist(headers.length - 3),
          ['Inception', 'Broker', 'Broker Fee']);
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
      expect(find.text('1.00%/yr'), findsOneWidget);
      expect(find.text('${moneyK(1.2)}/yr · ${moneyK(4.8)} over term'),
          findsOneWidget);
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

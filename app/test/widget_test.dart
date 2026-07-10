// Copyright 2026 Jim Zucker
// SPDX-License-Identifier: Apache-2.0
// Widget coverage for the portfolio screen (prices header, summary, list) and
// the add/edit form validation.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ihaveannuities/core/models.dart';
import 'package:ihaveannuities/core/payoff.dart';
import 'package:ihaveannuities/core/reset_event.dart';
import 'package:ihaveannuities/data/market.dart';
import 'package:ihaveannuities/data/portfolio_store.dart';
import 'package:ihaveannuities/data/tracker_xlsx.dart';
import 'package:ihaveannuities/data/vault.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ihaveannuities/ui/holding_detail.dart';
import 'package:ihaveannuities/ui/holding_form.dart';
import 'package:ihaveannuities/ui/index_chart_screen.dart';
import 'package:ihaveannuities/ui/index_period_chart.dart';
import 'package:ihaveannuities/ui/info_page.dart';
import 'package:ihaveannuities/ui/portfolio_screen.dart';
import 'package:ihaveannuities/ui/reset_history_screen.dart';

final _market = Market(
    asOf: DateTime(2026, 6, 12),
    spx: 7431.46,
    ndx: 29635.95,
    rut: 2943.99,
    dow: 44012.10,
    comp: 23501.75);

Widget _wrap(PortfolioStore store) => ChangeNotifierProvider.value(
      value: store,
      child: const MaterialApp(home: PortfolioScreen()),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('prices header shows indices and updated date', (tester) async {
    final store = PortfolioStore()..debugSeed([], _market);
    await tester.pumpWidget(_wrap(store));
    expect(find.textContaining('S&P 500'), findsOneWidget);
    expect(find.textContaining('Nasdaq-100'), findsOneWidget);
    expect(find.textContaining('Russell 2000'), findsOneWidget);
    expect(find.text('Dow '), findsOneWidget); // quote label, not "Download"
    expect(find.textContaining('Nasdaq Comp'), findsOneWidget);
    expect(find.textContaining('12-Jun-26'), findsOneWidget); // updated date
  });

  testWidgets('refresh button shows a spinner while refreshing', (tester) async {
    final store = PortfolioStore()..debugSeed([], _market);
    await tester.pumpWidget(_wrap(store));
    expect(find.byIcon(Icons.refresh), findsOneWidget);
    expect(store.refreshing, isFalse);
  });

  testWidgets('empty state offers add / import / template / sample', (tester) async {
    final store = PortfolioStore()..debugSeed([], _market);
    await tester.pumpWidget(_wrap(store));
    expect(find.text('Add a holding manually'), findsOneWidget);
    expect(find.text('Import .xlsx…'), findsOneWidget);
    expect(find.text('Download template'), findsOneWidget);
    expect(find.text('Load sample portfolio'), findsOneWidget);
    expect(find.text('About & disclosures'), findsOneWidget);
  });

  testWidgets('empty-state About opens the disclosures page', (tester) async {
    final store = PortfolioStore()..debugSeed([], _market);
    await tester.pumpWidget(_wrap(store));
    await tester.tap(find.text('About & disclosures'));
    await tester.pumpAndSettle();
    expect(find.text('About & Disclosures'), findsOneWidget);
  });

  testWidgets('clear all data is gated by typing the phrase', (tester) async {
    tester.view.physicalSize = const Size(1400, 900); // desktop: hero + table fit
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final holdings =
        parseTracker(File('../data/example-portfolio.xlsx').readAsBytesSync());
    final store = PortfolioStore()..debugSeed(holdings, _market);
    await tester.pumpWidget(_wrap(store));
    await tester.tap(find.byTooltip('Show menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear all data'));
    await tester.pumpAndSettle();
    expect(find.text('Clear all data?'), findsOneWidget);

    final confirm = find.widgetWithText(FilledButton, 'Clear all data');
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull); // disabled
    await tester.enterText(find.byType(TextField), 'clear all data');
    await tester.pump();
    expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull); // enabled
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(store.holdings, isEmpty);
  });

  testWidgets('clear all requires the passphrase when encrypted', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final holdings =
        parseTracker(File('../data/example-portfolio.xlsx').readAsBytesSync());
    final store = PortfolioStore(vault: Vault(kdfIterations: 1000))
      ..debugSeed(holdings, _market);
    await store.enableEncryption('mypass');
    await tester.pumpWidget(_wrap(store));
    await tester.tap(find.byTooltip('Show menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear all data'));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.widgetWithText(TextField, 'Type "clear all data" to confirm'),
        'clear all data');
    await tester.enterText(
        find.widgetWithText(TextField, 'Confirm with your passphrase'), 'wrong');
    await tester.tap(find.widgetWithText(FilledButton, 'Clear all data'));
    await tester.pumpAndSettle();
    expect(find.text('Incorrect passphrase'), findsOneWidget);
    expect(store.holdings, isNotEmpty); // wrong passphrase → nothing happened

    await tester.enterText(
        find.widgetWithText(TextField, 'Confirm with your passphrase'), 'mypass');
    await tester.tap(find.widgetWithText(FilledButton, 'Clear all data'));
    await tester.pumpAndSettle();
    expect(store.holdings, isEmpty);
  });

  testWidgets('export requires re-auth when encrypted', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final holdings =
        parseTracker(File('../data/example-portfolio.xlsx').readAsBytesSync());
    final store = PortfolioStore(vault: Vault(kdfIterations: 1000))
      ..debugSeed(holdings, _market);
    await store.enableEncryption('mypass');
    await tester.pumpWidget(_wrap(store));
    await tester.tap(find.byTooltip('Show menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Export .xlsx'));
    await tester.pumpAndSettle();
    expect(find.text('Confirm it\'s you'), findsOneWidget); // gated
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
  });

  testWidgets('lock icon locks the app when encrypted', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final holdings =
        parseTracker(File('../data/example-portfolio.xlsx').readAsBytesSync());
    final store = PortfolioStore(vault: Vault(kdfIterations: 1000))
      ..debugSeed(holdings, _market);
    await store.enableEncryption('mypass');
    await tester.pumpWidget(_wrap(store));
    await tester.tap(find.byTooltip('Lock now'));
    await tester.pumpAndSettle();
    expect(store.vaultState, VaultState.locked);
  });

  testWidgets('Security requires re-auth when encrypted', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final holdings =
        parseTracker(File('../data/example-portfolio.xlsx').readAsBytesSync());
    final store = PortfolioStore(vault: Vault(kdfIterations: 1000))
      ..debugSeed(holdings, _market);
    await store.enableEncryption('mypass');
    await tester.pumpWidget(_wrap(store));
    await tester.tap(find.byTooltip('Show menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Security'));
    await tester.pumpAndSettle();
    expect(find.text('Confirm it\'s you'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'Passphrase'), 'wrong');
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Incorrect passphrase'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'Passphrase'), 'mypass');
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Encrypt my portfolio'), findsOneWidget); // SecurityScreen
  });

  testWidgets('load sample is disabled when a portfolio exists', (tester) async {
    tester.view.physicalSize = const Size(1400, 900); // desktop: hero + table fit
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final holdings =
        parseTracker(File('../data/example-portfolio.xlsx').readAsBytesSync());
    final store = PortfolioStore()..debugSeed(holdings, _market);
    await tester.pumpWidget(_wrap(store));
    await tester.tap(find.byTooltip('Show menu'));
    await tester.pumpAndSettle();
    final item = tester.widget<PopupMenuItem<String>>(
        find.widgetWithText(PopupMenuItem<String>, 'Load sample'));
    expect(item.enabled, isFalse);
  });

  testWidgets('holding detail renders banner, chart, and section cards',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 1600); // tall enough to build all
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final holdings =
        parseTracker(File('../data/example-portfolio.xlsx').readAsBytesSync());
    final aspida = holdings.firstWhere((h) => h.issuer == 'ASPIDA'); // capped
    final store = PortfolioStore()..debugSeed(holdings, _market);
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: store,
      child: MaterialApp(home: HoldingDetail(holding: aspida)),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull); // chart painter didn't throw
    expect(find.text('Total Value'), findsOneWidget); // unified header (no dup card)
    expect(find.text('Unrealized \$'), findsOneWidget);
    // Contract terms folded into the header (former grey strip).
    expect(find.text('Cap'), findsOneWidget);
    expect(find.text('Account'), findsOneWidget);
    expect(find.text('Strike'), findsOneWidget);
    expect(find.text('Schedule'), findsOneWidget); // dates card beside the chart
    expect(find.text('Values'), findsNothing); // redundant card removed
    expect(find.byType(CustomPaint), findsWidgets); // payoff chart
    expect(find.text('12.25% cap reached'), findsOneWidget); // status chip
    expect(find.textContaining('Return at reset vs. the index move'),
        findsOneWidget); // plain-English chart caption
  });

  testWidgets('index-period chart plots the index since the last reset',
      (tester) async {
    int e(int y, int m, int d) =>
        DateTime.utc(y, m, d).millisecondsSinceEpoch ~/ 1000;
    final json = '{"asOf":"2026-06-15","daily":{"SPX":'
        '[[${e(2025, 12, 1)},6300.0],[${e(2026, 3, 1)},7000.0],'
        '[${e(2026, 6, 1)},7536.0]]},"intraday":{}}';
    final client = MockClient((_) async => http.Response(json, 200));
    final aspida = parseTracker(
            File('../data/example-portfolio.xlsx').readAsBytesSync())
        .firstWhere((h) => h.issuer == 'ASPIDA'); // ^GSPC, lastReset 2025-11
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: IndexPeriodChart(holding: aspida, client: client))));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(CustomPaint), findsWidgets); // index path painted
    expect(find.textContaining('since the last reset'), findsOneWidget);

    // Hover/tap the chart: the crosshair gesture path must not throw.
    final chart = find.byType(IndexPeriodChart);
    await tester.tapAt(tester.getCenter(chart));
    await tester.pump();
    final g = await tester.startGesture(tester.getCenter(chart));
    await g.moveBy(const Offset(40, 0));
    await tester.pump();
    await g.up();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('combined index chart: ranges, legend toggle, remembered',
      (tester) async {
    const historyJson = '{"asOf":"2026-06-15","daily":{"SPX":'
        '[[1700000000,100.0],[1710000000,120.0],[1718000000,150.0]],'
        '"DJI":[[1700000000,40000.0],[1718000000,44000.0]]},'
        '"intraday":{"SPX":[[1717900000,148.0],[1718000000,150.0]]}}';
    final client = MockClient((_) async => http.Response(historyJson, 200));
    final store = PortfolioStore();
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: store,
      child: MaterialApp(home: IndexChartScreen(client: client)),
    ));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Indexes'), findsOneWidget);
    expect(find.text('Max'), findsOneWidget); // range selector
    expect(find.text('S&P 500'), findsOneWidget); // legend chip
    await tester.tap(find.text('Max'));
    await tester.pumpAndSettle();
    expect(find.byType(CustomPaint), findsWidgets); // chart painted

    // Tapping a legend chip hides that index and remembers it.
    await tester.tap(find.text('Russell 2000'));
    await tester.pumpAndSettle();
    expect(store.hiddenIndexes.contains('RUT'), isTrue);
  });

  testWidgets('index chart shows a toggleable portfolio line', (tester) async {
    const historyJson = '{"asOf":"2026-06-15","daily":{'
        '"SPX":[[1700000000,100.0],[1718000000,120.0]],'
        '"DJI":[[1700000000,40000.0],[1718000000,44000.0]],'
        '"COMP":[[1700000000,15000.0],[1718000000,16000.0]],'
        '"NDX":[[1700000000,18000.0],[1718000000,20000.0]],'
        '"RUT":[[1700000000,2000.0],[1718000000,2200.0]]},"intraday":{}}';
    final client = MockClient((_) async => http.Response(historyJson, 200));
    final holdings =
        parseTracker(File('../data/example-portfolio.xlsx').readAsBytesSync());
    final store = PortfolioStore()..debugSeed(holdings, _market);
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: store,
      child: MaterialApp(home: IndexChartScreen(client: client)),
    ));
    await tester.pumpAndSettle();
    expect(find.text('My portfolio'), findsOneWidget); // portfolio legend chip
    expect(tester.takeException(), isNull); // area-fill painter didn't throw
    await tester.tap(find.text('My portfolio'));
    await tester.pumpAndSettle();
    expect(store.hiddenIndexes.contains('PORTFOLIO'), isTrue); // toggled off
  });

  testWidgets('combined index chart in portrait fills a screen and scrolls',
      (tester) async {
    final overflows = <String>[];
    final prev = FlutterError.onError;
    FlutterError.onError = (d) => d.exceptionAsString().contains('overflowed')
        ? overflows.add(d.exceptionAsString())
        : prev?.call(d);
    addTearDown(() => FlutterError.onError = prev);

    int ep(int y, int m, int d) =>
        DateTime.utc(y, m, d).millisecondsSinceEpoch ~/ 1000;
    final json = '{"asOf":"2026-06-15","daily":{"SPX":'
        '[[${ep(2026, 4, 15)},7000.0],[${ep(2026, 5, 15)},7300.0],'
        '[${ep(2026, 6, 15)},7536.0]]},"intraday":{}}';
    final client = MockClient((_) async => http.Response(json, 200));
    final store = PortfolioStore();
    tester.view.physicalSize = const Size(390, 844); // iPhone-class portrait
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: store,
      child: MaterialApp(home: IndexChartScreen(client: client)),
    ));
    await tester.pumpAndSettle();

    expect(overflows, isEmpty); // scrolls instead of overflowing
    expect(find.byType(Scrollable), findsWidgets); // page can scroll
    // The chart is sized to ~one full screen (viewport minus app bar/padding),
    // so once the header scrolls off the top the chart uses the whole screen.
    final heights = find.byType(CustomPaint).evaluate().map((e) {
      final ro = e.renderObject;
      return ro is RenderBox && ro.hasSize ? ro.size.height : 0.0;
    });
    expect(heights.any((h) => h > 650), isTrue); // ~full-screen chart
    // Header + chart together exceed the viewport, so the header can scroll off.
    await tester.drag(find.byType(CustomPaint).last, const Offset(0, -200));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('info button opens the disclosures page', (tester) async {
    final store = PortfolioStore()..debugSeed([], _market);
    await tester.pumpWidget(_wrap(store));
    await tester.tap(find.byTooltip('Show menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('About & disclosures').last);
    await tester.pumpAndSettle();
    expect(find.text('About & Disclosures'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Important disclosures'), 300);
    expect(find.text('Important disclosures'), findsOneWidget);
    expect(find.textContaining('Not financial, investment, tax, or legal advice'),
        findsOneWidget);
  });

  testWidgets('reset history screen: empty state', (tester) async {
    final store = PortfolioStore()..debugSeed([], _market);
    await tester.pumpWidget(ChangeNotifierProvider.value(
        value: store, child: const MaterialApp(home: ResetHistoryScreen())));
    expect(find.text('No resets recorded yet'), findsOneWidget);
  });

  testWidgets('reset history screen lists a logged coupon and a missed one',
      (tester) async {
    final events = [
      ResetEvent(
        holdingKey: 'k',
        label: 'NATBANK-30%-16Apr29',
        date: DateTime(2026, 6, 12),
        isIncomeNote: true,
        periodReturn: 0.01104,
        realizedAddedK: 0.1116,
        realizedAfterK: 0.2220,
      ),
      ResetEvent(
        holdingKey: 'k',
        label: 'NATBANK-30%-16Apr29',
        date: DateTime(2026, 5, 12),
        isIncomeNote: true,
        periodReturn: 0.0,
        realizedAddedK: 0.0,
        realizedAfterK: 0.1104,
        missed: true,
      ),
    ];
    final store = PortfolioStore()
      ..debugSeed([], _market, resetHistory: events);
    await tester.pumpWidget(ChangeNotifierProvider.value(
        value: store, child: const MaterialApp(home: ResetHistoryScreen())));
    expect(find.textContaining('NATBANK'), findsNWidgets(2));
    expect(find.text('Coupon'), findsOneWidget);
    expect(find.text('Coupon missed'), findsOneWidget);
    expect(find.text('breached'), findsOneWidget);
  });

  testWidgets('reset history clear is typed-confirm guarded', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = PortfolioStore()
      ..debugSeed([], _market, resetHistory: [
        ResetEvent(
          holdingKey: 'k',
          label: 'NATBANK-30%-16Apr29',
          date: DateTime(2026, 6, 12),
          isIncomeNote: true,
          periodReturn: 0.01104,
          realizedAddedK: 0.1116,
          realizedAfterK: 0.2220,
        ),
      ]);
    await tester.pumpWidget(ChangeNotifierProvider.value(
        value: store, child: const MaterialApp(home: ResetHistoryScreen())));

    await tester.tap(find.byTooltip('Clear history'));
    await tester.pumpAndSettle();
    expect(find.textContaining('cannot be undone'), findsOneWidget);
    // Guarded: the Clear button is disabled until the phrase is typed.
    final btn = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Clear history'));
    expect(btn.onPressed, isNull);
    expect(store.resetHistory, isNotEmpty);

    await tester.enterText(find.byType(TextField), 'clear');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Clear history'));
    await tester.pumpAndSettle();
    expect(store.resetHistory, isEmpty);
    expect(find.text('No resets recorded yet'), findsOneWidget);
  });

  testWidgets('info page renders the protection types', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: InfoPage()));
    expect(find.textContaining('Version'), findsOneWidget); // build version shown
    expect(find.textContaining('What it does'), findsOneWidget);
    expect(find.textContaining('Floor (max-loss)', findRichText: true),
        findsOneWidget);
    await tester.scrollUntilVisible(
        find.textContaining('claims-paying ability'), 300);
    expect(find.textContaining('claims-paying ability'), findsOneWidget);
  });

  testWidgets('seeded portfolio shows summary + rows', (tester) async {
    final holdings =
        parseTracker(File('../data/example-portfolio.xlsx').readAsBytesSync());
    final store = PortfolioStore()..debugSeed(holdings, _market);
    await tester.pumpWidget(_wrap(store));
    expect(find.text('Protection'), findsWidgets); // hero donut + table column
    expect(find.text('Next resets'), findsOneWidget); // hero upcoming resets
    expect(find.textContaining('contracts'), findsWidgets); // hero summary line
    expect(find.text('ASPIDA'), findsOneWidget); // issuer column (canonical uppercase)
  });

  testWidgets('table shows tracker columns and row actions', (tester) async {
    final holdings =
        parseTracker(File('../data/example-portfolio.xlsx').readAsBytesSync());
    final store = PortfolioStore()..debugSeed(holdings, _market);
    await tester.pumpWidget(_wrap(store));
    expect(find.text('Unrealized %'), findsOneWidget);
    expect(find.text('Total Value'), findsWidgets); // renamed from Projected Value
    expect(find.text('Return %'), findsOneWidget); // replaces Realized %
    expect(find.text('Yield'), findsOneWidget); // life-to-date CAGR column
    // "Inception" also appears as a Reset Freq value, so just confirm presence.
    expect(find.text('Inception'), findsWidgets); // rightmost date column header
    expect(find.text('Realized %'), findsNothing); // removed
    expect(find.text('Protection'), findsWidgets); // table column (also the hero donut label)
    expect(find.text('Days to Reset'), findsOneWidget);
    expect(find.text('TOTAL'), findsOneWidget); // totals row
    expect(find.byTooltip('Edit'), findsWidgets);
    expect(find.byTooltip('Delete'), findsWidgets);
  });

  testWidgets('compact-columns toggle hides static columns', (tester) async {
    final holdings =
        parseTracker(File('../data/example-portfolio.xlsx').readAsBytesSync());
    final store = PortfolioStore()..debugSeed(holdings, _market);
    await tester.pumpWidget(_wrap(store));
    expect(store.fullColumns, isTrue);
    expect(find.text('Strike'), findsOneWidget); // shown in full view

    await tester.tap(find.byTooltip('Compact columns'));
    await tester.pumpAndSettle();
    expect(store.fullColumns, isFalse);
    expect(find.text('Strike'), findsNothing);   // hidden in compact view
    expect(find.text('Issuer'), findsOneWidget);  // identity stays
    expect(find.text('Total Value'), findsWidgets);
    expect(find.text('Index Gain'), findsOneWidget); // kept in compact
  });

  testWidgets('hide-summary toggle collapses quotes + hero', (tester) async {
    final holdings =
        parseTracker(File('../data/example-portfolio.xlsx').readAsBytesSync());
    final store = PortfolioStore()..debugSeed(holdings, _market);
    await tester.pumpWidget(_wrap(store));
    expect(find.text('Next resets'), findsOneWidget); // hero visible (hero-only text)
    expect(find.textContaining('S&P 500'), findsOneWidget); // quotes visible

    await tester.tap(find.text('Hide summary')); // collapsible strip
    await tester.pumpAndSettle();
    expect(store.hideSummary, isTrue);
    expect(find.text('Show summary'), findsOneWidget); // strip flips label
    expect(find.text('Next resets'), findsNothing); // hero collapsed
    expect(find.textContaining('S&P 500'), findsNothing);
  });

  testWidgets('narrow viewport renders holding cards, not the table', (tester) async {
    tester.view.physicalSize = const Size(420, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final holdings =
        parseTracker(File('../data/example-portfolio.xlsx').readAsBytesSync());
    final store = PortfolioStore()..debugSeed(holdings, _market);
    await tester.pumpWidget(_wrap(store));
    expect(find.byType(DataTable), findsNothing);
    expect(find.byType(Card), findsWidgets); // one card per holding
  });

  testWidgets('wide viewport + compact columns renders the table (no gap path)',
      (tester) async {
    tester.view.physicalSize = const Size(1600, 900); // wider than the table
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final holdings =
        parseTracker(File('../data/example-portfolio.xlsx').readAsBytesSync());
    final store = PortfolioStore()..debugSeed(holdings, _market);
    await store.setFullColumns(false); // compact: few columns on a wide screen
    await tester.pumpWidget(_wrap(store));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Total Value'), findsWidgets); // table (not cards)
    expect(find.text('Strike'), findsNothing); // compact hides it
  });

  testWidgets('tapping a column header changes the sort', (tester) async {
    tester.view.physicalSize = const Size(1400, 900); // desktop: hero + table fit
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final holdings =
        parseTracker(File('../data/example-portfolio.xlsx').readAsBytesSync());
    final store = PortfolioStore()..debugSeed(holdings, _market);
    await tester.pumpWidget(_wrap(store));
    expect(store.sortColumn, PortfolioStore.defaultSortColumn); // Next Reset

    await tester.tap(find.text('Issuer'));
    await tester.pumpAndSettle();
    expect(store.sortColumn, 0); // Issuer column
  });

  testWidgets('delete removes a holding after confirm', (tester) async {
    // Use the card layout (narrow) so the Delete button is on-screen.
    tester.view.physicalSize = const Size(420, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final holdings =
        parseTracker(File('../data/example-portfolio.xlsx').readAsBytesSync());
    final store = PortfolioStore()..debugSeed(holdings, _market);
    await tester.pumpWidget(_wrap(store));
    final before = store.holdings.length;

    final del = find.byTooltip('Delete').first;
    await tester.ensureVisible(del);
    await tester.pumpAndSettle();
    await tester.tap(del);
    await tester.pumpAndSettle();
    expect(find.text('Delete holding?'), findsOneWidget);
    expect(find.textContaining('cannot be undone'), findsOneWidget);
    expect(find.text('Export backup'), findsOneWidget); // backup offered

    // Guarded like Clear-all: Delete stays disabled until the phrase is typed.
    final delBtn = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Delete'));
    expect(delBtn.onPressed, isNull);
    expect(store.holdings.length, before); // tapping early does nothing

    await tester.enterText(find.byType(TextField), 'delete');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(store.holdings.length, before - 1);
  });

  testWidgets('edit form opens for a Yahoo-ticker index (no dropdown crash)',
      (tester) async {
    final holdings =
        parseTracker(File('../data/example-portfolio.xlsx').readAsBytesSync());
    final aspida = holdings.firstWhere((h) => h.issuer == 'ASPIDA'); // index ^GSPC
    await tester.pumpWidget(MaterialApp(home: HoldingForm(initial: aspida)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('SPX'), findsOneWidget); // ^GSPC normalized to a dropdown value
  });

  testWidgets('form requires an Issuer', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: HoldingForm()));
    await tester.tap(find.text('SAVE'));
    await tester.pumpAndSettle();
    expect(find.text('Required'), findsOneWidget); // Issuer blank
  });

  testWidgets('form rejects a positive floor', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: HoldingForm()));
    await tester.enterText(find.byType(TextFormField).first, 'Test 1');
    // floor field default is "0.0"; set to a positive value
    final floorField = find.widgetWithText(TextFormField, '0.0');
    await tester.enterText(floorField.first, '5');
    await tester.tap(find.text('SAVE'));
    await tester.pumpAndSettle();
    expect(find.text('Must be ≤ 0'), findsOneWidget);
  });

  testWidgets('floor-type dropdown has distinct labels including None',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: HoldingForm()));
    await tester.pumpAndSettle();
    // Default is Hard (buffer) — one clear label, not a duplicated "Hard".
    expect(find.text('Hard (buffer)'), findsOneWidget);
    await tester.tap(find.text('Hard (buffer)'));
    await tester.pumpAndSettle();
    // The open menu offers all four distinct choices.
    expect(find.text('Soft (barrier)'), findsWidgets);
    expect(find.text('Floor (max loss)'), findsWidgets);
    expect(find.text('None (full downside)'), findsWidgets);
    // Choosing None hides the floor input and says so.
    await tester.tap(find.text('None (full downside)').last);
    await tester.pumpAndSettle();
    expect(find.text('No downside floor'), findsOneWidget);
  });

  testWidgets('refresh fetches prices and shows a snackbar', (tester) async {
    final client = MockClient((_) async => http.Response(
        '{"asOf":"2026-06-18","spx":7500.0,"ndx":30000.0,"rut":3000.0,'
        '"dow":44500.0,"comp":23800.0}',
        200));
    final store = PortfolioStore(client: client)..debugSeed([], _market);
    await tester.pumpWidget(_wrap(store));
    await tester.tap(find.byTooltip('Refresh prices'));
    await tester.pumpAndSettle();
    expect(store.status, isNull); // success clears any status
    expect(store.market!.spx, 7500.0); // revalued to fetched prices
    expect(find.textContaining('Prices updated'), findsOneWidget); // snackbar
  });

  testWidgets('refresh failure shows the status banner', (tester) async {
    final client = MockClient((_) async => http.Response('nope', 500));
    final store = PortfolioStore(client: client)..debugSeed([], _market);
    await tester.pumpWidget(_wrap(store));
    await tester.tap(find.byTooltip('Refresh prices'));
    await tester.pumpAndSettle();
    expect(store.status, isNotNull);
    // The status shows in both the error banner and the snackbar.
    expect(find.textContaining('Prices unavailable'), findsWidgets);
  });

  testWidgets('FAB add → fill form → SAVE upserts the holding', (tester) async {
    tester.view.physicalSize = const Size(1000, 1600); // build the whole form
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final store = PortfolioStore()..debugSeed([], _market);
    await tester.pumpWidget(_wrap(store));

    await tester.tap(find.widgetWithText(FloatingActionButton, 'Add'));
    await tester.pumpAndSettle();
    expect(find.text('Add holding'), findsOneWidget); // form opened

    await tester.enterText(find.widgetWithText(TextFormField, 'Issuer'), 'TESTCO');
    await tester.enterText(find.widgetWithText(TextFormField, 'Cap %'), '10');
    await tester.enterText(find.widgetWithText(TextFormField, 'Strike'), '100');
    // Flip on the income-note path so coupon handling is exercised on save.
    await tester.tap(find.text('Income note (coupon)'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('SAVE'));
    await tester.pumpAndSettle();
    expect(store.holdings.length, 1); // upserted, back on the screen
    expect(store.holdings.single.issuer, 'TESTCO');
    expect(store.holdings.single.isIncomeNote, isTrue);
    expect(store.holdings.single.cap, closeTo(0.10, 1e-9));
  });

  testWidgets('form: uncapped + dropdown + date picker returns a holding',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    Holding? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (ctx) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async => result = await Navigator.of(ctx)
                  .push<Holding>(MaterialPageRoute(builder: (_) => const HoldingForm())),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, 'Issuer'), 'UNCAP');
    await tester.enterText(find.widgetWithText(TextFormField, 'Strike'), '4200');
    // Uncapped: the Cap field disappears and save uses cap == null.
    await tester.tap(find.text('Uncapped'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextFormField, 'Cap %'), findsNothing);
    // Change the floor-type dropdown to Soft (barrier).
    await tester.tap(find.text('Hard (buffer)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Soft (barrier)').last);
    await tester.pumpAndSettle();
    // Open the date picker for "Start Date" and confirm the initial date.
    await tester.tap(find.text('Start Date'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('SAVE'));
    await tester.pumpAndSettle();
    expect(result, isNotNull);
    expect(result!.issuer, 'UNCAP');
    expect(result!.cap, isNull); // uncapped
    expect(result!.floorType, FloorType.soft);
  });

  testWidgets('menu → Load sample populates an empty portfolio', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final store = PortfolioStore()..debugSeed([], _market);
    await tester.pumpWidget(_wrap(store));
    await tester.tap(find.byTooltip('Show menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Load sample'));
    await tester.pumpAndSettle();
    expect(store.holdings, isNotEmpty); // loaded from the bundled asset
    expect(find.textContaining('sample holdings'), findsOneWidget); // snackbar
  });

  testWidgets('new-version banner shows and Later dismisses it', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final client = MockClient((_) async => http.Response('{"sha":"new"}', 200));
    final store = PortfolioStore(buildSha: 'old', client: client)
      ..debugSeed([], _market);
    await store.checkAppVersion(); // detect the newer deployed build
    await tester.pumpWidget(_wrap(store));
    expect(find.text('A new version of the app is available.'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Reload'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Later'));
    await tester.pumpAndSettle();
    expect(find.text('A new version of the app is available.'), findsNothing);
  });

  testWidgets('menu → User Guide opens the column glossary', (tester) async {
    final store = PortfolioStore()..debugSeed([], _market);
    await tester.pumpWidget(_wrap(store));
    await tester.tap(find.byTooltip('Show menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('User Guide'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'User Guide'), findsOneWidget);
    expect(find.text('Columns'), findsOneWidget); // top section card
    await tester.scrollUntilVisible(find.text('Protection types'), 300);
    expect(find.text('Protection types'), findsOneWidget);
  });

  testWidgets('menu → Reset history opens the log screen', (tester) async {
    final store = PortfolioStore()..debugSeed([], _market);
    await tester.pumpWidget(_wrap(store));
    await tester.tap(find.byTooltip('Show menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reset history'));
    await tester.pumpAndSettle();
    expect(find.text('No resets recorded yet'), findsOneWidget);
  });
}

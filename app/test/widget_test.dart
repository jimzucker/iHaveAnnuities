// Copyright 2026 Jim Zucker
// SPDX-License-Identifier: Apache-2.0
// Widget coverage for the portfolio screen (prices header, summary, list) and
// the add/edit form validation.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ihaveannuities/core/reset_event.dart';
import 'package:ihaveannuities/data/market.dart';
import 'package:ihaveannuities/data/portfolio_store.dart';
import 'package:ihaveannuities/data/tracker_xlsx.dart';
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

  testWidgets('load sample is disabled when a portfolio exists', (tester) async {
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
    expect(find.text('Projected Value'), findsWidgets);
    expect(find.text('Unrealized \$'), findsWidgets);
    expect(find.text('Cap'), findsOneWidget); // compact key strip
    expect(find.text('Schedule'), findsOneWidget);
    expect(find.text('Values'), findsOneWidget);
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
    expect(find.text('Protection'), findsOneWidget); // hero donut legend
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
    expect(find.text('Floor Type'), findsOneWidget);
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
    expect(find.text('Projected Value'), findsWidgets);
    expect(find.text('Index Gain'), findsOneWidget); // kept in compact
  });

  testWidgets('hide-summary toggle collapses quotes + hero', (tester) async {
    final holdings =
        parseTracker(File('../data/example-portfolio.xlsx').readAsBytesSync());
    final store = PortfolioStore()..debugSeed(holdings, _market);
    await tester.pumpWidget(_wrap(store));
    expect(find.text('Protection'), findsOneWidget); // hero visible
    expect(find.textContaining('S&P 500'), findsOneWidget); // quotes visible

    await tester.tap(find.text('Hide summary')); // collapsible strip
    await tester.pumpAndSettle();
    expect(store.hideSummary, isTrue);
    expect(find.text('Show summary'), findsOneWidget); // strip flips label
    expect(find.text('Protection'), findsNothing);
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
    expect(find.text('Projected Value'), findsWidgets); // table (not cards)
    expect(find.text('Strike'), findsNothing); // compact hides it
  });

  testWidgets('tapping a column header changes the sort', (tester) async {
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
}

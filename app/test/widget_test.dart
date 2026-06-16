// Copyright 2026 Jim Zucker
// SPDX-License-Identifier: Apache-2.0
// Widget coverage for the portfolio screen (prices header, summary, list) and
// the add/edit form validation.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ihaveannuities/data/market.dart';
import 'package:ihaveannuities/data/portfolio_store.dart';
import 'package:ihaveannuities/data/tracker_xlsx.dart';
import 'package:ihaveannuities/ui/holding_form.dart';
import 'package:ihaveannuities/ui/info_page.dart';
import 'package:ihaveannuities/ui/portfolio_screen.dart';

final _market = Market(
    asOf: DateTime(2026, 6, 12), spx: 7431.46, ndx: 29635.95, rut: 2943.99);

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
    expect(find.textContaining('Updated 12-Jun-26'), findsOneWidget);
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

  testWidgets('info page renders the protection types', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: InfoPage()));
    expect(find.textContaining('What it does'), findsOneWidget);
    expect(find.textContaining('Protected (0% floor)', findRichText: true),
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
    expect(find.text('Contracts'), findsOneWidget);
    expect(find.text('Principal'), findsOneWidget);
    expect(find.text('${holdings.length}'), findsWidgets);
    expect(find.text('ASPIDA'), findsOneWidget); // issuer column (canonical uppercase)
  });

  testWidgets('table shows tracker columns and row actions', (tester) async {
    final holdings =
        parseTracker(File('../data/example-portfolio.xlsx').readAsBytesSync());
    final store = PortfolioStore()..debugSeed(holdings, _market);
    await tester.pumpWidget(_wrap(store));
    expect(find.text('Proj Gain @ Reset'), findsOneWidget);
    expect(find.text('Floor Type'), findsOneWidget);
    expect(find.text('Days to Reset'), findsOneWidget);
    expect(find.byTooltip('Edit'), findsWidgets);
    expect(find.byTooltip('Delete'), findsWidgets);
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

    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(store.holdings.length, before - 1);
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

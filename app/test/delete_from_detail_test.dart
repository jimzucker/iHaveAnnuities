// Copyright 2026 Jim Zucker
// SPDX-License-Identifier: LicenseRef-Proprietary
// The detail page (where a phone card opens) must offer Delete in its edit
// form, the same as the table's edit button. Synthetic data only.

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

void main() {
  testWidgets('delete from the detail page edit form', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final h = Holding(
      issuer: 'TESTCO', index: 'SPX', account: AccountType.ira, cap: 0.2,
      participation: 1, floor: -0.1, floorType: FloorType.hard, strike: 100,
      currentLevel: 101, openDate: DateTime(2026, 1, 1),
      lastReset: DateTime(2026, 1, 1), maturity: DateTime(2032, 1, 1),
      nextReset: DateTime(2032, 1, 1), resetFreq: ResetFreq.inception,
      initial: 150, realized: 0,
    );
    final store = PortfolioStore(
        client: MockClient((_) async => http.Response('x', 500)))
      ..debugSeed([h], Market(asOf: DateTime(2026, 6, 20), spx: 101, ndx: 1, rut: 1));
    addTearDown(store.dispose);

    // A home page under the detail page, to check we land back on it.
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: store,
      child: MaterialApp(
          home: Builder(
              builder: (ctx) => Scaffold(
                  body: TextButton(
                      onPressed: () => Navigator.of(ctx).push(MaterialPageRoute(
                          builder: (_) =>
                              HoldingDetail(holding: store.holdings.single))),
                      child: const Text('open'))))),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Edit'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Delete holding'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, 'Type "delete" to confirm'), 'delete');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(store.holdings, isEmpty);
    expect(find.text('open'), findsOneWidget); // back on the home page
    expect(find.byType(HoldingDetail), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

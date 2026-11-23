// Copyright 2026 Jim Zucker
// SPDX-License-Identifier: LicenseRef-Proprietary
// A price refresh rebuilds every holding as a new copy. An edit or delete
// started before the refresh must still change the original holding, not add
// a second copy or do nothing. Synthetic data only.

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ihaveannuities/core/models.dart';
import 'package:ihaveannuities/core/payoff.dart';
import 'package:ihaveannuities/data/market.dart';
import 'package:ihaveannuities/data/portfolio_store.dart';

Holding _h(double initial, DateTime maturity) => Holding(
      issuer: 'TESTCO',
      index: 'SPX',
      account: AccountType.ira,
      cap: 0.2,
      participation: 1,
      floor: -0.1,
      floorType: FloorType.hard,
      strike: 6000,
      currentLevel: 6500,
      openDate: DateTime(2026, 1, 1),
      lastReset: DateTime(2026, 1, 1),
      maturity: maturity,
      nextReset: maturity,
      resetFreq: ResetFreq.inception,
      initial: initial,
      realized: 0,
    );

Future<PortfolioStore> _store() async {
  SharedPreferences.setMockInitialValues({});
  const mkt = '{"asOf":"2026-11-20","spx":6600,"ndx":26000,"rut":2400}';
  final store = PortfolioStore(
      client: MockClient((_) async => http.Response(mkt, 200)))
    ..debugSeed([_h(220, DateTime(2032, 1, 1)), _h(150, DateTime(2033, 1, 1))],
        Market(asOf: DateTime(2026, 11, 20), spx: 6500, ndx: 1, rut: 1));
  return store;
}

void main() {
  test('an edit saved after a price refresh replaces the holding', () async {
    final store = await _store();
    final opened = store.holdings[1]; // the edit page holds this copy
    await store.refreshMarket();
    expect(store.holdings[1].currentLevel, 6600); // the refresh happened
    expect(identical(store.holdings[1], opened), isFalse);

    await store.upsert(
        Holding.fromJson({...opened.toJson(), 'initial': 151.0}),
        replacing: opened);
    expect(store.holdings.map((x) => x.initial), [220.0, 151.0]);
  });

  test('a delete after a price refresh removes the right holding', () async {
    final store = await _store();
    final opened = store.holdings[1];
    await store.refreshMarket();
    await store.remove(opened);
    expect(store.holdings.map((x) => x.initial), [220.0]);
  });

  test('a new holding is still added', () async {
    final store = await _store();
    await store.upsert(_h(50, DateTime(2034, 1, 1)));
    expect(store.holdings.length, 3);
  });
}

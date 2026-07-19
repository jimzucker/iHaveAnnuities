// Copyright 2026 Jim Zucker
// SPDX-License-Identifier: LicenseRef-Proprietary
// New-app-version detection: the store flags an update when the deployed
// build-id SHA differs from the running build's SHA, and "Later" suppresses
// re-nagging for that same build.

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ihaveannuities/data/app_version.dart';
import 'package:ihaveannuities/data/market.dart';
import 'package:ihaveannuities/data/portfolio_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _market = Market(
    asOf: DateTime(2026, 6, 12), spx: 7431.46, ndx: 29635.95, rut: 2943.99);

http.Client _shaClient(String sha) =>
    MockClient((_) async => http.Response('{"sha":"$sha"}', 200));

PortfolioStore _store(String running, String deployed) => PortfolioStore(
    buildSha: running, client: _shaClient(deployed))
  ..debugSeed([], _market);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('fetchDeployedSha parses the build-id json', () async {
    expect(await fetchDeployedSha(client: _shaClient('abc123')), 'abc123');
  });

  test('flags a new version when the deployed SHA differs', () async {
    final s = _store('old-sha', 'new-sha');
    expect(s.newVersionAvailable, isFalse);
    await s.checkAppVersion();
    expect(s.newVersionAvailable, isTrue);
  });

  test('does not flag when SHAs match', () async {
    final s = _store('same', 'same');
    await s.checkAppVersion();
    expect(s.newVersionAvailable, isFalse);
  });

  test('dev build never prompts', () async {
    final s = _store('dev', 'whatever');
    await s.checkAppVersion();
    expect(s.newVersionAvailable, isFalse);
  });

  test('a newer deploy re-flags after a prior dismiss', () async {
    var served = 'NEW1';
    final s = PortfolioStore(
        buildSha: 'OLD',
        client: MockClient((_) async => http.Response('{"sha":"$served"}', 200)))
      ..debugSeed([], _market);
    await s.checkAppVersion();
    expect(s.newVersionAvailable, isTrue);
    s.dismissNewVersion();
    expect(s.newVersionAvailable, isFalse);
    // A distinct, even-newer deploy must re-flag (dismissing NEW1 ≠ NEW2).
    served = 'NEW2';
    await s.checkAppVersion();
    expect(s.newVersionAvailable, isTrue);
  });

  test('Later suppresses re-nagging for the same deployed build', () async {
    final s = _store('old', 'new');
    await s.checkAppVersion();
    expect(s.newVersionAvailable, isTrue);
    s.dismissNewVersion();
    expect(s.newVersionAvailable, isFalse);
    await s.checkAppVersion(); // same deployed SHA → stays dismissed
    expect(s.newVersionAvailable, isFalse);
  });
}

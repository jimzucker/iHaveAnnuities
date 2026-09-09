// Copyright 2026 Jim Zucker
// SPDX-License-Identifier: LicenseRef-Proprietary
// Screenshot generator for the README. NOT a CI regression check — tagged
// 'golden' and excluded from the gate (font rendering is platform-specific).
// Regenerate the PNGs with:
//   flutter test --update-goldens --tags golden test/golden_screens_test.dart
//   cp test/goldens/*.png ../docs/screenshots/
@Tags(['golden'])
library;

import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_toolkit/golden_toolkit.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ihaveannuities/data/market.dart';
import 'package:ihaveannuities/data/portfolio_store.dart';
import 'package:ihaveannuities/data/tracker_xlsx.dart';
import 'package:ihaveannuities/ui/holding_detail.dart';
import 'package:ihaveannuities/ui/portfolio_hero.dart';
import 'package:ihaveannuities/ui/portfolio_screen.dart';

final _market = Market(
    asOf: DateTime(2026, 6, 15),
    spx: 7536.24,
    ndx: 30294.06,
    rut: 2975.53,
    dow: 51968.24,
    comp: 26561.77);

ThemeData _theme(Brightness b) => ThemeData(
      colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1F3A5F), brightness: b),
      useMaterial3: true,
    );

// golden_toolkit's own materialAppWrapper builds a package:flutter/material
// MaterialApp, whose Theme and MaterialLocalizations the material_ui widgets
// under test can't see. This is that wrapper, rebuilt from material_ui — same
// platform, locale and Material surface, so the screenshots don't shift.
WidgetWrapper _appWrapper(ThemeData theme) => (child) => MaterialApp(
      supportedLocales: const [Locale('en')],
      theme: theme.copyWith(platform: TargetPlatform.android),
      debugShowCheckedModeBanner: false,
      home: Material(child: child),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  PortfolioStore seeded() {
    final holdings =
        parseTracker(File('../data/example-portfolio.xlsx').readAsBytesSync());
    return PortfolioStore()..debugSeed(holdings, _market);
  }

  testGoldens('overview-app (table + hero, desktop)', (tester) async {
    await loadAppFonts();
    await tester.pumpWidgetBuilder(
      ChangeNotifierProvider.value(value: seeded(), child: const PortfolioScreen()),
      wrapper: _appWrapper(_theme(Brightness.light)),
      surfaceSize: const Size(1320, 720),
    );
    await tester.pumpAndSettle();
    await screenMatchesGolden(tester, 'overview-app');
  });

  testGoldens('overview-compact (compact columns, wide — no gap)', (tester) async {
    await loadAppFonts();
    final store = seeded();
    await store.setFullColumns(false);
    await store.setHideSummary(true);
    await tester.pumpWidgetBuilder(
      ChangeNotifierProvider.value(value: store, child: const PortfolioScreen()),
      wrapper: _appWrapper(_theme(Brightness.light)),
      surfaceSize: const Size(1500, 700),
    );
    await tester.pumpAndSettle();
    await screenMatchesGolden(tester, 'overview-compact');
  });

  testGoldens('hero (portfolio summary card)', (tester) async {
    await loadAppFonts();
    await tester.pumpWidgetBuilder(
      ChangeNotifierProvider.value(
          value: seeded(), child: const Material(child: PortfolioHero())),
      wrapper: _appWrapper(_theme(Brightness.light)),
      surfaceSize: const Size(920, 188),
    );
    await tester.pumpAndSettle();
    await screenMatchesGolden(tester, 'hero');
  });

  testGoldens('drilldown (detail, desktop)', (tester) async {
    await loadAppFonts();
    final store = seeded();
    final h = store.holdings.firstWhere((x) => x.issuer == 'ASPIDA');
    await tester.pumpWidgetBuilder(
      ChangeNotifierProvider.value(
          value: store, child: HoldingDetail(holding: h)),
      wrapper: _appWrapper(_theme(Brightness.dark)),
      surfaceSize: const Size(1100, 820),
    );
    await tester.pumpAndSettle();
    await screenMatchesGolden(tester, 'drilldown');
  });

  testGoldens('phone-cards (narrow)', (tester) async {
    await loadAppFonts();
    final store = seeded();
    await store.setHideSummary(true); // collapse the quotes banner for a clean card shot
    await tester.pumpWidgetBuilder(
      ChangeNotifierProvider.value(value: store, child: const PortfolioScreen()),
      wrapper: _appWrapper(_theme(Brightness.light)),
      surfaceSize: const Size(400, 920),
    );
    await tester.pumpAndSettle();
    await screenMatchesGolden(tester, 'phone-cards');
  });
}

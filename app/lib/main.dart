// Copyright 2026 Jim Zucker
// SPDX-License-Identifier: LicenseRef-Proprietary

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'data/portfolio_store.dart';
import 'ui/onboarding_screen.dart';
import 'ui/portfolio_screen.dart';
import 'ui/unlock_screen.dart';

void main() {
  runApp(const IHaveAnnuitiesApp());
}

class IHaveAnnuitiesApp extends StatelessWidget {
  const IHaveAnnuitiesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => PortfolioStore()..init(),
      child: MaterialApp(
        title: 'iHaveAnnuities',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1F3A5F)),
          useMaterial3: true,
        ),
        darkTheme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF1F3A5F),
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
        ),
        themeMode: ThemeMode.system, // follows the OS light/dark setting
        // Startup gate: splash until storage is read, then unlock (if locked),
        // first-run onboarding (brand-new install), else the portfolio.
        home: Consumer<PortfolioStore>(
          builder: (_, store, _) {
            if (!store.ready) {
              return const Scaffold(body: Center(child: CircularProgressIndicator()));
            }
            if (store.isLocked) return const UnlockScreen();
            if (store.needsOnboarding) return const OnboardingScreen();
            return const PortfolioScreen();
          },
        ),
      ),
    );
  }
}

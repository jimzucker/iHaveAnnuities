// Copyright 2026 Jim Zucker
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'data/portfolio_store.dart';
import 'ui/portfolio_screen.dart';

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
        home: const PortfolioScreen(),
      ),
    );
  }
}

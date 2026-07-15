// Copyright 2026 Jim Zucker
// SPDX-License-Identifier: LicenseRef-Proprietary
// UnlockScreen UI: passphrase unlock (right/wrong) and the recovery flow that
// sets a new passphrase inline (regression: "Set" did nothing when it was a
// dialog on the screen the unlock was tearing down).

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ihaveannuities/core/models.dart';
import 'package:ihaveannuities/core/payoff.dart';
import 'package:ihaveannuities/data/biometric.dart';
import 'package:ihaveannuities/data/market.dart';
import 'package:ihaveannuities/data/portfolio_store.dart';
import 'package:ihaveannuities/data/vault.dart';
import 'package:ihaveannuities/ui/onboarding_screen.dart';
import 'package:ihaveannuities/ui/unlock_screen.dart';

final _market = Market(asOf: DateTime(2026, 6, 12), spx: 7431.46, ndx: 29635.95, rut: 2943.99);

Holding _h(String issuer) => Holding(
      issuer: issuer,
      index: 'SPX',
      account: AccountType.nonQual,
      cap: 0.10,
      participation: 1.0,
      floor: 0.0,
      floorType: FloorType.hard,
      strike: 100,
      currentLevel: 110,
      openDate: DateTime(2025, 1, 1),
      lastReset: DateTime(2025, 1, 1),
      maturity: DateTime(2032, 1, 1),
      nextReset: DateTime(2030, 1, 1),
      resetFreq: ResetFreq.annual,
      initial: 100,
      realized: 0,
    );

class _FakeBio implements BiometricAuthenticator {
  _FakeBio({this.supported = false});
  final bool supported;
  final Uint8List secret = Uint8List.fromList(List.filled(32, 7));
  @override
  Future<bool> isSupported() async => supported;
  @override
  Future<BiometricEnrollment?> enroll() async =>
      supported ? BiometricEnrollment('cred', secret) : null;
  @override
  Future<Uint8List?> authenticate(String credentialId) async =>
      supported ? secret : null;
}

Future<(PortfolioStore, String)> _lockedStore() async {
  final s = PortfolioStore(vault: Vault(kdfIterations: 1000), biometric: _FakeBio())
    ..debugSeed([_h('AAA')], _market);
  final code = await s.enableEncryption('orig');
  await s.lock();
  return (s, code);
}

/// A locked store with biometric enrolled (a supported fake authenticator).
Future<PortfolioStore> _bioLockedStore() async {
  final s = PortfolioStore(
      vault: Vault(kdfIterations: 1000), biometric: _FakeBio(supported: true))
    ..debugSeed([_h('AAA')], _market);
  await s.enableEncryption('orig');
  await s.enableBiometric();
  await s.lock();
  return s;
}

Widget _wrap(PortfolioStore s) => ChangeNotifierProvider.value(
    value: s, child: const MaterialApp(home: UnlockScreen()));

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('onboarding renders the welcome step (no startup crash)',
      (tester) async {
    final store =
        PortfolioStore(vault: Vault(kdfIterations: 1000), biometric: _FakeBio());
    await tester.pumpWidget(ChangeNotifierProvider.value(
        value: store, child: const MaterialApp(home: OnboardingScreen())));
    await tester.pumpAndSettle();
    expect(find.text('Protect your portfolio'), findsOneWidget);
    expect(find.text('Set up encryption'), findsOneWidget);
  });

  testWidgets('wrong passphrase shows an error and stays locked', (tester) async {
    final (s, _) = await _lockedStore();
    await tester.pumpWidget(_wrap(s));
    await tester.enterText(find.byType(TextField), 'nope');
    await tester.tap(find.widgetWithText(FilledButton, 'Unlock'));
    await tester.pumpAndSettle();
    expect(find.text('Incorrect passphrase'), findsOneWidget);
    expect(s.vaultState, VaultState.locked);
  });

  testWidgets('correct passphrase unlocks', (tester) async {
    final (s, _) = await _lockedStore();
    await tester.pumpWidget(_wrap(s));
    await tester.enterText(find.byType(TextField), 'orig');
    await tester.tap(find.widgetWithText(FilledButton, 'Unlock'));
    await tester.pumpAndSettle();
    expect(s.vaultState, VaultState.unlocked);
  });

  testWidgets('biometric unlock via the Touch ID button', (tester) async {
    final s = await _bioLockedStore();
    expect(s.biometricEnabled, isTrue);
    expect(s.vaultState, VaultState.locked);
    await tester.pumpWidget(_wrap(s));
    await tester.tap(find.widgetWithText(OutlinedButton, 'Unlock with Touch ID'));
    await tester.pumpAndSettle();
    expect(s.vaultState, VaultState.unlocked);
    expect(s.holdings.single.issuer, 'AAA');
  });

  testWidgets('recovery sets a new passphrase inline; old one stops working',
      (tester) async {
    final (s, code) = await _lockedStore();
    await tester.pumpWidget(_wrap(s));

    await tester.tap(find.text('Use recovery code'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), code);
    await tester.enterText(find.byType(TextField).at(1), 'fresh-pass');
    await tester.enterText(find.byType(TextField).at(2), 'fresh-pass'); // confirm
    await tester.tap(find.widgetWithText(FilledButton, 'Recover & set passphrase'));
    await tester.pumpAndSettle();

    expect(s.vaultState, VaultState.unlocked);
    expect(s.holdings.single.issuer, 'AAA');
    // The new passphrase works; the original (forgotten) one no longer does.
    await s.lock();
    expect(await s.unlock('orig'), isFalse);
    expect(await s.unlock('fresh-pass'), isTrue);
  });
}

// Copyright 2026 Jim Zucker
// SPDX-License-Identifier: Apache-2.0
// Widget coverage for the security UI: onboarding wizard, Security settings,
// the re-auth gate (passphrase / recovery / Touch ID), and the destructive
// confirm dialog's Touch ID branch.

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
import 'package:ihaveannuities/ui/confirm.dart';
import 'package:ihaveannuities/ui/onboarding_screen.dart';
import 'package:ihaveannuities/ui/reauth.dart';
import 'package:ihaveannuities/ui/security_screen.dart';

final _market =
    Market(asOf: DateTime(2026, 6, 12), spx: 7431.46, ndx: 29635.95, rut: 2943.99);

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

PortfolioStore _fresh({bool bio = false}) =>
    PortfolioStore(vault: Vault(kdfIterations: 1000), biometric: _FakeBio(supported: bio));

Future<(PortfolioStore, String)> _encrypted({bool bio = false}) async {
  final s = _fresh(bio: bio)..debugSeed([_h('AAA')], _market);
  final code = await s.enableEncryption('pass');
  return (s, code);
}

Widget _host(PortfolioStore s, Widget home) =>
    ChangeNotifierProvider.value(value: s, child: MaterialApp(home: home));

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // ---- Onboarding wizard ----------------------------------------------------

  testWidgets('onboarding: full set-up enables encryption', (tester) async {
    final s = _fresh();
    await tester.pumpWidget(_host(s, const OnboardingScreen()));
    await tester.tap(find.text('Set up encryption'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'mypass');
    await tester.enterText(find.byType(TextField).at(1), 'mypass');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Save your recovery code'), findsOneWidget);
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(s.encryptionEnabled, isTrue);
    expect(s.needsOnboarding, isFalse);
  });

  testWidgets('onboarding: skip leaves encryption off', (tester) async {
    final s = _fresh();
    await tester.pumpWidget(_host(s, const OnboardingScreen()));
    await tester.tap(find.text('Skip for now'));
    await tester.pumpAndSettle();
    expect(s.needsOnboarding, isFalse);
    expect(s.encryptionEnabled, isFalse);
  });

  testWidgets('onboarding: passphrase mismatch is rejected', (tester) async {
    final s = _fresh();
    await tester.pumpWidget(_host(s, const OnboardingScreen()));
    await tester.tap(find.text('Set up encryption'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'a');
    await tester.enterText(find.byType(TextField).at(1), 'b');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.textContaining('don\'t match'), findsOneWidget);
    expect(s.encryptionEnabled, isFalse);
  });

  testWidgets('onboarding: biometric step can enroll', (tester) async {
    final s = _fresh(bio: true);
    await tester.pumpWidget(_host(s, const OnboardingScreen()));
    await tester.tap(find.text('Set up encryption'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'p');
    await tester.enterText(find.byType(TextField).at(1), 'p');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Enable Touch ID'), findsOneWidget);
    await tester.tap(find.text('Enable Touch ID'));
    await tester.pumpAndSettle();
    expect(s.biometricEnabled, isTrue);
    expect(s.needsOnboarding, isFalse);
  });

  // ---- Security settings ----------------------------------------------------

  testWidgets('security: change passphrase needs a match, then updates',
      (tester) async {
    final (s, _) = await _encrypted();
    await tester.pumpWidget(_host(s, const SecurityScreen()));
    await tester.tap(find.text('Change passphrase'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'new1');
    await tester.enterText(find.byType(TextField).at(1), 'new2');
    await tester.tap(find.widgetWithText(FilledButton, 'OK'));
    await tester.pumpAndSettle();
    expect(find.textContaining('don\'t match'), findsOneWidget);
    await tester.enterText(find.byType(TextField).at(0), 'newpass');
    await tester.enterText(find.byType(TextField).at(1), 'newpass');
    await tester.tap(find.widgetWithText(FilledButton, 'OK'));
    await tester.pumpAndSettle();
    await s.lock();
    expect(await s.unlock('newpass'), isTrue);
  });

  testWidgets('security: disable encryption is passphrase-gated', (tester) async {
    final (s, _) = await _encrypted();
    await tester.pumpWidget(_host(s, const SecurityScreen()));
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    expect(find.text('Turn off encryption?'), findsOneWidget);
    await tester.enterText(
        find.widgetWithText(TextField, 'Type "disable" to confirm'), 'disable');
    await tester.enterText(
        find.widgetWithText(TextField, 'Confirm with your passphrase'), 'pass');
    await tester.tap(find.widgetWithText(FilledButton, 'Turn off'));
    await tester.pumpAndSettle();
    expect(s.encryptionEnabled, isFalse);
  });

  testWidgets('security: enable biometric + change stay-unlocked days',
      (tester) async {
    final (s, _) = await _encrypted(bio: true);
    await tester.pumpWidget(_host(s, const SecurityScreen()));
    await tester.pumpAndSettle(); // isSupported() future
    await tester.tap(find.text('Unlock with Touch ID / Face ID'));
    await tester.pumpAndSettle();
    expect(s.biometricEnabled, isTrue);
    await tester.tap(find.byType(DropdownButton<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('7 days').last);
    await tester.pumpAndSettle();
    expect(s.stayUnlockedDays, 7);
  });

  testWidgets('security: regenerate recovery code shows a new code',
      (tester) async {
    final (s, _) = await _encrypted();
    await tester.pumpWidget(_host(s, const SecurityScreen()));
    await tester.tap(find.text('Regenerate recovery code'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, 'Type "regenerate" to confirm'), 'regenerate');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Regenerate'));
    await tester.pumpAndSettle();
    expect(find.text('Your recovery code'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'I saved it'));
    await tester.pumpAndSettle();
  });

  // ---- Re-auth gate ---------------------------------------------------------

  Widget reauthHarness(PortfolioStore s, void Function(bool) onResult) =>
      _host(
        s,
        Builder(
          builder: (ctx) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async => onResult(await requireReauth(ctx, s)),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      );

  testWidgets('reauth: recovery-code fallback passes the gate', (tester) async {
    final (s, code) = await _encrypted();
    bool? result;
    await tester.pumpWidget(reauthHarness(s, (r) => result = r));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('Confirm it\'s you'), findsOneWidget);
    await tester.tap(find.text('Forgot? Use recovery code'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), code);
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });

  testWidgets('reauth: Touch ID passes the gate', (tester) async {
    final (s, _) = await _encrypted(bio: true);
    await s.enableBiometric();
    bool? result;
    await tester.pumpWidget(reauthHarness(s, (r) => result = r));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Touch ID'));
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });

  // ---- Destructive confirm: Touch ID branch ---------------------------------

  testWidgets('confirm dialog confirms via Touch ID', (tester) async {
    final (s, _) = await _encrypted(bio: true);
    await s.enableBiometric();
    bool? result;
    await tester.pumpWidget(_host(
      s,
      Builder(
        builder: (ctx) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async => result = await confirmTyped(ctx,
                  title: 'Delete?',
                  message: 'm',
                  phrase: 'delete',
                  confirmLabel: 'Delete',
                  verifyPassphrase: s.verifyPassphrase,
                  verifyBiometric: s.verifyBiometric),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, 'Type "delete" to confirm'), 'delete');
    await tester.pump();
    await tester.tap(find.widgetWithText(TextButton, 'Touch ID'));
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });

  testWidgets('confirm dialog confirms via recovery code', (tester) async {
    final (s, code) = await _encrypted();
    bool? result;
    await tester.pumpWidget(_host(
      s,
      Builder(
        builder: (ctx) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async => result = await confirmTyped(ctx,
                  title: 'Delete?',
                  message: 'm',
                  phrase: 'delete',
                  confirmLabel: 'Delete',
                  verifyPassphrase: s.verifyPassphrase,
                  verifyRecoveryCode: s.verifyRecoveryCode),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, 'Type "delete" to confirm'), 'delete');
    await tester.pump();
    await tester.tap(find.text('Forgot? Use recovery code'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Recovery code'), code);
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });
}

// Copyright 2026 Jim Zucker
// SPDX-License-Identifier: LicenseRef-Proprietary
// Gaps in the unlock + security UI: the "Forget & reset" path that erases local
// data (only after the typed confirmation; cancel keeps everything), the
// recovery-code error messages, and turning encryption on from Security.


import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ihaveannuities/core/models.dart';
import 'package:ihaveannuities/core/payoff.dart';
import 'package:ihaveannuities/data/biometric.dart';
import 'package:ihaveannuities/data/market.dart';
import 'package:ihaveannuities/data/portfolio_store.dart';
import 'package:ihaveannuities/data/vault.dart';
import 'package:ihaveannuities/ui/security_screen.dart';
import 'package:ihaveannuities/ui/unlock_screen.dart';

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
  final bool supported; // device has Touch ID, but enrolment is always cancelled
  final Uint8List secret = Uint8List.fromList(List.filled(32, 7));
  @override
  Future<bool> isSupported() async => supported;
  @override
  Future<BiometricEnrollment?> enroll() async => null;
  @override
  Future<Uint8List?> authenticate(String credentialId) async => null;
}

PortfolioStore _fresh({bool bio = false}) => PortfolioStore(
    vault: Vault(kdfIterations: 1000), biometric: _FakeBio(supported: bio));

Future<(PortfolioStore, String)> _lockedStore() async {
  final s = _fresh()..debugSeed([_h('AAA')], _market);
  final code = await s.enableEncryption('orig');
  await s.lock();
  return (s, code);
}

Widget _host(PortfolioStore s, Widget home) =>
    ChangeNotifierProvider.value(value: s, child: MaterialApp(home: home));

Future<Set<String>> _storedKeys() async =>
    (await SharedPreferences.getInstance()).getKeys();

/// Fills the recovery form (code, new passphrase, confirm).
Future<void> _fillRecovery(
    WidgetTester tester, String code, String p1, String p2) async {
  await tester.tap(find.text('Use recovery code'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField).at(0), code);
  await tester.enterText(find.byType(TextField).at(1), p1);
  await tester.enterText(find.byType(TextField).at(2), p2);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // ---- Gap 2: Forget & reset ------------------------------------------------

  group('Forget & reset', () {
    Future<void> openDialog(WidgetTester tester, PortfolioStore s) async {
      await tester.pumpWidget(_host(s, const UnlockScreen()));
      await tester.tap(find.text('Forget & reset…'));
      await tester.pumpAndSettle();
      expect(find.text('Forget & reset?'), findsOneWidget);
    }

    testWidgets('cancel keeps the encrypted data and the passphrase working',
        (tester) async {
      final (s, _) = await _lockedStore();
      final before = await _storedKeys();
      expect(before, isNotEmpty);

      await openDialog(tester, s);
      // Type the phrase too, so cancel is tested with the button armed.
      await tester.enterText(find.byType(TextField).last, 'reset');
      await tester.pump();
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Forget & reset?'), findsNothing);
      expect(s.encryptionEnabled, isTrue);
      expect(s.vaultState, VaultState.locked);
      expect(await _storedKeys(), before);
      expect(await s.unlock('orig'), isTrue);
      expect(s.holdings.single.issuer, 'AAA');
    });

    testWidgets('the erase button stays disabled until "reset" is typed',
        (tester) async {
      final (s, _) = await _lockedStore();
      final before = await _storedKeys();
      await openDialog(tester, s);

      FilledButton eraseButton() => tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Forget & reset'));
      expect(eraseButton().onPressed, isNull);

      await tester.enterText(find.byType(TextField).last, 'reser');
      await tester.pump();
      expect(eraseButton().onPressed, isNull);
      // Tapping the disabled button does nothing.
      await tester.tap(find.widgetWithText(FilledButton, 'Forget & reset'));
      await tester.pumpAndSettle();
      expect(await _storedKeys(), before);
      expect(s.encryptionEnabled, isTrue);

      await tester.enterText(find.byType(TextField).last, 'reset');
      await tester.pump();
      expect(eraseButton().onPressed, isNotNull);
    });

    testWidgets('confirming erases the stored portfolio and turns encryption off',
        (tester) async {
      final (s, _) = await _lockedStore();
      expect(await _storedKeys(), containsAll(['portfolio.v1', 'vault.meta.v1']));
      await openDialog(tester, s);

      await tester.enterText(find.byType(TextField).last, 'reset');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Forget & reset'));
      await tester.pumpAndSettle();

      expect(s.encryptionEnabled, isFalse);
      expect(s.vaultState, VaultState.disabled);
      expect(s.holdings, isEmpty);
      // No portfolio data, reset history, vault metadata or session remains.
      final left = await _storedKeys();
      for (final k in ['portfolio.v1', 'resetHistory.v1', 'vault.meta.v1',
          'vault.session.v1']) {
        expect(left, isNot(contains(k)), reason: 'left: $left');
      }
    });
  });

  // ---- Gap 3: recovery-code errors ------------------------------------------

  group('Recovery errors', () {
    testWidgets('empty new passphrase is refused and nothing changes',
        (tester) async {
      final (s, code) = await _lockedStore();
      await tester.pumpWidget(_host(s, const UnlockScreen()));
      await _fillRecovery(tester, code, '', '');
      await tester.tap(find.widgetWithText(FilledButton, 'Recover & set passphrase'));
      await tester.pumpAndSettle();
      expect(find.text('Enter a new passphrase'), findsOneWidget);
      expect(s.vaultState, VaultState.locked);
      expect(await s.unlock('orig'), isTrue);
    });

    testWidgets('mismatched new passphrases are refused', (tester) async {
      final (s, code) = await _lockedStore();
      await tester.pumpWidget(_host(s, const UnlockScreen()));
      await _fillRecovery(tester, code, 'one-pass', 'two-pass');
      await tester.tap(find.widgetWithText(FilledButton, 'Recover & set passphrase'));
      await tester.pumpAndSettle();
      expect(find.text('Passphrases don\'t match'), findsOneWidget);
      expect(s.vaultState, VaultState.locked);
      expect(await s.unlock('orig'), isTrue);
      await s.lock();
      expect(await s.unlock('one-pass'), isFalse);
    });

    testWidgets('a wrong recovery code is refused and the passphrase is kept',
        (tester) async {
      final (s, _) = await _lockedStore();
      await tester.pumpWidget(_host(s, const UnlockScreen()));
      await _fillRecovery(tester, 'WRONG-CODE-0000', 'fresh', 'fresh');
      // Enter in the confirm field submits the form.
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.text('Invalid recovery code'), findsOneWidget);
      expect(s.vaultState, VaultState.locked);
      expect(await s.unlock('fresh'), isFalse);
      expect(await s.unlock('orig'), isTrue);
    });

    testWidgets('Enter in the passphrase field unlocks', (tester) async {
      final (s, _) = await _lockedStore();
      await tester.pumpWidget(_host(s, const UnlockScreen()));
      await tester.enterText(find.byType(TextField), 'orig');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(s.vaultState, VaultState.unlocked);
      expect(s.holdings.single.issuer, 'AAA');
    });
  });

  // ---- Gap 4: turning encryption on from Security ---------------------------

  group('Turn on encryption', () {
    Future<void> openEnable(WidgetTester tester, PortfolioStore s) async {
      await tester.pumpWidget(_host(s, const SecurityScreen()));
      await tester.pumpAndSettle();
      expect(s.encryptionEnabled, isFalse);
      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();
      expect(find.text('Set a passphrase'), findsOneWidget);
    }

    testWidgets('an empty passphrase is refused and encryption stays off',
        (tester) async {
      final s = _fresh()..debugSeed([_h('AAA')], _market);
      await openEnable(tester, s);
      await tester.tap(find.widgetWithText(FilledButton, 'OK'));
      await tester.pumpAndSettle();
      expect(find.text('Enter a passphrase'), findsOneWidget);
      expect(s.encryptionEnabled, isFalse);
    });

    testWidgets('cancel leaves encryption off', (tester) async {
      final s = _fresh()..debugSeed([_h('AAA')], _market);
      await openEnable(tester, s);
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Set a passphrase'), findsNothing);
      expect(s.encryptionEnabled, isFalse);
      expect(s.holdings.single.issuer, 'AAA');
    });

    testWidgets('enabling shows the recovery code; data survives lock + unlock',
        (tester) async {
      final s = _fresh()..debugSeed([_h('AAA')], _market);
      await openEnable(tester, s);
      await tester.enterText(find.byType(TextField).at(0), 'secret-1');
      await tester.enterText(find.byType(TextField).at(1), 'secret-1');
      // Enter in the confirm field submits.
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.text('Your recovery code'), findsOneWidget);
      // Copy puts the shown code on the clipboard.
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      });
      final shown = tester.widget<SelectableText>(find.byType(SelectableText)).data;
      await tester.tap(find.text('Copy'));
      await tester.pump();
      expect(copied, shown);
      expect(find.text('Recovery code copied'), findsOneWidget);
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
      await tester.tap(find.widgetWithText(FilledButton, 'I saved it'));
      await tester.pumpAndSettle();
      expect(find.text('Your recovery code'), findsNothing);
      expect(s.encryptionEnabled, isTrue);

      await s.lock();
      expect(s.vaultState, VaultState.locked);
      expect(await s.unlock('wrong'), isFalse);
      expect(await s.unlock('secret-1'), isTrue);
      expect(s.holdings.single.issuer, 'AAA');
    });

    testWidgets('cancelled Touch ID setup says so and stays off', (tester) async {
      final s = _fresh(bio: true)..debugSeed([_h('AAA')], _market);
      await s.enableEncryption('pass');
      await tester.pumpWidget(_host(s, const SecurityScreen()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Unlock with Touch ID / Face ID'));
      await tester.pumpAndSettle();
      expect(find.text('Biometric setup cancelled or unavailable'), findsOneWidget);
      expect(s.biometricEnabled, isFalse);
    });

    testWidgets('Lock now locks the store and leaves the screen', (tester) async {
      final s = _fresh()..debugSeed([_h('AAA')], _market);
      await s.enableEncryption('pass');
      await tester.pumpWidget(_host(
          s,
          Builder(
              builder: (ctx) => TextButton(
                  onPressed: () => Navigator.of(ctx).push(
                      MaterialPageRoute(builder: (_) => const SecurityScreen())),
                  child: const Text('open')))));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Lock now'), 100);
      await tester.tap(find.text('Lock now'));
      await tester.pumpAndSettle();
      expect(s.vaultState, VaultState.locked);
      expect(find.byType(SecurityScreen), findsNothing);
    });
  });
}

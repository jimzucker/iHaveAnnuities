// Copyright 2026 Jim Zucker
// SPDX-License-Identifier: LicenseRef-Proprietary
// PortfolioStore vault integration: enable/lock/unlock, recovery, biometric,
// migration, stay-unlocked session. Uses a tiny KDF count + a fake biometric.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ihaveannuities/core/models.dart';
import 'package:ihaveannuities/core/payoff.dart';
import 'package:ihaveannuities/data/biometric.dart';
import 'package:ihaveannuities/data/market.dart';
import 'package:ihaveannuities/data/portfolio_store.dart';
import 'package:ihaveannuities/data/vault.dart';
import 'package:shared_preferences/shared_preferences.dart';

http.Client _mkClient() => MockClient((_) async => http.Response(
    '{"asOf":"2026-06-12","spx":7431.46,"ndx":29635.95,"rut":2943.99}', 200));

final _market = Market(
    asOf: DateTime(2026, 6, 12), spx: 7431.46, ndx: 29635.95, rut: 2943.99);

// nextReset far in the future → no catch-up (no network) during unlock.
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
  final bool supported = true;
  final Uint8List secret = Uint8List.fromList(List.filled(32, 7));
  @override
  Future<bool> isSupported() async => supported;
  @override
  Future<BiometricEnrollment?> enroll() async =>
      supported ? BiometricEnrollment('cred-1', secret) : null;
  @override
  Future<Uint8List?> authenticate(String credentialId) async =>
      supported ? secret : null;
}

PortfolioStore _store({_FakeBio? bio}) => PortfolioStore(
    vault: Vault(kdfIterations: 1000), biometric: bio ?? _FakeBio());

Future<String?> _raw(String key) async =>
    (await SharedPreferences.getInstance()).getString(key);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('enable → ciphertext at rest → lock → unlock restores data', () async {
    final s = _store()..debugSeed([_h('AAA'), _h('BBB')], _market);
    final code = await s.enableEncryption('pass1');
    expect(code, isNotEmpty);
    expect(s.vaultState, VaultState.unlocked);
    expect(s.encryptionEnabled, isTrue);
    final stored = await _raw('portfolio.v1');
    expect(stored, isNotNull);
    expect(stored, isNot(contains('AAA'))); // encrypted, not plaintext JSON

    await s.lock();
    expect(s.vaultState, VaultState.locked);
    expect(s.holdings, isEmpty);

    expect(await s.unlock('pass1'), isTrue);
    expect(s.vaultState, VaultState.unlocked);
    expect(s.holdings.map((h) => h.issuer), ['AAA', 'BBB']);
  });

  test('wrong passphrase is rejected and stays locked', () async {
    final s = _store()..debugSeed([_h('AAA')], _market);
    await s.enableEncryption('right');
    await s.lock();
    expect(await s.unlock('wrong'), isFalse);
    expect(s.vaultState, VaultState.locked);
    expect(s.holdings, isEmpty);
  });

  test('recover with code, then set a new passphrase; old one no longer works',
      () async {
    final s = _store()..debugSeed([_h('AAA')], _market);
    final code = await s.enableEncryption('orig');
    await s.lock();

    expect(await s.recoverWithCode(code), isTrue);
    expect(s.holdings.single.issuer, 'AAA');
    await s.changePassphrase('brand-new');
    await s.lock();

    expect(await s.unlock('orig'), isFalse); // replaced
    expect(await s.unlock('brand-new'), isTrue);
  });

  test('biometric enroll → unlock', () async {
    final s = _store()..debugSeed([_h('AAA')], _market);
    await s.enableEncryption('pass');
    expect(await s.enableBiometric(), isTrue);
    expect(s.biometricEnabled, isTrue);
    await s.lock();
    expect(await s.biometricUnlock(), isTrue);
    expect(s.holdings.single.issuer, 'AAA');
  });

  test('disable encryption writes plaintext back', () async {
    final s = _store()..debugSeed([_h('AAA')], _market);
    await s.enableEncryption('pass');
    await s.disableEncryption();
    expect(s.vaultState, VaultState.disabled);
    expect(s.encryptionEnabled, isFalse);
    expect(await _raw('portfolio.v1'), contains('AAA')); // plaintext again
    expect(s.holdings.single.issuer, 'AAA');
  });

  test('stay-unlocked session is written on unlock, cleared on lock', () async {
    final s = _store()..debugSeed([_h('AAA')], _market);
    await s.enableEncryption('pass');
    final sess = await _raw('vault.session.v1');
    expect(sess, isNotNull);
    expect(DateTime.parse(jsonDecode(sess!)['expiresAt'] as String).isAfter(DateTime.now()),
        isTrue);
    await s.lock();
    expect(await _raw('vault.session.v1'), isNull);
  });

  test('enabling encryption migrates existing plaintext holdings', () async {
    final s = _store();
    SharedPreferences.setMockInitialValues({});
    s.debugSeed([], _market);
    await s.replaceAll([_h('AAA'), _h('BBB')]); // persisted as plaintext
    expect(await _raw('portfolio.v1'), contains('AAA'));
    await s.enableEncryption('pass');
    expect(await _raw('portfolio.v1'), isNot(contains('AAA'))); // now encrypted
    await s.lock();
    expect(await s.unlock('pass'), isTrue);
    expect(s.holdings.length, 2);
  });

  test('regenerate recovery code: new code works, old one stops', () async {
    final s = _store()..debugSeed([_h('AAA')], _market);
    final code1 = await s.enableEncryption('pass');
    final code2 = await s.regenerateRecoveryCode();
    expect(code2, isNotNull);
    expect(code2, isNot(code1));
    await s.lock();
    expect(await s.recoverWithCode(code1), isFalse); // invalidated
    expect(await s.recoverWithCode(code2!), isTrue);
  });

  test('biometric can be disabled; unlock fails without enrollment', () async {
    final s = _store()..debugSeed([_h('AAA')], _market);
    await s.enableEncryption('pass');
    await s.enableBiometric();
    await s.disableBiometric();
    expect(s.biometricEnabled, isFalse);
    await s.lock();
    expect(await s.biometricUnlock(), isFalse); // no credential anymore
  });

  test('recover with a bad code is rejected', () async {
    final s = _store()..debugSeed([_h('AAA')], _market);
    await s.enableEncryption('pass');
    await s.lock();
    expect(await s.recoverWithCode('XXXX-XXXX-XXXX-XXXX-XXXX-XXXX'), isFalse);
    expect(s.vaultState, VaultState.locked);
  });

  test('setStayUnlockedDays refreshes the session expiry', () async {
    final s = _store()..debugSeed([_h('AAA')], _market);
    await s.enableEncryption('pass');
    await s.setStayUnlockedDays(7);
    expect(s.stayUnlockedDays, 7);
    final exp = DateTime.parse(
        jsonDecode((await _raw('vault.session.v1'))!)['expiresAt'] as String);
    expect(exp.isBefore(DateTime.now().add(const Duration(days: 8))), isTrue);
  });

  test('init restores a valid stay-unlocked session and decrypts', () async {
    final a = _store()..debugSeed([_h('AAA')], _market);
    await a.enableEncryption('pass'); // writes meta + session + ciphertext
    a.dispose();

    final b = PortfolioStore(
        vault: Vault(kdfIterations: 1000), biometric: _FakeBio(), client: _mkClient());
    await b.init();
    expect(b.vaultState, VaultState.unlocked);
    expect(b.holdings.single.issuer, 'AAA');
    b.dispose();
  });

  test('init stays locked when there is no session', () async {
    final a = _store()..debugSeed([_h('AAA')], _market);
    await a.enableEncryption('pass');
    await a.lock(); // clears the session
    a.dispose();

    final b = PortfolioStore(
        vault: Vault(kdfIterations: 1000), biometric: _FakeBio(), client: _mkClient());
    await b.init();
    expect(b.vaultState, VaultState.locked);
    expect(b.holdings, isEmpty);
    b.dispose();
  });

  test('init discards an expired session and stays locked', () async {
    final a = _store()..debugSeed([_h('AAA')], _market);
    await a.enableEncryption('pass');
    a.dispose();
    // Backdate the session so it's expired.
    (await SharedPreferences.getInstance()).setString(
        'vault.session.v1',
        jsonEncode({'dek': 'AAAA', 'expiresAt': '2000-01-01T00:00:00.000'}));

    final b = PortfolioStore(
        vault: Vault(kdfIterations: 1000), biometric: _FakeBio(), client: _mkClient());
    await b.init();
    expect(b.vaultState, VaultState.locked);
    expect(await _raw('vault.session.v1'), isNull); // pruned
    b.dispose();
  });

  test('verifyPassphrase gates destructive actions', () async {
    final s = _store()..debugSeed([_h('AAA')], _market);
    expect(await s.verifyPassphrase('anything'), isTrue); // off → no gate
    await s.enableEncryption('secret');
    expect(await s.verifyPassphrase('secret'), isTrue);
    expect(await s.verifyPassphrase('nope'), isFalse);
    expect(s.vaultState, VaultState.unlocked); // checking didn't change state
  });

  test('portfolioXirr: positive for a profitable book, null when empty', () {
    final s = _store()..debugSeed([_h('AAA')], _market); // open 2025, value > initial
    final r = s.portfolioXirr;
    expect(r, isNotNull);
    expect(r! > 0, isTrue);
    expect((_store()..debugSeed([], _market)).portfolioXirr, isNull);
  });

  test('verifyBiometric checks identity without changing state', () async {
    final s = _store()..debugSeed([_h('AAA')], _market);
    await s.enableEncryption('p');
    expect(await s.verifyBiometric(), isFalse); // not enrolled yet
    await s.enableBiometric();
    expect(await s.verifyBiometric(), isTrue);
    expect(s.vaultState, VaultState.unlocked);
  });

  test('verifyRecoveryCode gates without changing state', () async {
    final s = _store()..debugSeed([_h('AAA')], _market);
    expect(await s.verifyRecoveryCode('any'), isTrue); // off → no gate
    final code = await s.enableEncryption('p');
    expect(await s.verifyRecoveryCode(code), isTrue);
    expect(await s.verifyRecoveryCode('XXXX-XXXX'), isFalse);
    expect(s.vaultState, VaultState.unlocked); // checking didn't change state
  });

  test('onboarding flag flips after markOnboarded', () async {
    final s = _store(); // fresh, no debugSeed
    expect(s.needsOnboarding, isTrue);
    await s.markOnboarded();
    expect(s.needsOnboarding, isFalse);
  });

  test('encryption nudge shows once then is dismissed', () async {
    final s = _store()..debugSeed([_h('AAA')], _market); // onboarded, data, no vault
    expect(s.shouldNudgeEncryption, isTrue);
    await s.dismissEncryptionNudge();
    expect(s.shouldNudgeEncryption, isFalse);
  });

  test('NoBiometric reports unsupported; defaultBiometric is one', () async {
    const b = NoBiometric();
    expect(await b.isSupported(), isFalse);
    expect(await b.enroll(), isNull);
    expect(await b.authenticate('x'), isNull);
    expect(defaultBiometric(), isA<BiometricAuthenticator>());
  });
}

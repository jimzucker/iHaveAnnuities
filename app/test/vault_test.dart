// Copyright 2026 Jim Zucker
// SPDX-License-Identifier: LicenseRef-Proprietary
// Crypto core for the local encrypted vault. Uses a tiny KDF iteration count so
// the suite stays fast (production uses kVaultKdfIterations).

import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ihaveannuities/data/vault.dart';

void main() {
  final vault = Vault(kdfIterations: 1000);

  test('deriveKek is deterministic for the same secret + salt', () async {
    final salt = vault.newSalt();
    final dek = vault.newDek();
    final k1 = await vault.deriveKek('hunter2', salt);
    final k2 = await vault.deriveKek('hunter2', salt);
    final env = await vault.wrap(dek, k1);
    expect(await vault.unwrap(env, k2), dek); // a key derived again still unwraps
  });

  test('wrap → unwrap round-trips the DEK', () async {
    final dek = vault.newDek();
    final kek = await vault.deriveKek('pass', vault.newSalt());
    expect(await vault.unwrap(await vault.wrap(dek, kek), kek), dek);
  });

  test('wrong passphrase fails to unwrap', () async {
    final salt = vault.newSalt();
    final env = await vault.wrap(vault.newDek(), await vault.deriveKek('right', salt));
    final wrongKek = await vault.deriveKek('wrong', salt);
    await expectLater(
        vault.unwrap(env, wrongKek), throwsA(isA<SecretBoxAuthenticationError>()));
  });

  test('tampered ciphertext fails authentication', () async {
    final kek = await vault.deriveKek('p', vault.newSalt());
    final env = await vault.wrap(vault.newDek(), kek);
    final bytes = base64Decode(env);
    bytes[bytes.length - 1] ^= 0xFF; // flip a mac byte
    await expectLater(vault.unwrap(base64Encode(bytes), kek),
        throwsA(isA<SecretBoxAuthenticationError>()));
  });

  test('a DEK wrapped by passphrase AND recovery code unwraps with either',
      () async {
    final dek = vault.newDek();
    final saltPp = vault.newSalt(), saltRc = vault.newSalt();
    final code = vault.newRecoveryCode();
    final wrapPp = await vault.wrap(dek, await vault.deriveKek('pp', saltPp));
    final wrapRc = await vault.wrap(
        dek, await vault.deriveKek(Vault.normalizeRecoveryCode(code), saltRc));
    expect(await vault.unwrap(wrapPp, await vault.deriveKek('pp', saltPp)), dek);
    expect(
        await vault.unwrap(
            wrapRc, await vault.deriveKek(Vault.normalizeRecoveryCode(code), saltRc)),
        dek);
  });

  test('encryptString / decryptString round-trips a portfolio blob', () async {
    final dek = vault.newDek();
    const plain = '[{"issuer":"X","initial":100.0}]';
    final env = await vault.encryptString(plain, dek);
    expect(env, isNot(contains('issuer'))); // ciphertext, not plaintext
    expect(await vault.decryptString(env, dek), plain);
  });

  test('recovery code is 6 dash-grouped Crockford groups', () {
    final code = vault.newRecoveryCode();
    expect(code, matches(RegExp(r'^[0-9A-HJKMNP-TV-Z]{4}(-[0-9A-HJKMNP-TV-Z]{4}){5}$')));
    expect(Vault.normalizeRecoveryCode(code.toLowerCase()),
        code.replaceAll('-', ''));
  });

  test('VaultMeta serializes round-trip incl. biometric', () {
    final m = VaultMeta(
        kdfIterations: 1000,
        saltPp: 'a',
        wrapPp: 'b',
        saltRc: 'c',
        wrapRc: 'd',
        biometric: BiometricWrap(credentialId: 'cid', wrap: 'w'));
    final back = VaultMeta.fromJson(m.toJson());
    expect(back.wrapPp, 'b');
    expect(back.biometric!.credentialId, 'cid');
    expect(VaultMeta.fromJson(m.copyWith(clearBiometric: true).toJson()).biometric,
        isNull);
  });
}

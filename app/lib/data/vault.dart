// Copyright 2026 Jim Zucker
// SPDX-License-Identifier: Apache-2.0
// Local encrypted vault — pure crypto core (no Flutter, no storage).
//
// Key-wrapping model: a random 256-bit Data Encryption Key (DEK) encrypts the
// portfolio. The DEK is itself wrapped (AES-GCM-encrypted) separately by a key
// derived from each unlock method — passphrase, recovery code, biometric — so
// any one of them can unwrap the DEK. Adding/removing a method only adds/removes
// its wrapped-DEK copy; the data is never re-encrypted.
//
// On web the `cryptography` package uses the browser's Web Crypto (SubtleCrypto)
// for AES-GCM/PBKDF2; in the test VM it uses a pure-Dart implementation, so the
// unit tests run in CI without a browser.

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// OWASP-recommended PBKDF2-HMAC-SHA256 iteration count (2023).
const int kVaultKdfIterations = 310000;

class Vault {
  Vault({this.kdfIterations = kVaultKdfIterations});

  /// Configurable so tests can use a small count (KDF is deliberately slow).
  final int kdfIterations;

  final AesGcm _aes = AesGcm.with256bits();
  static const int _nonceLen = 12;
  static const int _macLen = 16;

  /// Cryptographically-random bytes.
  Uint8List randomBytes(int n) {
    final r = Random.secure();
    return Uint8List.fromList(List<int>.generate(n, (_) => r.nextInt(256)));
  }

  /// A fresh 256-bit Data Encryption Key.
  Uint8List newDek() => randomBytes(32);

  /// A fresh 128-bit salt for a KDF.
  Uint8List newSalt() => randomBytes(16);

  /// Derive a 256-bit key-encryption key from a secret (passphrase/recovery
  /// code) and salt via PBKDF2-HMAC-SHA256. [iterations] overrides the default
  /// (used on unlock to match the count stored in the vault meta).
  Future<SecretKey> deriveKek(String secret, List<int> salt, {int? iterations}) {
    final pbkdf2 = Pbkdf2(
        macAlgorithm: Hmac.sha256(),
        iterations: iterations ?? kdfIterations,
        bits: 256);
    return pbkdf2.deriveKey(secretKey: SecretKey(utf8.encode(secret)), nonce: salt);
  }

  /// Wrap (AES-GCM-encrypt) raw bytes with [kek] → a base64 envelope
  /// (nonce ‖ ciphertext ‖ mac).
  Future<String> wrap(List<int> data, SecretKey kek) async {
    final box = await _aes.encrypt(data, secretKey: kek);
    return base64Encode(box.concatenation());
  }

  /// Unwrap an envelope produced by [wrap]. Throws [SecretBoxAuthenticationError]
  /// if the key is wrong or the ciphertext was tampered with.
  Future<Uint8List> unwrap(String envelope, SecretKey kek) async {
    final box = SecretBox.fromConcatenation(base64Decode(envelope),
        nonceLength: _nonceLen, macLength: _macLen);
    return Uint8List.fromList(await _aes.decrypt(box, secretKey: kek));
  }

  /// Encrypt a UTF-8 string with the DEK → base64 envelope.
  Future<String> encryptString(String plain, List<int> dek) =>
      wrap(utf8.encode(plain), SecretKey(dek));

  /// Decrypt an envelope produced by [encryptString] back to its string.
  Future<String> decryptString(String envelope, List<int> dek) async =>
      utf8.decode(await unwrap(envelope, SecretKey(dek)));

  // Crockford base32 (no I/L/O/U) — unambiguous to read back from paper.
  static const _b32 = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

  /// A one-time recovery code: 120 bits, grouped as XXXX-XXXX-… (6 groups).
  String newRecoveryCode() {
    final bytes = randomBytes(15); // 120 bits
    var value = 0, bits = 0;
    final raw = StringBuffer();
    for (final b in bytes) {
      value = (value << 8) | b;
      bits += 8;
      while (bits >= 5) {
        raw.write(_b32[(value >> (bits - 5)) & 31]);
        bits -= 5;
      }
    }
    if (bits > 0) raw.write(_b32[(value << (5 - bits)) & 31]);
    final s = raw.toString();
    final groups = <String>[
      for (var i = 0; i < s.length; i += 4) s.substring(i, min(i + 4, s.length)),
    ];
    return groups.join('-');
  }

  /// Normalize a user-typed recovery code (strip dashes/spaces, uppercase) so
  /// derivation matches regardless of formatting.
  static String normalizeRecoveryCode(String code) =>
      code.replaceAll(RegExp(r'[^0-9A-Za-z]'), '').toUpperCase();
}

/// Persisted vault metadata: per-method salts + wrapped DEK copies. Holds NO
/// secret on its own — every field is useless without a passphrase/code/biometric.
class VaultMeta {
  VaultMeta({
    required this.kdfIterations,
    required this.saltPp,
    required this.wrapPp,
    required this.saltRc,
    required this.wrapRc,
    this.biometric,
  });

  final int kdfIterations;
  final String saltPp; // base64
  final String wrapPp; // DEK wrapped by the passphrase KEK
  final String saltRc;
  final String wrapRc; // DEK wrapped by the recovery-code KEK
  final BiometricWrap? biometric;

  Map<String, dynamic> toJson() => {
        'v': 1,
        'kdfIterations': kdfIterations,
        'saltPp': saltPp,
        'wrapPp': wrapPp,
        'saltRc': saltRc,
        'wrapRc': wrapRc,
        if (biometric != null) 'biometric': biometric!.toJson(),
      };

  factory VaultMeta.fromJson(Map<String, dynamic> j) => VaultMeta(
        kdfIterations: (j['kdfIterations'] as num).toInt(),
        saltPp: j['saltPp'] as String,
        wrapPp: j['wrapPp'] as String,
        saltRc: j['saltRc'] as String,
        wrapRc: j['wrapRc'] as String,
        biometric: j['biometric'] == null
            ? null
            : BiometricWrap.fromJson(j['biometric'] as Map<String, dynamic>),
      );

  VaultMeta copyWith({
    String? saltPp,
    String? wrapPp,
    String? saltRc,
    String? wrapRc,
    BiometricWrap? biometric,
    bool clearBiometric = false,
  }) =>
      VaultMeta(
        kdfIterations: kdfIterations,
        saltPp: saltPp ?? this.saltPp,
        wrapPp: wrapPp ?? this.wrapPp,
        saltRc: saltRc ?? this.saltRc,
        wrapRc: wrapRc ?? this.wrapRc,
        biometric: clearBiometric ? null : (biometric ?? this.biometric),
      );
}

/// The DEK wrapped by the WebAuthn-PRF biometric secret, plus the credential id
/// needed to re-authenticate the right passkey.
class BiometricWrap {
  BiometricWrap({required this.credentialId, required this.wrap});
  final String credentialId; // base64
  final String wrap; // DEK wrapped by the PRF-derived key

  Map<String, dynamic> toJson() => {'credentialId': credentialId, 'wrap': wrap};
  factory BiometricWrap.fromJson(Map<String, dynamic> j) => BiometricWrap(
        credentialId: j['credentialId'] as String,
        wrap: j['wrap'] as String,
      );
}

// Copyright 2026 Jim Zucker
// SPDX-License-Identifier: LicenseRef-Proprietary
// Biometric (Touch ID / Face ID) unlock via WebAuthn PRF. The PRF extension
// returns a stable per-credential secret on a successful platform-authenticator
// gesture; that secret wraps the vault DEK. The browser never exposes the secret
// without the biometric, and nothing extra is persisted unprotected.
//
// The real implementation is web-only (js_interop → web/webauthn.js); on the VM
// (tests) a no-op stand-in reports "unsupported". Store logic is exercised in
// tests via a fake [BiometricAuthenticator].

import 'dart:typed_data';

import 'biometric_stub.dart' if (dart.library.js_interop) 'biometric_web.dart';

/// Result of enrolling a platform passkey: its credential id, plus the PRF
/// secret if the browser returned it during create() (modern Chrome → one
/// prompt). When [prfSecret] is null the caller derives it via [authenticate].
class BiometricEnrollment {
  const BiometricEnrollment(this.credentialId, this.prfSecret);
  final String credentialId; // base64
  final Uint8List? prfSecret; // 32 bytes, or null if not available at create
}

abstract class BiometricAuthenticator {
  /// Whether the platform supports WebAuthn PRF (Chromium + a platform auth).
  Future<bool> isSupported();

  /// Create a platform passkey. Returns its id (+ PRF secret when available), or
  /// null if the user cancels / PRF is unsupported.
  Future<BiometricEnrollment?> enroll();

  /// Re-authenticate [credentialId] (Touch ID) and return its PRF secret, or
  /// null. This is the unlock path (and the enroll fallback).
  Future<Uint8List?> authenticate(String credentialId);
}

/// Stand-in used off-web and in tests: biometrics are simply unavailable.
class NoBiometric implements BiometricAuthenticator {
  const NoBiometric();
  @override
  Future<bool> isSupported() async => false;
  @override
  Future<BiometricEnrollment?> enroll() async => null;
  @override
  Future<Uint8List?> authenticate(String credentialId) async => null;
}

/// Platform-appropriate authenticator (web impl on the browser, no-op elsewhere).
BiometricAuthenticator defaultBiometric() => createBiometric();

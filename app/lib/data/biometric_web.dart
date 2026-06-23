// Copyright 2026 Jim Zucker
// SPDX-License-Identifier: Apache-2.0
// Web implementation of BiometricAuthenticator over the global helpers defined
// in web/webauthn.js (which does the actual WebAuthn PRF dance and base64s the
// results). Needs live device verification — not exercised in headless tests.

import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'biometric.dart';

@JS('webauthnSupported')
external JSBoolean _supported();
@JS('webauthnEnroll')
external JSPromise<JSAny?> _enroll();
@JS('webauthnAuth')
external JSPromise<JSAny?> _auth(JSString credentialId);

extension type _EnrollResult(JSObject _) implements JSObject {
  external String get credentialId;
  external String? get prf; // present when create() returned the PRF secret
}

extension type _AuthResult(JSObject _) implements JSObject {
  external String get prf;
}

class WebBiometric implements BiometricAuthenticator {
  @override
  Future<bool> isSupported() async {
    try {
      return _supported().toDart;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<BiometricEnrollment?> enroll() async {
    try {
      final r = await _enroll().toDart;
      if (r == null) return null;
      final e = r as _EnrollResult;
      final prf = e.prf;
      return BiometricEnrollment(
          e.credentialId, prf == null ? null : base64Decode(prf));
    } catch (_) {
      return null;
    }
  }

  @override
  Future<Uint8List?> authenticate(String credentialId) async {
    try {
      final r = await _auth(credentialId.toJS).toDart;
      if (r == null) return null;
      return base64Decode((r as _AuthResult).prf);
    } catch (_) {
      return null;
    }
  }
}

BiometricAuthenticator createBiometric() => WebBiometric();

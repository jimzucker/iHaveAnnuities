// Copyright 2026 Jim Zucker
// SPDX-License-Identifier: LicenseRef-Proprietary
// WebAuthn PRF helpers for biometric (Touch ID / Face ID) vault unlock.
// Exposes window.webauthnSupported / webauthnEnroll / webauthnAuth, all
// returning base64 strings so the Dart side stays simple.
(function () {
  var RP_ID = location.hostname || 'localhost';
  // Fixed app salt so the same PRF secret is derived every time.
  var PRF_SALT = new TextEncoder().encode('ihaveannuities-prf-v1');

  function b64(buf) {
    var b = new Uint8Array(buf), s = '';
    for (var i = 0; i < b.length; i++) s += String.fromCharCode(b[i]);
    return btoa(s);
  }
  function fromB64(s) {
    var bin = atob(s), a = new Uint8Array(bin.length);
    for (var i = 0; i < bin.length; i++) a[i] = bin.charCodeAt(i);
    return a;
  }
  function rand(n) {
    var a = new Uint8Array(n);
    crypto.getRandomValues(a);
    return a;
  }

  window.webauthnSupported = function () {
    return !!(window.PublicKeyCredential && navigator.credentials &&
      navigator.credentials.create);
  };

  // Create a platform passkey, asking for the PRF secret in the same step.
  // Modern Chrome returns it during create() → a single Touch ID prompt. If the
  // browser only reports prf.enabled (no secret yet), the caller falls back to a
  // follow-up assertion to derive it.
  window.webauthnEnroll = async function () {
    if (!window.webauthnSupported()) return null;
    try {
      var cred = await navigator.credentials.create({
        publicKey: {
          challenge: rand(32),
          rp: { name: 'iHaveAnnuities', id: RP_ID },
          user: { id: rand(16), name: 'vault', displayName: 'Vault' },
          pubKeyCredParams: [
            { type: 'public-key', alg: -7 },
            { type: 'public-key', alg: -257 },
          ],
          authenticatorSelection: {
            authenticatorAttachment: 'platform',
            residentKey: 'required',
            userVerification: 'required',
          },
          extensions: { prf: { eval: { first: PRF_SALT } } },
        },
      });
      if (!cred) return null;
      var ext = cred.getClientExtensionResults();
      if (!ext || !ext.prf || ext.prf.enabled !== true) {
        console.warn('[vault] passkey created but PRF is not supported here.');
        return null; // can't derive a key from this authenticator
      }
      var secret = ext.prf.results && ext.prf.results.first;
      return {
        credentialId: b64(cred.rawId),
        prf: secret ? b64(secret) : undefined, // undefined → caller will re-auth
      };
    } catch (e) {
      console.warn('[vault] enroll failed:', e);
      return null;
    }
  };

  window.webauthnAuth = async function (credentialIdB64) {
    if (!window.webauthnSupported()) return null;
    try {
      var assertion = await navigator.credentials.get({
        publicKey: {
          challenge: rand(32),
          allowCredentials: [{ id: fromB64(credentialIdB64), type: 'public-key' }],
          userVerification: 'required',
          extensions: { prf: { eval: { first: PRF_SALT } } },
        },
      });
      if (!assertion) return null;
      var ext = assertion.getClientExtensionResults();
      if (!ext || !ext.prf || !ext.prf.results || !ext.prf.results.first) {
        console.warn('[vault] assertion ok but no PRF output.');
        return null;
      }
      return { prf: b64(ext.prf.results.first) };
    } catch (e) {
      console.warn('[vault] authenticate failed:', e);
      return null;
    }
  };
})();

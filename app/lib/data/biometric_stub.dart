// Copyright 2026 Jim Zucker
// SPDX-License-Identifier: Apache-2.0
// Non-web fallback: no biometric authenticator (used by the test VM).

import 'biometric.dart';

BiometricAuthenticator createBiometric() => const NoBiometric();

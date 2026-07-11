// Copyright 2026 Jim Zucker
// SPDX-License-Identifier: LicenseRef-Proprietary
// Non-web fallback: no biometric authenticator (used by the test VM).

import 'biometric.dart';

BiometricAuthenticator createBiometric() => const NoBiometric();

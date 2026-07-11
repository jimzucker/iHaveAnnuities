// Copyright 2026 Jim Zucker
// SPDX-License-Identifier: LicenseRef-Proprietary
// Reload the app to pick up a freshly deployed version (web), no-op elsewhere.

export 'app_reload_stub.dart' if (dart.library.js_interop) 'app_reload_web.dart';

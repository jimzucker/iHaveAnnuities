// Copyright 2026 Jim Zucker
// SPDX-License-Identifier: Apache-2.0
// Web reload — fetches the freshly deployed app. The Flutter loader picks up the
// updated service worker on the next load.

import 'package:web/web.dart' as web;

void reloadApp() => web.window.location.reload();

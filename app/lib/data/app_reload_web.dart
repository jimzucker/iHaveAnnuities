// Copyright 2026 Jim Zucker
// SPDX-License-Identifier: LicenseRef-Proprietary
// Web reload — loads the freshly deployed build. Flutter's service worker caches
// the app shell aggressively, so a plain location.reload() re-serves the OLD
// bundle (the "new version available" banner then reappears in a loop). We first
// unregister the service worker(s) and clear their Cache Storage entries, then
// reload — which forces the browser to fetch the new bundle from the network.
//
// GitHub Pages also lets the browser reuse every file for 10 minutes without
// asking (Cache-Control: max-age=600), so a reload right after a deploy still
// got the old app. Fetching the app's own files with cache: 'reload' replaces
// those cached copies first.
//
// This only touches the HTTP/app-shell cache. The user's portfolio lives in
// localStorage / IndexedDB and is NOT affected.

import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// The files that change with each deploy: the page, the loader and the app.
/// Relative to the page, so the /iHaveAnnuities/ base path is kept.
const _appFiles = ['./', 'index.html', 'flutter_bootstrap.js', 'main.dart.js'];

void reloadApp() {
  _purgeThenReload();
}

Future<void> _purgeThenReload() async {
  try {
    // Unregister the Flutter service worker so it stops serving the cached shell.
    final regs =
        await web.window.navigator.serviceWorker.getRegistrations().toDart;
    for (final r in regs.toDart) {
      await r.unregister().toDart;
    }
    // Drop any caches the worker populated (main.dart.js, assets, …).
    final caches = web.window.caches;
    final keys = await caches.keys().toDart;
    for (final k in keys.toDart) {
      await caches.delete(k.toDart).toDart;
    }
  } catch (_) {
    // Best-effort: whatever fails, still fall through to a plain reload.
  }
  for (final f in _appFiles) {
    try {
      await web.window
          .fetch(Uri.base.resolve(f).toString().toJS,
              web.RequestInit(cache: 'reload'))
          .toDart;
    } catch (_) {/* best-effort, as above */}
  }
  web.window.location.reload();
}

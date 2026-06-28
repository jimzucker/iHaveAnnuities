// Copyright 2026 Jim Zucker
// SPDX-License-Identifier: Apache-2.0
// App-version detection. Each deploy stamps the git SHA into `build-id.json`
// (same-origin on the Pages site) and compiles the same SHA into the app via
// --dart-define=BUILD_SHA. Polling that file and comparing tells a kept-open
// tab that a newer version has been deployed, so we can prompt a reload.

import 'dart:convert';

import 'package:http/http.dart' as http;

/// The git SHA this build was compiled with. `dev` for local/test builds (no
/// --dart-define), which disables the update prompt off-deploy.
const appBuildSha = String.fromEnvironment('BUILD_SHA', defaultValue: 'dev');

/// Fetch the SHA currently published at `build-id.json` (same origin as the
/// app). Returns null on error or if the file/field is missing.
Future<String?> fetchDeployedSha({http.Client? client}) async {
  final c = client ?? http.Client();
  try {
    // Relative to the page (honors the /iHaveAnnuities/ base href on Pages).
    final res = await c.get(Uri.base.resolve('build-id.json'));
    if (res.statusCode != 200) return null;
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    return j['sha'] as String?;
  } catch (_) {
    return null;
  } finally {
    if (client == null) c.close();
  }
}

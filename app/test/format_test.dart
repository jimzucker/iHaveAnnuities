// Copyright 2026 Jim Zucker
// SPDX-License-Identifier: LicenseRef-Proprietary

import 'package:flutter_test/flutter_test.dart';
import 'package:ihaveannuities/ui/format.dart';

void main() {
  test('exportFileName is dated and lowercase', () {
    expect(exportFileName(on: DateTime(2026, 6, 9)),
        'export_ihaveannuities_20260609');
    expect(exportFileName(on: DateTime(2026, 12, 23)),
        'export_ihaveannuities_20261223');
  });
}

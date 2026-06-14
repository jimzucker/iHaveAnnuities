#!/usr/bin/env python3
# check_coverage.py — enforce the coverage gate on app/coverage/lcov.info.
# Copyright 2026 Jim Zucker
# SPDX-License-Identifier: Apache-2.0
#
# Requires lib/core and lib/data at (near) 100% — the pure, fully-testable
# layers — and reports overall. Exits non-zero if the core/data gate fails.

import os
import re
import sys

CORE_MIN = 100.0   # %
DATA_MIN = 95.0    # % (xlsx writer paths partially exercised)


def parse(path):
    per_file = {}
    cur = None
    for line in open(path):
        if line.startswith("SF:"):
            cur = line[3:].strip()
            per_file[cur] = [0, 0]
        elif line.startswith("LF:"):
            per_file[cur][0] = int(line[3:])
        elif line.startswith("LH:"):
            per_file[cur][1] = int(line[3:])
    return per_file


def pct(group):
    lf = sum(v[0] for v in group)
    lh = sum(v[1] for v in group)
    return (100.0 * lh / lf) if lf else 100.0, lh, lf


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else "app/coverage/lcov.info"
    if not os.path.exists(path):
        print(f"no coverage file at {path}")
        return 1
    files = parse(path)
    core = [v for k, v in files.items() if "/lib/core/" in k or k.startswith("lib/core/")]
    data = [v for k, v in files.items() if "/lib/data/" in k or k.startswith("lib/data/")]
    overall = list(files.values())

    cp, clh, clf = pct(core)
    dp, dlh, dlf = pct(data)
    op, olh, olf = pct(overall)
    print(f"core    {cp:6.2f}%  ({clh}/{clf})")
    print(f"data    {dp:6.2f}%  ({dlh}/{dlf})")
    print(f"overall {op:6.2f}%  ({olh}/{olf})")

    ok = True
    if cp < CORE_MIN:
        print(f"FAIL: core {cp:.2f}% < {CORE_MIN}%"); ok = False
    if dp < DATA_MIN:
        print(f"FAIL: data {dp:.2f}% < {DATA_MIN}%"); ok = False
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())

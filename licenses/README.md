# Third-Party Licenses

This directory holds the license texts for third-party components redistributed
as part of iHaveAnnuities. The project itself is **proprietary — all rights
reserved** under a custom Proprietary Software License (see the root
[`LICENSE`](../LICENSE) and [`NOTICE`](../NOTICE)); it is not open source.
The third-party components below remain under their own licenses.

## How this directory is organized

When a third-party dependency whose source or binary is **bundled/redistributed**
in this repository is added, place its full license text here as:

```
licenses/<component-name>-LICENSE.txt
```

and add a row to the inventory below.

## Current inventory

No third-party source or binary code is currently vendored into this repository,
so there are no third-party license files to include yet. The dependencies
below are either linked at build/runtime from upstream sources (pub.dev, the
Flutter SDK) or accessed over HTTP — none of their code is checked into this
repo.

| Component | Role | License | Bundled? | Notes |
| --- | --- | --- | --- | --- |
| Flutter SDK | Framework | BSD-3-Clause | No | Resolved from the installed Flutter toolchain at build time |
| Dart packages (`excel`, `archive`, `xml`, `provider`, `http`, `file_picker`, `file_saver`, `shared_preferences`, `intl`, `cupertino_icons`, `flutter_lints`) | Runtime / dev deps | See each package on pub.dev (mostly BSD/MIT/Apache-2.0) | No | Fetched by `flutter pub get`; not vendored |
| Yahoo Finance chart API | Market-data source | Yahoo terms of use | No | External HTTP endpoint; no code bundled |

> Update this table and add the corresponding `*-LICENSE.txt` file whenever a
> Dart package or other dependency that ships code is vendored into the repo.

# Third-Party Licenses

This directory holds the license texts for third-party components redistributed
as part of iHaveAnnuities. The project itself is licensed under the Apache
License 2.0 (see the root [`LICENSE`](../LICENSE) and [`NOTICE`](../NOTICE)).

## How this directory is organized

When a third-party dependency whose source or binary is **bundled/redistributed**
in this repository is added, place its full license text here as:

```
licenses/<component-name>-LICENSE.txt
```

and add a row to the inventory below.

## Current inventory

No third-party source or binary code is currently vendored into this repository,
so there are no third-party license files to include yet.

| Component | Version | License | Bundled? | Notes |
| --- | --- | --- | --- | --- |
| AnnuityKit | — | Apache-2.0 | First-party | Part of this repo; not third-party |
| Apple SDK frameworks (SwiftUI, SwiftData, Swift Charts, Foundation) | iOS 18+ | Apple SDK License | No | System frameworks linked at runtime, not redistributed |
| Stooq market data | — | Stooq terms of use | No | External HTTP data source; no code bundled |

> Update this table and add the corresponding `*-LICENSE.txt` file whenever a
> Swift Package or other dependency that ships code is introduced.

# Third-Party Licenses

`iHaveAnnuities` is proprietary software (see the root [`LICENSE`](../LICENSE) and
[`NOTICE`](../NOTICE)). It is built on open-source components that remain under
their own licenses.

## Where the notices live

- **Repo:** [`../THIRD_PARTY_NOTICES.txt`](../THIRD_PARTY_NOTICES.txt) — the full
  aggregated set of third-party license texts, **auto-generated** from Flutter's
  own build output so it can never drift from what the app actually ships.
- **In-app:** *About & Disclosures → Open-source licenses* opens Flutter's
  standard `showLicensePage` (the same `LicenseRegistry` data), a list of the
  bundled libraries each with its license text.

## Regenerating

Run before a release (rebuilds web and refreshes the notices file):

```
./scripts/gen_notices.sh
```

This is the Flutter-native equivalent of Android's `oss-licenses-plugin` or
npm's `license-checker`: the framework collects every package's license into the
build's `NOTICES` asset, and the script copies that to `THIRD_PARTY_NOTICES.txt`.

## Market data

The app fetches index levels from the Yahoo Finance chart API (an external HTTP
endpoint governed by Yahoo's terms of use) — no Yahoo code is bundled.

# iHaveAnnuities

Track structured products (annuities) that pay an index-linked return. The
**upside** is the index move — optionally scaled by a **participation rate** and
limited by a **cap** (or uncapped). The **downside** uses one of three protection
types (the tracker's *Floor* column):

1. **Floor** (0%) — no loss in the period; principal protected each reset.
2. **Buffer** (negative, *Hard*) — absorbs the first *X%* of losses; you lose only beyond it.
3. **Barrier** (negative, *Soft*) — fully protected unless the index breaches it, then full loss applies.

**▶ Live app: https://jimzucker.github.io/iHaveAnnuities/** — a Flutter web app
(source in [`app/`](app/)). Load the sample portfolio, or import/export your own
tracker `.xlsx`; index prices refresh daily at 5 PM ET on trading days.

![Overview](docs/overview.png)

## Payoff math

Credited gain on the upside (per reset period):

```
indexReturn  = currentLevel / startLevel − 1
creditedGain = uncapped ? participation × indexReturn
                        : min(cap, participation × indexReturn)
```

Downside depends on the protection type (the tracker's **Floor** column):

```
Floor 0%          → true floor: no loss in the period            payoff = max(0, creditedGain)
Negative + Hard   → buffer: absorbs the first |floor|%, lose 1:1 beyond
                    payoff = indexReturn ≥ 0 ? creditedGain : min(0, indexReturn − floor)
Negative + Soft   → barrier: protected unless breached, then full 1:1 loss
                    payoff = indexReturn ≥ 0 ? creditedGain
                            : (indexReturn ≥ floor ? 0 : indexReturn)

currentValue = principal × (1 + payoff)
```

The numeric difference matters: on a −28% index, a **−20% buffer** loses 8%, but a
**−20% floor** would cap the loss at 20%, while a **−20% soft barrier** (breached)
loses the full 28%.

## Example contracts — $100,000 starting principal

The eight illustrative contracts below match the table in the image above. They
are **modeled on real holdings** but normalized to a **$100,000** principal;
index returns/levels are illustrative (dates/days as of 14‑Jun‑2026). The
`Floor` column is the downside-protection level — *Hard* negative = **buffer**,
*Soft* negative = **barrier**, `0%` = **true floor**. `$` values are in $000s.

| Position (computed) | Index | Cap | Part. | Floor | Type | Reset | Account | Index → Payoff | Proj Value |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Aspida-0%-14Nov28 | SPX | 12.25% | 100% | 0% | Absolute | Annual | Non‑Qual | +18.00% → +12.25% | **$112.25** |
| AXA-15%-18Aug27 | SPX | 65% | 100% | −15% | Hard (buffer) | 6‑Year | Non‑Qual | −22.00% → −7.00% | **$93.00** |
| Citi-15%-04Feb30 | SPX | Uncapped | 102% | −15% | Hard (buffer) | 5‑Year | IRA | +30.00% → +30.60% | **$130.60** |
| HSBC-15%-20Oct30 | NDX | Uncapped | 92.25% | −15% | Hard (buffer) | 5‑Year | IRA | +40.00% → +36.90% | **$136.90** |
| BNP-30%-06Jan31 | SPX | Uncapped | 105% | −30% | Soft (barrier) | 5‑Year | ROTH | −35.00% → −35.00% | **$65.00** |
| Nat. Bank of Canada-30%-16Apr29 | worst‑of SPX/NDX/RUT | 13.25% cpn | 100% | −30% | Soft (barrier) | Monthly | Non‑Qual | +8.47% → +1.12% | **$102.22** |
| AXA-20%-20May32 | NDX | 100% | 100% | −20% | Hard (buffer) | 6‑Year | IRA | −15.00% → 0.00% | **$100.00** |
| Citi-15%-01Dec29 | SPX | Uncapped | 100% | −15% | Hard (buffer) | 4‑Year | ROTH | +12.00% → +12.00% | **$112.00** |
| **Total** | | | | | | | | | **$851.97** |

What each row demonstrates:

- **Aspida** — gain above the 12.25% cap → capped; with a true 0% floor.
- **Axa 65%** — −22% index, −15% **buffer** absorbs 15% → lose only 7%.
- **Citi IRA** — uncapped with **102% participation** → +30% becomes +30.6%.
- **HSBC** — uncapped with **92.25% participation** (<100%) → +40% becomes +36.9%.
- **BNP** — −35% **breaches** the −30% **soft barrier** → full −35% loss.
- **NatBank** — monthly‑coupon **income note** on a **worst‑of** basket; soft −30% barrier.
- **Axa 100%** — −15% index sits **within** the −20% buffer → 0% loss.
- **Citi ROTH** — uncapped, 4‑year reset, modest +12% gain passes through.

### Use-case coverage

These eight cover every distinct case in the real tracker: **downside** — 0% floor,
negative Hard buffer, negative Soft barrier; **cap** — capped + uncapped; **participation**
— <100% / 100% / >100%; **reset** — Annual / Monthly / 4‑Year / 5‑Year / 6‑Year; **index**
— SPX / NDX / RUT / worst‑of; **account** — Non‑Qual / IRA / ROTH; plus a monthly‑coupon
income note alongside the standard indexed annuities.

## App (Flutter)

Cross-platform Flutter app in [`app/`](app/). The portfolio is stored as an
`.xlsx` in the Zucker Annuity Tracker format — import your real spreadsheet, edit,
and export; on web it persists in the browser between visits.

```bash
cd app
flutter pub get
flutter test            # 58 tests; core 100% / data ≥95% coverage gate
flutter run -d chrome   # run the web app locally
```

- **Core** (`lib/core`): payoff engine + model (floor / Hard buffer / Soft barrier,
  participation, capped/uncapped, income notes).
- **Data** (`lib/data`): robust `.xlsx` reader/writer (the tracker schema), market
  feed, and browser-persisted store.
- **Prices**: `data/market.json` is refreshed by a GitHub Action at 5 PM ET on
  trading days (Yahoo Finance, no API key); the web app is published to GitHub Pages.
- The example/template spreadsheets and `docs/overview.png` are all generated from
  `docs/gen_overview.py` (`python3 docs/gen_overview.py`).

## License

Licensed under the **Apache License, Version 2.0** — see [`LICENSE`](LICENSE) and [`NOTICE`](NOTICE).

Third-party license texts (when any code is vendored) live in [`licenses/`](licenses/).

Every source file carries an SPDX header:

```dart
//
//  <file_name>.dart
//  iHaveAnnuities
//
//  Copyright 2026 Jim Zucker
//  SPDX-License-Identifier: Apache-2.0
//
```

Copyright 2026 Jim Zucker.

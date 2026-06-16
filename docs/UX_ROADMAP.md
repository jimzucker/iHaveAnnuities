<!--
Copyright 2026 Jim Zucker
SPDX-License-Identifier: Apache-2.0
-->
# iHaveAnnuities — UX roadmap

Outstanding UX work from the design review, sequenced. Part 1 (column reorder)
is applied consistently across the **screen, the export/import schema, and the
generator**. Re-importing then exporting an existing tracker through the app
converts it to the new order (the importer maps by header name). Later parts are
the remaining review recommendations. Quick-wins (semantic palette, token colors,
units consistency, refresh spinner, web-shell branding) are already shipped.

## Guiding column order (v1.2) — "identity → inputs → outcome → timing → terms"

```
Identity   Position · Issuer · Type · Index · Floor Type
Inputs     Initial $ · Realized $
Outcome    Proj Value $ · Proj $ Gain $ · Proj Gain % · Index Gain %
Timing     Next Reset · Days to Reset · Maturity · Days to Maturity        ← monitor
Terms      CAP · Part. · Floor · Strike · Reset Freq · Open · Last Reset    ← static
Worst-of   NDX_Strike · RUT_Strike
```

Rationale: identity first; then **Initial sits next to Proj Value** so "what I
put in → what it's worth" reads left-to-right; the **monitor** columns (the
reset/maturity countdowns you actively scan) come before the **static** terms
(set-once contract params + inception dates) you rarely re-read. `Reset Freq`
stays in Terms (it's fixed at inception). The on-screen table uses this order
minus `Position` and the worst-of strikes.

> v1.1 (identity → outcome → terms → schedule → inputs) shipped first; v1.2
> refines it by lifting Inputs next to Outcome and splitting monitor-vs-static
> dates. Same 24/21 columns, same name-mapped import.

---

## Part 1 — Apply the reorder everywhere (schema v1.1)

1. **Screen** (`app/lib/ui/portfolio_table.dart`): reorder the `_Col` list to the
   guiding order above. Update `defaultSortColumn` (Next Reset moves index) and
   any tests that assert column index (`tapping a column header changes the sort`).
2. **Export/import schema** (`app/lib/data/tracker_xlsx.dart`): reorder the
   `headers` const to v1.1 — `Position` stays column A (the row label),
   `NDX_Strike`/`RUT_Strike` stay last; the middle reflows to the guiding order.
   Reorder the `writeTracker` cell list to match. **Import is unchanged** (it maps
   by header name), so v1.0 files — including your real tracker — keep loading;
   add a v1.1 round-trip test and keep the v1.0-compat test.
3. **Generator** (`docs/gen_overview.py`): reorder `HEADERS` + the row dict
   emission + the `overview.html`/`_style_sheet` columns to v1.1, then regenerate
   `data/example-portfolio.xlsx`, `data/template.xlsx`, `app/assets/*` copies, and
   `docs/overview.png`. (Keeps picture, README table, sample, and test fixture in
   lockstep — as today.)
4. **Docs**: bump the schema note to v1.1 in `tracker_xlsx.dart` header comment and
   the README/`ihaveannuities_schema_v1` memory.
5. **Verify**: `flutter analyze` + `flutter test` (reorder-affected tests),
   `python3 docs/gen_overview.py`, re-import the regenerated example + your real
   file (confirming v1.0 → v1.1 conversion via import→export), build web, deploy.

## Part 2 — Additional reference indices (Dow, Nasdaq Composite)

Today the app tracks **SPX** (S&P 500), **NDX** (Nasdaq-100), and **RUT**
(Russell 2000). Add **Dow Jones Industrial Average** (`^DJI`) and the **Nasdaq
Composite** (`^IXIC`) so holdings can reference them and the header shows them.

1. **Fetcher** (`scripts/fetch_market.py`): fetch `^DJI` and `^IXIC` alongside the
   existing three; write `dow` and `comp` into `data/market.json`
   (`{asOf, tradingDay, spx, ndx, rut, dow, comp}`).
2. **Model** (`app/lib/data/market.dart`): parse the new fields, extend
   `priceFor`/`bySymbol` with `DJI` / `COMP`; default missing fields to null so old
   `market.json` still loads.
3. **Index mapping** (`app/lib/core/models.dart` `baseIndex`): map `DJI`/`DOW` →
   `DJI` and `COMP`/`IXIC` (distinct from `NDX`) so a holding priced off the Dow or
   Nasdaq Composite revalues correctly. Keep the worst-of check first.
4. **Prices header** (`portfolio_screen.dart` `_PricesHeader`): add `Dow` and
   `Nasdaq Comp` quotes (wraps responsively).
5. **Schema vocab**: allow `^DJI` / `^IXIC` (and friendly `DJI`/`COMP`) in the
   `Index` column; document in the schema note + form's index choices.
6. **Tests**: market JSON (de)serialization with the new fields + a null-safe old
   payload; `baseIndex` cases for Dow/Composite; fetcher parse (mocked).

## Part 3 — Table readability

- Freeze the **Issuer** column so identity never scrolls off (horizontal-scroll
  the rest).
- **Zebra striping** on rows for easier scanning.
- **Simple / Full** view toggle: Simple = Issuer · Type · Index · Floor Type ·
  Proj Value $ · Proj Gain %; Full = all columns. Remember the choice (like sort).

## Part 4 — Portfolio hero (engagement)

A summary band above the table:
- **Protection mix donut** — principal split across Protected / Hard / Soft.
- **Projected gain bar** — green/red, vs. principal.
- **Next-reset timeline strip** — upcoming resets using existing `daysToReset`.

## Part 5 — Accessibility & theming

- **Colorblind-safe** gain/loss: add a ▲/▼ glyph alongside color (`format.dart`).
- **Dark mode**: `darkTheme` from the same seed + `themeMode` (now cheap since
  colors are tokenized).
- **Chart semantics**: wrap `PayoffChart` in `Semantics(label: …)`; bump the
  smallest 11px labels for contrast/readability.

## Part 6 — Mobile responsive

Below a width breakpoint, render holdings as **cards** (detail `_Section` style)
instead of the 20-column horizontal scroll.

## Part 7 — Motion & brand polish

- Subtle shared-axis transition into the detail view; count-up on summary figures.
- A real **logo / PWA icon** (replace the default Flutter favicon + `icons/*`).

---

### Status
- [x] Part 1 — reorder (screen + schema v1.1 + generator) — shipped
- [x] Part 2 — additional reference indices (Dow, Nasdaq Composite) — shipped
- [ ] Part 3 — table readability
- [ ] Part 4 — portfolio hero
- [ ] Part 5 — accessibility & theming
- [ ] Part 6 — mobile responsive
- [ ] Part 7 — motion & brand polish

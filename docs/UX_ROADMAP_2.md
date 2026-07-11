<!--
Copyright 2026 Jim Zucker
SPDX-License-Identifier: LicenseRef-Proprietary
-->
# UX roadmap — round 2 (drilldown + controls)

Follow-up review after the v1.2 table work. Grouped by area; each part is
independent so we can pick and choose. Nothing here changes the calc.

## Part A — Drilldown (detail screen)

1. **Unit consistency.** The key-figures banner shows full dollars
   (`$282,203`) but the **Values** card shows `$000` (`$282.20`). Make the
   Values card full-dollar too and drop the `($000)` from its title — one
   convention on screen (the `.xlsx` keeps `$000`). (`holding_detail.dart`)
2. **Kill the duplicate.** `Index gain` appears in both the banner and the
   Levels card. Drop it from the banner and put a **status chip** there
   instead — `Protected` / `Hard` / `Soft`, and `Cap reached` / `Room to cap`
   (reuse `gainStatus` + `protectionPalette`). (`holding_detail.dart`)
3. **Terminology.** Rename the banner/Values "Proj $ gain" → **Unrealized $**
   to match the table + hero.
3b. **Tooltip wording (industry standard).** Reword the cap tooltips: the
   current "Cap reached — upside ceilinged at 10.00%" → **"10.00% cap
   reached"**, and the room-left tooltip → **"Below the 10.00% cap"** /
   "room to the 10.00% cap". Sweep all tooltips for plain, standard phrasing.
4. **Payoff chart upgrade** (`payoff_chart.dart`) — the biggest win:
   - Axis **tick labels** (index move % on x, payoff % on y) and faint
     gridlines.
   - **Reference lines**: strike (0%), the **cap** ceiling, and the
     **floor/buffer/barrier** level — each lightly labeled.
   - **Label the current point** with its (index %, payoff %) instead of a
     bare dot.
   - **Tighten the y-range** to the meaningful band so the line isn't lost in
     empty space.
   - Optional: tap/drag to read the payoff at any index move (a value readout).

## Part B — App-bar controls

5. **Hide the compact-columns toggle on phones.** In card mode it does
   nothing; only show it when the wide table is visible (width ≥ 720, via
   `MediaQuery`). (`portfolio_screen.dart`)
6. **Make "hide summary" intuitive.** Replace the cryptic `unfold` app-bar
   icon with a **collapsible "Summary" header** on the band itself — a thin
   tappable strip with a chevron (`Summary ⌄ / ⌃`) directly above the quotes +
   hero. Discoverable, labeled, and the chevron clearly implies collapse.
   Remove the app-bar icon. (`portfolio_screen.dart`)

## Part C — Other suggestions

7. **Countdown affordance.** Show "Next reset" / "Maturity" as a subtle
   progress indicator or relative phrasing ("in 325 days") in the detail
   Schedule card.
8. **Wide-screen drilldown.** The four section cards are fixed 320px in a
   Wrap; on a wide window they leave a ragged right edge. Let them flex to fill
   evenly (2×2 grid that stretches).
9. **Consistent "Unrealized" wording** everywhere (table, hero, detail, export
   header) so the same number always has the same name.
10. **Chart legend.** A one-line legend (payoff curve vs. the faint
    unclamped-index reference) so the two lines are self-explanatory.

## Part D — Index history charts (drill down from the quotes)

Tap a quote in the header (S&P 500 / Dow / Nasdaq Comp / Nasdaq-100 / Russell)
to open a price chart with range toggles: **1D · 1W · 1M · YTD · 1Y · 2Y · Max**.

**Architecture (important):** the browser can't call Yahoo directly (CORS), and
the app is static on Pages — so the **daily GitHub Action fetches the history
server-side** and writes public JSON the app loads same-origin (same pattern as
`market.json`):

- `scripts/fetch_market.py` (or a new `fetch_history.py`) pulls each index's
  series from the Yahoo chart API and writes `data/history-<sym>.json`
  (`{sym, asOf, points:[{t, c}]}`). Daily closes back ~2-5Y cover 1M/YTD/1Y/2Y/
  Max; for 1D/1W, fetch a short intraday series (`interval=5m,range=5d`) into the
  same file (or a sibling) so the short ranges aren't just 1-2 daily dots.
- New `IndexChartScreen` with a `SegmentedButton` range selector and a
  CustomPaint line chart (reuse the payoff-chart drawing helpers): min/max
  labels, last price + % change for the selected range, gridlines.
- Header quotes become tappable (`InkWell`) → push the chart for that symbol.
- The deploy step already copies `data/*.json`; extend it to copy the history
  files. Tests: history JSON (de)serialization + range filtering (pure).

Caveats: history files add weight to the deploy (keep to daily closes + one
short intraday window). Yahoo intraday is delayed; fine for a tracker. If we
want only the simple version first, ship daily-close ranges (1M→Max) and add
1D/1W intraday later.

## Suggested order
- **B (controls)** first — small, high-friction fixes (dead toggle, confusing
  collapse).
- **A1–A3** — quick consistency wins on the detail screen.
- **A4** — the chart upgrade (the meatiest, most visible improvement).
- **C** — polish.

### Status
- [ ] A1 unit consistency  · [ ] A2 status chip / dedupe · [ ] A3 unrealized label
- [ ] A4 chart upgrade
- [ ] B5 hide compact on phone · [ ] B6 collapsible summary header
- [ ] C7 countdown · [ ] C8 wide grid · [ ] C9 wording · [ ] C10 legend

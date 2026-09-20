<!--
  TAX_TREATMENT_DESIGN.md — design proposal (not yet implemented)
  Copyright 2026 Jim Zucker
  SPDX-License-Identifier: LicenseRef-Proprietary
-->

# Surfacing tax implications

## Goal

Show the user the **tax character** of each holding and of the portfolio as a
whole — informationally, not as advice. No brackets, no rates, no after-tax
projection. The app should answer "which of my positions are tax-deferred,
tax-free, or throwing off taxable income *now*?" and stop there.

## The core insight: it's a 2×3 matrix, and the wrapper dominates

Tax character is a function of two axes:

- **Account wrapper** — already modelled: `enum AccountType { nonQual, ira, roth }`
  (`lib/core/models.dart:12`). "Qualified" = IRA today, and 401(k) when the
  parked enum add lands.
- **Product type** — *not* modelled yet. Annuity contract vs. brokerage-held
  structured note. (`isIncomeNote` is **orthogonal** — it describes payoff shape,
  not the tax wrapper, so it can't stand in for this.)

|  Account ↓ / Product → | **Annuity** | **Structured note** |
| --- | --- | --- |
| **Qualified** (IRA / 401k) | Tax-deferred; withdrawals = ordinary income; RMDs; 10% penalty pre-59½ | **Same** — the wrapper controls; the note's internal coupons/OID are invisible for tax |
| **Roth** | Qualified withdrawals tax-free; no RMDs for the owner | **Same** — the wrapper controls |
| **Non-Qual** (taxable) | Tax-deferred; gains-first (LIFO) ordinary income on withdrawal; penalty pre-59½ | **Taxed as you go** — coupons ordinary income annually; possible OID / phantom accrual; ordinary-vs-cap-gain per the note's terms |

Two consequences drive the whole design:

1. **In Qualified and Roth, annuity-vs-note is tax-neutral.** Four of the six
   cells collapse to "the wrapper decides." Product type only *ever* changes the
   answer in the **Non-Qual** row.
2. **The one cell that surprises people is Non-Qual + structured note** — it can
   generate **annual taxable income** (coupons / OID) that none of the deferred
   buckets do. That single cell is the thing most worth flagging visually.

So the derived tax character reduces to three buckets:
**Tax-deferred**, **Tax-free**, **Taxable now**.

## Approach (minimum: one field + one function + three placements)

### 1. New data: product type — `lib/core/models.dart`

- Add `enum ProductType { annuity, structuredNote }` with a `.label`
  ("Annuity" / "Structured Note"), mirroring `AccountType` (models.dart:12–36).
- Add `final ProductType productType;` to `Holding`, **defaulting to
  `ProductType.annuity`** in the constructor and in `fromJson`/`copyWith` so
  every existing holding and cache round-trips unchanged (the historical
  assumption — the app was annuities-only).

### 2. New derived getter: `taxTreatment` — `lib/core/models.dart`

A pure function next to the other derived getters (~models.dart:128):

```dart
enum TaxTreatment { deferred, taxFree, taxableNow }

TaxTreatment get taxTreatment => switch (account) {
      AccountType.roth => TaxTreatment.taxFree,
      AccountType.ira => TaxTreatment.deferred,            // + 401k when added
      AccountType.nonQual => productType == ProductType.structuredNote
          ? TaxTreatment.taxableNow
          : TaxTreatment.deferred,
    };
```

Plus a one-line human description per `(account, productType)` cell for the
drill-down (a small `const` map or switch — the six strings from the matrix
above). No numbers, no assumptions → trivially unit-testable.

### 3. Import / export — `lib/data/tracker_xlsx.dart`

- Add a `"Product Type"` column to the schema (a schema-version bump). Parse it
  with an `_productType()` helper mirroring `_account()` (tracker_xlsx.dart:99);
  **a missing/blank column defaults to `annuity`** so older tracker files and
  the current example fixtures import unchanged.
- Emit it on export alongside `Type` (account).
- Regenerate the fixtures from `docs/gen_overview.py` (the single source for both
  xlsx twins + `overview.html`), tagging a couple of the example rows as
  `Structured Note` so the sample demonstrates the taxable-now bucket.

### 4. Surface it — three cheap placements

- **Drill-down** (`lib/ui/holding_detail.dart`): one line — the tax-character
  description for that holding's cell (e.g. "Non-Qual structured note — may
  generate annual taxable income; withdrawals/coupons taxed as ordinary income").
- **A badge** on holdings in the **taxable-now** cell only — a small chip
  ("Taxable now") next to the account, since that's the actionable surprise. The
  deferred/tax-free majority stay unadorned to avoid noise.
- **Grouping band** — add `'Tax'` to `groupDimensions`
  (`lib/data/portfolio_store.dart:134`) and a case to `groupValueOf`
  (`lib/ui/portfolio_table.dart:454`) returning the `TaxTreatment` label, so the
  existing pivot/subtotal engine rolls the portfolio into Tax-deferred /
  Tax-free / Taxable-now buckets with totals. (Needs a `columnIndexForDimension`
  mapping like the other dims — portfolio_table.dart:450; simplest is to sort the
  band by the account column it derives from.) This also flows into the exported
  report for free, since the report mirrors the on-screen grouping.

### 5. Disclaimer — already present

`lib/ui/info_page.dart:135` already reads *"Not financial, investment, tax, or
legal advice…"*. Reuse it; optionally add a one-liner near the tax badge/line
pointing back to it. No new legal surface needed.

### 6. Version — `app/pubspec.yaml`

Patch bump on the feature branch, per the standing versioning rule.

## What we deliberately will NOT build

- **No per-note OID / CPDI accrual or ordinary-vs-cap-gain characterization.**
  That lives in each issuer's tax opinion; guessing it would be wrong and
  high-maintenance. The badge points the user to the note's own tax summary — it
  does not compute phantom income.
- **No after-tax calculator** (bracket / state → net value). That is personalized
  tax advice and assumption-heavy; out of scope by policy.
- **No RMD scheduling / penalty math.** Mentioned in the description text only.

## Tests

- **Core** — `taxTreatment` for all six `(account, productType)` cells; the
  description string for each; default `productType == annuity` when unspecified.
- **Data** — `_productType()` parses "Structured Note"/"Annuity"/blank; a missing
  column defaults to annuity (backward-compat regression guard); export→import
  round-trips the field.
- **Widget** — the "Taxable now" badge shows only on Non-Qual structured notes
  and nowhere else; grouping by `Tax` produces the three bands with correct
  membership.
- Coverage gate holds (core 100% / data ≥95%).

## Open question (gates step 3)

Do the holdings already carry anything that distinguishes an annuity from a
brokerage note, or is a **new `Product Type` field** the right call? The design
above assumes the latter (new field, defaulting to annuity). If the tracker
already encodes it somewhere, step 3 changes from "add a column" to "map an
existing one."

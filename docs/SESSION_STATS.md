# Build session story

The real numbers behind building **iHaveAnnuities**, pulled from this project's Claude Code session transcript (2,299 records spanning the whole build). Regenerate with `python3 scripts/session_stats.py --md`.

## Tokens

| Category | Tokens |
| --- | ---: |
| Output (generated) | 1,206,672 |
| Input (uncached) | 214,246 |
| Cache write | 1,792,013 |
| Cache read | 257,835,092 |
| **Grand total** | **~261.0 M** |

The total is dominated by **cache reads (~258 M)** — that's the growing conversation/codebase context being re-read on each of 906 assistant turns, billed at the cheap cached rate, not 258 M of fresh work. The number that reflects actual **produced content is ~1.21 M output tokens**.

## Prompts

- **~45 prompts you typed** (out of 496 raw "user" records — the rest are tool results, slash-command stdout, and system reminders).
- **906 assistant turns** in response (each prompt fans out into many tool-call/reasoning steps).

## Time

Session ran **Jun 14 10:05 AM → Jun 15 10:19 PM EDT** wall-clock, but that includes **~33 h of idle gaps** (overnight, breaks). Counting only stretches with <5-min gaps between events:

- **Active session: ~3h 42m 46s**
  - **Claude working** (tool calls, builds, tests, writing): ~2h 14m 47s
  - **You prompting / reading**: ~1h 27m 59s

| Metric | Value |
| --- | --- |
| Session start | 2026-06-14 10:05 EDT |
| Session end | 2026-06-15 22:19 EDT |
| Active (gaps <5m) | 3h 42m 46s |
| &nbsp;&nbsp;Claude working | 2h 14m 47s |
| &nbsp;&nbsp;User prompting | 1h 27m 59s |
| Idle (excluded) | 32h 30m 46s |

## Cost

What this would cost on the **metered Claude API**, using Opus 4.x standard rates (USD per million tokens). These rates are assumptions — verify against current pricing; the total scales linearly with the cache-read rate, which dominates.

| Token type | Rate / M | Tokens | Cost |
| --- | ---: | ---: | ---: |
| Output | $75.00 | 1,206,672 | $90.50 |
| Input (uncached) | $15.00 | 214,246 | $3.21 |
| Cache write | $18.75 | 1,792,013 | $33.60 |
| Cache read | $1.50 | 257,835,092 | $386.75 |
| **Total** | | | **≈ $514** |

**Prompt caching saved ~$3,481.** Those 258 M cache reads, if billed as normal input tokens ($15/M), would have been **~$3,868** instead of **$387** — a 10× discount, and the single biggest cost lever.

**At work this usually isn't metered API.** Most teams run Claude Code on a flat **subscription** (Max ~$100–200/mo), where this build is effectively included; the ~$514 above is the equivalent à-la-carte value, useful for ROI math but not what most orgs pay.

**ROI framing.** A from-scratch Flutter app — payoff engine, custom `.xlsx` reader/writer, 60+ tests with a CI coverage gate, Pages deploy, and a market-data cron — is realistically **3–10 engineer-days**. At ~$800/loaded-day that's **$2,400–$8,000** of labor, so even the metered ~$514 (or a month of subscription) is roughly **5–15× cheaper** than the equivalent hands-on time.

## Caveats

- All from **1 transcript file**, which cover the whole project — both the pre-compaction work and the continued sessions — not just any single feature.
- **"User prompting" time is approximated** as the gap before each of your messages (composing + reading my output), so it bundles your think-time with reading time.
- **Token counts come straight from the `usage` field** on each assistant message; **timing from event timestamps**.
- **Costs are estimates** at the assumed Opus 4.x rates above; the labor comparison is a rough industry figure, not a measured one.

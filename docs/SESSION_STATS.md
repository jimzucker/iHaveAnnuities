# Build session story

The real numbers behind building **iHaveAnnuities**, pulled from this project's Claude Code session transcript (11,411 records spanning the whole build). Regenerate with `python3 scripts/session_stats.py --md`.

## Tokens

| Category | Tokens |
| --- | ---: |
| Output (generated) | 5,679,501 |
| Input (uncached) | 627,701 |
| Cache write | 28,569,925 |
| Cache read | 1,933,012,099 |
| **Grand total** | **~1967.9 M** |

The total is dominated by **cache reads (~1933 M)** — that's the growing conversation/codebase context being re-read on each of 4,469 assistant turns, billed at the cheap cached rate, not 1933 M of fresh work. The number that reflects actual **produced content is ~5.68 M output tokens**.

## Prompts

- **~212 prompts you typed** (out of 2,462 raw "user" records — the rest are tool results, slash-command stdout, and system reminders).
- **4,469 assistant turns** in response (each prompt fans out into many tool-call/reasoning steps).

## Time

Session ran **Jun 14 10:05 AM → Jun 24 5:26 AM EDT** wall-clock, but that includes **~217 h of idle gaps** (overnight, breaks). Counting only stretches with <5-min gaps between events:

- **Active session: ~18h 31m 29s**
  - **Claude working** (tool calls, builds, tests, writing): ~11h 43m 18s
  - **You prompting / reading**: ~6h 48m 10s

| Metric | Value |
| --- | --- |
| Session start | 2026-06-14 10:05 EDT |
| Session end | 2026-06-24 05:26 EDT |
| Active (gaps <5m) | 18h 31m 29s |
| &nbsp;&nbsp;Claude working | 11h 43m 18s |
| &nbsp;&nbsp;User prompting | 6h 48m 10s |
| Idle (excluded) | 216h 49m 39s |

## Cost

What this would cost on the **metered Claude API**, at Anthropic's official **Opus 4.8** rates (USD per million tokens — input $5, output $25, 5-min cache write $6.25, cache read $0.50; [source](https://platform.claude.com/docs/en/about-claude/pricing), verified 2026-06). The total scales linearly with the cache-read rate, which dominates; override with `--rate-*` for other models.

| Token type | Rate / M | Tokens | Cost |
| --- | ---: | ---: | ---: |
| Output | $25.00 | 5,679,501 | $141.99 |
| Input (uncached) | $5.00 | 627,701 | $3.14 |
| Cache write | $6.25 | 28,569,925 | $178.56 |
| Cache read | $0.50 | 1,933,012,099 | $966.51 |
| **Total** | | | **≈ $1,290** |

**Prompt caching saved ~$8,699.** Those 1933 M cache reads, if billed as normal input tokens ($5/M), would have been **~$9,665** instead of **$967** — a 10× discount, and the single biggest cost lever.

**At work this usually isn't metered API.** Most teams run Claude Code on a flat **subscription** (Max ~$100–200/mo), where this build is effectively included; the ~$1,290 above is the equivalent à-la-carte value, useful for ROI math but not what most orgs pay.

**ROI framing.** A from-scratch Flutter app — payoff engine, custom `.xlsx` reader/writer, 60+ tests with a CI coverage gate, Pages deploy, and a market-data cron — is realistically **3–10 engineer-days**. At ~$800/loaded-day that's **$2,400–$8,000** of labor, so even the metered ~$1,290 (or a month of subscription) is roughly **2–6× cheaper** than the equivalent hands-on time.

## Caveats

- All from **1 transcript file**, which cover the whole project — both the pre-compaction work and the continued sessions — not just any single feature.
- **"User prompting" time is approximated** as the gap before each of your messages (composing + reading my output), so it bundles your think-time with reading time.
- **Token counts come straight from the `usage` field** on each assistant message; **timing from event timestamps**.
- **Costs use Anthropic's official Opus 4.8 rates** ([pricing docs](https://platform.claude.com/docs/en/about-claude/pricing), verified 2026-06); the labor comparison is a rough industry figure, not a measured one.

# Build session story

The real numbers behind building **iHaveAnnuities**, pulled from this project's Claude Code session transcript (5,836 records spanning the whole build). Regenerate with `python3 scripts/session_stats.py --md`.

## Tokens

| Category | Tokens |
| --- | ---: |
| Output (generated) | 3,059,550 |
| Input (uncached) | 395,336 |
| Cache write | 6,035,221 |
| Cache read | 933,281,457 |
| **Grand total** | **~942.8 M** |

The total is dominated by **cache reads (~933 M)** — that's the growing conversation/codebase context being re-read on each of 2,308 assistant turns, billed at the cheap cached rate, not 933 M of fresh work. The number that reflects actual **produced content is ~3.06 M output tokens**.

## Prompts

- **~85 prompts you typed** (out of 1,258 raw "user" records — the rest are tool results, slash-command stdout, and system reminders).
- **2,308 assistant turns** in response (each prompt fans out into many tool-call/reasoning steps).

## Time

Session ran **Jun 14 10:05 AM → Jun 16 3:30 PM EDT** wall-clock, but that includes **~44 h of idle gaps** (overnight, breaks). Counting only stretches with <5-min gaps between events:

- **Active session: ~8h 59m 9s**
  - **Claude working** (tool calls, builds, tests, writing): ~5h 41m 59s
  - **You prompting / reading**: ~3h 17m 10s

| Metric | Value |
| --- | --- |
| Session start | 2026-06-14 10:05 EDT |
| Session end | 2026-06-16 15:30 EDT |
| Active (gaps <5m) | 8h 59m 9s |
| &nbsp;&nbsp;Claude working | 5h 41m 59s |
| &nbsp;&nbsp;User prompting | 3h 17m 10s |
| Idle (excluded) | 44h 25m 32s |

## Cost

What this would cost on the **metered Claude API**, at Anthropic's official **Opus 4.8** rates (USD per million tokens — input $5, output $25, 5-min cache write $6.25, cache read $0.50; [source](https://platform.claude.com/docs/en/about-claude/pricing), verified 2026-06). The total scales linearly with the cache-read rate, which dominates; override with `--rate-*` for other models.

| Token type | Rate / M | Tokens | Cost |
| --- | ---: | ---: | ---: |
| Output | $25.00 | 3,059,550 | $76.49 |
| Input (uncached) | $5.00 | 395,336 | $1.98 |
| Cache write | $6.25 | 6,035,221 | $37.72 |
| Cache read | $0.50 | 933,281,457 | $466.64 |
| **Total** | | | **≈ $583** |

**Prompt caching saved ~$4,200.** Those 933 M cache reads, if billed as normal input tokens ($5/M), would have been **~$4,666** instead of **$467** — a 10× discount, and the single biggest cost lever.

**At work this usually isn't metered API.** Most teams run Claude Code on a flat **subscription** (Max ~$100–200/mo), where this build is effectively included; the ~$583 above is the equivalent à-la-carte value, useful for ROI math but not what most orgs pay.

**ROI framing.** A from-scratch Flutter app — payoff engine, custom `.xlsx` reader/writer, 60+ tests with a CI coverage gate, Pages deploy, and a market-data cron — is realistically **3–10 engineer-days**. At ~$800/loaded-day that's **$2,400–$8,000** of labor, so even the metered ~$583 (or a month of subscription) is roughly **4–14× cheaper** than the equivalent hands-on time.

## Caveats

- All from **1 transcript file**, which cover the whole project — both the pre-compaction work and the continued sessions — not just any single feature.
- **"User prompting" time is approximated** as the gap before each of your messages (composing + reading my output), so it bundles your think-time with reading time.
- **Token counts come straight from the `usage` field** on each assistant message; **timing from event timestamps**.
- **Costs use Anthropic's official Opus 4.8 rates** ([pricing docs](https://platform.claude.com/docs/en/about-claude/pricing), verified 2026-06); the labor comparison is a rough industry figure, not a measured one.

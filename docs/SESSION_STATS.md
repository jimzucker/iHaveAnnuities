# Build session story

The real numbers behind building **iHaveAnnuities**, pulled from this project's Claude Code session transcript (2,372 records spanning the whole build). Regenerate with `python3 scripts/session_stats.py --md`.

## Tokens

| Category | Tokens |
| --- | ---: |
| Output (generated) | 1,218,643 |
| Input (uncached) | 216,362 |
| Cache write | 2,003,486 |
| Cache read | 260,762,690 |
| **Grand total** | **~264.2 M** |

The total is dominated by **cache reads (~261 M)** — that's the growing conversation/codebase context being re-read on each of 934 assistant turns, billed at the cheap cached rate, not 261 M of fresh work. The number that reflects actual **produced content is ~1.22 M output tokens**.

## Prompts

- **~46 prompts you typed** (out of 513 raw "user" records — the rest are tool results, slash-command stdout, and system reminders).
- **934 assistant turns** in response (each prompt fans out into many tool-call/reasoning steps).

## Time

Session ran **Jun 14 10:05 AM → Jun 16 6:09 AM EDT** wall-clock, but that includes **~40 h of idle gaps** (overnight, breaks). Counting only stretches with <5-min gaps between events:

- **Active session: ~3h 45m 13s**
  - **Claude working** (tool calls, builds, tests, writing): ~2h 16m 40s
  - **You prompting / reading**: ~1h 28m 32s

| Metric | Value |
| --- | --- |
| Session start | 2026-06-14 10:05 EDT |
| Session end | 2026-06-16 06:09 EDT |
| Active (gaps <5m) | 3h 45m 13s |
| &nbsp;&nbsp;Claude working | 2h 16m 40s |
| &nbsp;&nbsp;User prompting | 1h 28m 32s |
| Idle (excluded) | 40h 19m 14s |

## Cost

What this would cost on the **metered Claude API**, at Anthropic's published **Opus 4.8** rates (USD per million tokens, current as of 2026-06). The total scales linearly with the cache-read rate, which dominates; override with `--rate-*` for other models.

| Token type | Rate / M | Tokens | Cost |
| --- | ---: | ---: | ---: |
| Output | $25.00 | 1,218,643 | $30.47 |
| Input (uncached) | $5.00 | 216,362 | $1.08 |
| Cache write | $6.25 | 2,003,486 | $12.52 |
| Cache read | $0.50 | 260,762,690 | $130.38 |
| **Total** | | | **≈ $174** |

**Prompt caching saved ~$1,173.** Those 261 M cache reads, if billed as normal input tokens ($5/M), would have been **~$1,304** instead of **$130** — a 10× discount, and the single biggest cost lever.

**At work this usually isn't metered API.** Most teams run Claude Code on a flat **subscription** (Max ~$100–200/mo), where this build is effectively included; the ~$174 above is the equivalent à-la-carte value, useful for ROI math but not what most orgs pay.

**ROI framing.** A from-scratch Flutter app — payoff engine, custom `.xlsx` reader/writer, 60+ tests with a CI coverage gate, Pages deploy, and a market-data cron — is realistically **3–10 engineer-days**. At ~$800/loaded-day that's **$2,400–$8,000** of labor, so even the metered ~$174 (or a month of subscription) is roughly **14–46× cheaper** than the equivalent hands-on time.

## Caveats

- All from **1 transcript file**, which cover the whole project — both the pre-compaction work and the continued sessions — not just any single feature.
- **"User prompting" time is approximated** as the gap before each of your messages (composing + reading my output), so it bundles your think-time with reading time.
- **Token counts come straight from the `usage` field** on each assistant message; **timing from event timestamps**.
- **Costs use Anthropic's published Opus 4.8 rates** (current as of 2026-06); the labor comparison is a rough industry figure, not a measured one.

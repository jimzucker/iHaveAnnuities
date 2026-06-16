# Build session story

The real numbers behind building **iHaveAnnuities**, pulled from this project's Claude Code session transcript (2,243 records spanning the whole build). Regenerate with `python3 scripts/session_stats.py --md`.

## Tokens

| Category | Tokens |
| --- | ---: |
| Output (generated) | 1,192,020 |
| Input (uncached) | 213,220 |
| Cache write | 1,778,919 |
| Cache read | 255,878,715 |
| **Grand total** | **~259.1 M** |

The total is dominated by **cache reads (~256 M)** — that's the growing conversation/codebase context being re-read on each of 886 assistant turns, billed at the cheap cached rate, not 256 M of fresh work. The number that reflects actual **produced content is ~1.19 M output tokens**.

## Prompts

- **~43 prompts you typed** (out of 482 raw "user" records — the rest are tool results, slash-command stdout, and system reminders).
- **886 assistant turns** in response (each prompt fans out into many tool-call/reasoning steps).

## Time

Session ran **Jun 14 10:05 AM → Jun 15 10:13 PM EDT** wall-clock, but that includes **~33 h of idle gaps** (overnight, breaks). Counting only stretches with <5-min gaps between events:

- **Active session: ~3h 36m 50s**
  - **Claude working** (tool calls, builds, tests, writing): ~2h 12m 41s
  - **You prompting / reading**: ~1h 24m 9s

| Metric | Value |
| --- | --- |
| Session start | 2026-06-14 10:05 EDT |
| Session end | 2026-06-15 22:13 EDT |
| Active (gaps <5m) | 3h 36m 50s |
| &nbsp;&nbsp;Claude working | 2h 12m 41s |
| &nbsp;&nbsp;User prompting | 1h 24m 9s |
| Idle (excluded) | 32h 30m 46s |

## Caveats

- All from **1 transcript file**, which cover the whole project — both the pre-compaction work and the continued sessions — not just any single feature.
- **"User prompting" time is approximated** as the gap before each of your messages (composing + reading my output), so it bundles your think-time with reading time.
- **Token counts come straight from the `usage` field** on each assistant message; **timing from event timestamps**.

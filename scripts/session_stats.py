#!/usr/bin/env python3
# Copyright 2026 Jim Zucker
# SPDX-License-Identifier: Apache-2.0
"""Summarize Claude Code session transcripts for this repo.

Reports token usage, prompt/turn counts, and active vs. idle time by parsing
the JSONL transcript(s) Claude Code stores under
``~/.claude/projects/<encoded-repo-path>/``.

Usage:
    python3 scripts/session_stats.py            # all transcripts for this repo
    python3 scripts/session_stats.py FILE.jsonl # a specific transcript
    python3 scripts/session_stats.py --idle 10  # idle gap threshold in minutes
"""
from __future__ import annotations

import argparse
import datetime as dt
import glob
import json
import os
import sys

# Gaps longer than this (minutes) count as idle, not active work.
DEFAULT_IDLE_MIN = 5


def transcript_dir_for(repo_path: str) -> str:
    """Claude Code encodes the repo path by replacing '/' with '-'."""
    encoded = repo_path.replace("/", "-")
    return os.path.expanduser(f"~/.claude/projects/{encoded}")


def find_transcripts(args_paths: list[str]) -> list[str]:
    if args_paths:
        return args_paths
    repo = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
    d = transcript_dir_for(repo)
    files = sorted(glob.glob(os.path.join(d, "*.jsonl")))
    if not files:
        sys.exit(f"No transcripts found in {d}")
    return files


def load(path: str) -> list[dict]:
    rows = []
    with open(path) as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                rows.append(json.loads(line))
            except json.JSONDecodeError:
                pass
    return rows


def parse_ts(r: dict):
    t = r.get("timestamp")
    if not t:
        return None
    try:
        return dt.datetime.fromisoformat(t.replace("Z", "+00:00"))
    except ValueError:
        return None


def is_human_prompt(r: dict) -> bool:
    """A message the user actually typed (not a tool result / slash-command)."""
    if r.get("type") != "user" or r.get("isMeta"):
        return False
    content = r.get("message", {}).get("content")
    if isinstance(content, list):
        for b in content:
            if isinstance(b, dict) and b.get("type") == "tool_result":
                return False
        text = " ".join(b.get("text", "") for b in content if isinstance(b, dict))
    elif isinstance(content, str):
        text = content
    else:
        return False
    if not text.strip():
        return False
    markers = ("<local-command", "<command-name>", "command-message")
    if any(m in text for m in markers):
        return False
    if "Caveat:" in text and len(text) < 400:
        return False
    return True


def hms(td: dt.timedelta) -> str:
    s = int(td.total_seconds())
    return f"{s // 3600}h {s % 3600 // 60}m {s % 60}s"


def write_markdown(path, files, n_rows, outp, inp, cc, cr, total, prompts,
                   turns, events, active, claude, user, idle, idle_min,
                   n_user_records) -> None:
    """Write the full narrative report — the story, not just the tables."""
    cr_m = cr / 1e6
    out_m = outp / 1e6
    total_m = total / 1e6
    lines = [
        "# Build session story",
        "",
        "The real numbers behind building **iHaveAnnuities**, pulled from this "
        f"project's Claude Code session transcript ({n_rows:,} records spanning "
        "the whole build). Regenerate with `python3 scripts/session_stats.py --md`.",
        "",
        "## Tokens",
        "",
        "| Category | Tokens |",
        "| --- | ---: |",
        f"| Output (generated) | {outp:,} |",
        f"| Input (uncached) | {inp:,} |",
        f"| Cache write | {cc:,} |",
        f"| Cache read | {cr:,} |",
        f"| **Grand total** | **~{total_m:.1f} M** |",
        "",
        f"The total is dominated by **cache reads (~{cr_m:.0f} M)** — that's the "
        "growing conversation/codebase context being re-read on each of "
        f"{turns:,} assistant turns, billed at the cheap cached rate, not "
        f"{cr_m:.0f} M of fresh work. The number that reflects actual **produced "
        f"content is ~{out_m:.2f} M output tokens**.",
        "",
        "## Prompts",
        "",
        f"- **~{prompts} prompts you typed** (out of {n_user_records:,} raw "
        '"user" records — the rest are tool results, slash-command stdout, and '
        "system reminders).",
        f"- **{turns:,} assistant turns** in response (each prompt fans out into "
        "many tool-call/reasoning steps).",
    ]
    if events:
        start = events[0].astimezone()
        end = events[-1].astimezone()
        idle_h = idle.total_seconds() / 3600
        lines += [
            "",
            "## Time",
            "",
            f"Session ran **{start:%b %-d %-I:%M %p} → {end:%b %-d %-I:%M %p %Z}** "
            f"wall-clock, but that includes **~{idle_h:.0f} h of idle gaps** "
            f"(overnight, breaks). Counting only stretches with <{idle_min:g}-min "
            "gaps between events:",
            "",
            f"- **Active session: ~{hms(active)}**",
            f"  - **Claude working** (tool calls, builds, tests, writing): "
            f"~{hms(claude)}",
            f"  - **You prompting / reading**: ~{hms(user)}",
            "",
            "| Metric | Value |",
            "| --- | --- |",
            f"| Session start | {start:%Y-%m-%d %H:%M %Z} |",
            f"| Session end | {end:%Y-%m-%d %H:%M %Z} |",
            f"| Active (gaps <{idle_min:g}m) | {hms(active)} |",
            f"| &nbsp;&nbsp;Claude working | {hms(claude)} |",
            f"| &nbsp;&nbsp;User prompting | {hms(user)} |",
            f"| Idle (excluded) | {hms(idle)} |",
        ]
    lines += [
        "",
        "## Caveats",
        "",
        f"- All from **{len(files)} transcript "
        f"file{'s' if len(files) != 1 else ''}**, which cover the whole "
        "project — both the pre-compaction work and the continued sessions — not "
        "just any single feature.",
        '- **"User prompting" time is approximated** as the gap before each of '
        "your messages (composing + reading my output), so it bundles your "
        "think-time with reading time.",
        "- **Token counts come straight from the `usage` field** on each "
        "assistant message; **timing from event timestamps**.",
        "",
    ]
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    with open(path, "w") as fh:
        fh.write("\n".join(lines))


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("paths", nargs="*", help="transcript .jsonl file(s)")
    ap.add_argument("--idle", type=float, default=DEFAULT_IDLE_MIN,
                    help=f"idle gap threshold in minutes (default {DEFAULT_IDLE_MIN})")
    ap.add_argument("--md", nargs="?", const="docs/SESSION_STATS.md", default=None,
                    metavar="PATH",
                    help="write a Markdown report (default path docs/SESSION_STATS.md)")
    args = ap.parse_args()

    files = find_transcripts(args.paths)
    rows: list[dict] = []
    for p in files:
        rows.extend(load(p))

    inp = outp = cc = cr = 0
    assistant_turns = 0
    for r in rows:
        if r.get("type") != "assistant":
            continue
        assistant_turns += 1
        u = r.get("message", {}).get("usage") or {}
        inp += u.get("input_tokens", 0)
        outp += u.get("output_tokens", 0)
        cc += u.get("cache_creation_input_tokens", 0)
        cr += u.get("cache_read_input_tokens", 0)

    prompts = sum(1 for r in rows if is_human_prompt(r))

    events = sorted((t for t in (parse_ts(r) for r in rows) if t))
    idle_gap = dt.timedelta(minutes=args.idle)
    active = claude = user = idle = dt.timedelta()
    typed = [(parse_ts(r), r.get("type")) for r in rows if parse_ts(r)]
    typed.sort(key=lambda x: x[0])
    for (t0, _), (t1, ty1) in zip(typed, typed[1:]):
        gap = t1 - t0
        if gap > idle_gap:
            idle += gap
        else:
            active += gap
            if ty1 == "user":
                user += gap
            else:
                claude += gap

    total = inp + outp + cc + cr

    if args.md is not None:
        n_user_records = sum(1 for r in rows if r.get("type") == "user")
        write_markdown(args.md, files, len(rows), outp, inp, cc, cr, total,
                       prompts, assistant_turns, events, active, claude, user,
                       idle, args.idle, n_user_records)
        print(f"Wrote {args.md}")
        return

    print(f"Transcripts: {len(files)} file(s), {len(rows):,} records\n")
    print("TOKENS")
    print(f"  Output (generated)   {outp:>15,}")
    print(f"  Input (uncached)     {inp:>15,}")
    print(f"  Cache write          {cc:>15,}")
    print(f"  Cache read           {cr:>15,}")
    print(f"  Grand total          {total:>15,}\n")
    print("ACTIVITY")
    print(f"  Human prompts        {prompts:>15,}")
    print(f"  Assistant turns      {assistant_turns:>15,}\n")
    if events:
        print("TIME")
        print(f"  Session start        {events[0].astimezone():%Y-%m-%d %H:%M %Z}")
        print(f"  Session end          {events[-1].astimezone():%Y-%m-%d %H:%M %Z}")
        print(f"  Active (gaps <{args.idle:g}m)   {hms(active)}")
        print(f"    Claude working     {hms(claude)}")
        print(f"    User prompting     {hms(user)}")
        print(f"  Idle (excluded)      {hms(idle)}")


if __name__ == "__main__":
    main()

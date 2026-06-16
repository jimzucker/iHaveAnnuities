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


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("paths", nargs="*", help="transcript .jsonl file(s)")
    ap.add_argument("--idle", type=float, default=DEFAULT_IDLE_MIN,
                    help=f"idle gap threshold in minutes (default {DEFAULT_IDLE_MIN})")
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

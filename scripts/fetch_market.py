#!/usr/bin/env python3
# fetch_market.py — refresh data/market.json from Yahoo Finance (no API key).
# Copyright 2026 Jim Zucker
# SPDX-License-Identifier: LicenseRef-Proprietary
#
# Runs from the 5pm-ET trading-day GitHub Action. Without --force it is a no-op
# unless "now" is 5pm ET (17:00) on a US trading day, so the two UTC cron entries
# (21:00 & 22:00, covering DST) update at most once per day.

import datetime as dt
import json
import os
import sys
import urllib.request
from zoneinfo import ZoneInfo

ET = ZoneInfo("America/New_York")
SYMBOLS = {"spx": "%5EGSPC", "ndx": "%5ENDX", "rut": "%5ERUT",
           "dow": "%5EDJI", "comp": "%5EIXIC"}
# Short symbol -> Yahoo ticker, for the history series the app charts.
HIST_SYMBOLS = {"SPX": "%5EGSPC", "NDX": "%5ENDX", "RUT": "%5ERUT",
                "DJI": "%5EDJI", "COMP": "%5EIXIC"}
UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36"
_DATA = os.path.join(os.path.dirname(os.path.dirname(__file__)), "data")
OUT = os.path.join(_DATA, "market.json")
HIST_OUT = os.path.join(_DATA, "history.json")

# NYSE full-day closures (observed dates), 2026–2027.
HOLIDAYS = {
    dt.date(2026, 1, 1), dt.date(2026, 1, 19), dt.date(2026, 2, 16),
    dt.date(2026, 4, 3), dt.date(2026, 5, 25), dt.date(2026, 6, 19),
    dt.date(2026, 7, 3), dt.date(2026, 9, 7), dt.date(2026, 11, 26),
    dt.date(2026, 12, 25),
    dt.date(2027, 1, 1), dt.date(2027, 1, 18), dt.date(2027, 2, 15),
    dt.date(2027, 3, 26), dt.date(2027, 5, 31), dt.date(2027, 6, 18),
    dt.date(2027, 7, 5), dt.date(2027, 9, 6), dt.date(2027, 11, 25),
    dt.date(2027, 12, 24),
}


def is_trading_day(d: dt.date) -> bool:
    return d.weekday() < 5 and d not in HOLIDAYS


def fetch_quote(symbol: str) -> tuple[float, int]:
    url = (f"https://query1.finance.yahoo.com/v8/finance/chart/"
           f"{symbol}?interval=1d&range=1d")
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=30) as r:
        meta = json.load(r)["chart"]["result"][0]["meta"]
    return float(meta["regularMarketPrice"]), int(meta["regularMarketTime"])


def fetch_series(symbol: str, interval: str, rng: str) -> list[list]:
    """[[epoch_sec, close], ...] for one index, dropping null closes."""
    url = (f"https://query1.finance.yahoo.com/v8/finance/chart/"
           f"{symbol}?interval={interval}&range={rng}")
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=30) as r:
        res = json.load(r)["chart"]["result"][0]
    ts = res.get("timestamp") or []
    closes = res["indicators"]["quote"][0].get("close") or []
    return [[int(t), round(float(c), 2)]
            for t, c in zip(ts, closes) if c is not None]


def write_history() -> None:
    """Daily (5y) + intraday (15m/5d) closes per index for the in-app charts."""
    daily, intraday = {}, {}
    for sym, ticker in HIST_SYMBOLS.items():
        daily[sym] = fetch_series(ticker, "1d", "5y")
        intraday[sym] = fetch_series(ticker, "15m", "5d")
    data = {"asOf": dt.datetime.now(ET).date().isoformat(),
            "daily": daily, "intraday": intraday}
    with open(HIST_OUT, "w") as f:
        json.dump(data, f, separators=(",", ":"))
        f.write("\n")
    print("wrote", HIST_OUT,
          {k: len(v) for k, v in daily.items()})


def main() -> int:
    force = "--force" in sys.argv
    now_et = dt.datetime.now(ET)
    if not force:
        if not is_trading_day(now_et.date()):
            print(f"skip: {now_et.date()} is not a trading day")
            return 0
        if now_et.hour != 17:
            print(f"skip: ET hour {now_et.hour} != 17 (avoids double-run)")
            return 0

    quotes = {k: fetch_quote(s) for k, s in SYMBOLS.items()}
    as_of = max(t for _, t in quotes.values())
    as_of_date = dt.datetime.fromtimestamp(as_of, ET).date()
    data = {
        "asOf": as_of_date.isoformat(),
        "tradingDay": is_trading_day(as_of_date),
        "spx": round(quotes["spx"][0], 2),
        "ndx": round(quotes["ndx"][0], 2),
        "rut": round(quotes["rut"][0], 2),
        "dow": round(quotes["dow"][0], 2),
        "comp": round(quotes["comp"][0], 2),
    }
    with open(OUT, "w") as f:
        json.dump(data, f, indent=2)
        f.write("\n")
    print("wrote", OUT, data)
    write_history()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

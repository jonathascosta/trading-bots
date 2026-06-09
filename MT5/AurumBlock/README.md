# AurumBlock

**Platform:** MetaTrader 5  
**Version:** 1.14  
**Last updated:** 2026-06-09  
**Based on:** [FvgBlock](../FvgBlock/) v3.87

## What it does

Production-hardened evolution of the FVG Block strategy, built for **XAUUSD M1**. The core logic (Fair Value Gap detection, dual-sided entries, martingale scale-in, break-even TP) is identical to FvgBlock. AurumBlock adds session pause windows, an asymmetric news filter driven by an external CSV calendar, a statistics dashboard, and auto lot sizing — with almost all settings as compile-time `#define` constants instead of runtime inputs.

## Key additions over FvgBlock

| Feature | FvgBlock | AurumBlock |
|---|---|---|
| Session pause windows | — | ±15 min around Tokyo, London, NY Forex, NYSE opens |
| News filter window | ±15 min (hardcoded dates) | **135 min before / 15 min after** (CSV-driven) |
| News calendar source | Hardcoded array in code | External `fvg_news.csv` + live MT5 calendar sync |
| Settings exposure | Runtime inputs | Compile-time `#define` (one input: `InpFixedLots`) |
| Dashboard | Top-left label | Bottom-left stats card (cycles, duration, BE rate) |
| Backtest news filter | Not reproducible | Reproducible via shared CSV |

## Session pause windows

New entries and pending limit orders are blocked during the 15 minutes surrounding each major session open. Existing open positions continue to be managed normally.

| Session | Opens (UTC+1) | Blocked window |
|---|---|---|
| Tokyo | 01:00 | 00:45 – 01:15 |
| London | 08:00 | 07:45 – 08:15 |
| NY Forex | 13:00 | 12:45 – 13:15 |
| NYSE | 14:30 | 14:15 – 14:45 |

Trading starts at 23:15 (15 min after Sydney open) — no pause around Sydney.

## News filter

Asymmetric window: **135 minutes before** an event (no new entries, existing scale-ins continue) → **15 minutes after** (trading resumes).

Events are read from `fvg_news.csv` in `%APPDATA%\MetaQuotes\Terminal\Common\Files\`. While running live, the EA automatically syncs new USD events from the MT5 native economic calendar into the CSV daily (dedup, sorted, history preserved). Backtests read the same CSV, making news blocks reproducible without a live calendar API.

The calendar whitelist filters only events that materially move gold:

- **Labour market:** NFP, ADP, Unemployment Rate, Claims, JOLTS
- **Inflation:** CPI, PPI, PCE
- **Growth:** GDP, Durable Goods, Retail Sales
- **Activity:** ISM Manufacturing, ISM Services
- **Fed:** FOMC, Powell speeches, Fed member statements

Both high-impact (red) and moderate-impact (orange) events on the whitelist are blocked.

## Lot sizing

```
lot = 0.01 × MAX(1;  1 + FLOOR( (√(2×Balance − 700) − 30) / 20 ))
```

Square-root curve — grows more slowly than the previous linear formula, keeping 0.01 lot for longer on smaller accounts:

| Balance range | Auto lot |
|---|---|
| < $1 600 | 0.01 |
| $1 600 – $2 799 | 0.02 |
| $2 800 – $4 399 | 0.03 |
| $4 400 – $6 399 | 0.04 |

Set `InpFixedLots > 0` to override with a fixed lot without recompiling. Scale-in lots always double the previous position's lot regardless of this setting.

## Dashboard (bottom-left)

Semi-transparent dark navy card (88% opacity, true ARGB bitmap, 370 px wide). Rows top to bottom:

- **Status row** — current state: `● ACTIVE` (green), `▶ NEWS <name> » Xm` (amber), `⏸ <Session> pause » Xm` (amber), `■ PAUSED` (red)
- **Next event row** — upcoming pause/news preview: amber when < 90 min to news pre-block or < 60 min to session pause; dim informational when event is within 8 h
- **Box row** — active FVG block range, pip size, and per-band touch counters (`↑Nt ↓Nt`; prefixed with `!` when a band is exhausted)
- **Ciclos hoje / semana** — initial cycle entries only (scale-ins excluded)
- **Tempo mín / avg / máx** — per closed position duration
- **Breakeven** — cycles with net P&L ≤ $0.10 after costs
- **Acima BE** — cycles with net P&L > $0.10
- **Version label** — EA version shown in dim text at the bottom-right of the panel

Set `InpUIScale = 2` on Mac Retina / HiDPI displays to prevent the bitmap from rendering at half the logical size.

## FVG band health and touch counting

Each FVG band is coloured to indicate how many times price has touched it since the block was created:

| Band colour | Meaning |
|---|---|
| Blue (`C_EXTREME`) | Band is clean — no touches yet |
| Amber (`C_UNSTABLE`) | Band touched 1–2 times; entries still allowed |
| Red (`C_OVERTOUCHED`) | Band touched ≥ `TOUCH_WARN_COUNT` (3) times; new initial entries on that side are **blocked** |

Touch counts are reset when a new block is activated, or when a band expands after a large price move. The `!↑Nt` / `!↓Nt` notation in the dashboard box row shows when a band has reached the warning threshold. Scale-in positions on an already-open trade are never blocked by touch count — only new initial entries are gated.

## Configuration

Most settings are `#define` constants — change them and recompile. The runtime inputs are:

| Input | Default | Description |
|---|---|---|
| `InpFixedLots` | 0.0 | Fixed initial lot (0 = auto by balance formula) |
| `InpMinOrderDist` | 130.0 | Pips between scale-in levels (was `#define`, now tunable at runtime / in optimizer) |
| `InpUIScale` | 1 | Dashboard scale: `1` = Windows / non-Retina Mac; `2` = Mac Retina / HiDPI |

Key constants (edit in source before compiling):

| Constant | Default | Description |
|---|---|---|
| `BLK_MIN_SIZE` | 39.0 | Min block size in pips |
| `ZONE_PCT` | 5.0 | Entry zone as % of block |
| `COST_PER_LOT` | 0.06 | Round-trip cost per 0.01 lot |
| `PAUSE_WINDOW_MIN` | 15 | Minutes blocked around session opens |
| `NEWS_PRE_SEC` | 8100 | Seconds before event to block (135 min) |
| `NEWS_POST_SEC` | 900 | Seconds after event to resume (15 min) |
| `TRADE_START_H/M` | 23:15 | Trading window start |
| `FORCE_CLOSE_H/M` | 20:45 | Force-close time |
| `SERVER_OFFSET` | 3 | Broker server UTC offset |
| `LOCAL_OFFSET` | 1 | Local UTC offset |
| `TOUCH_WARN_COUNT` | 3 | Touch threshold to flag a band as exhausted and block new entries |
| `C_OVERTOUCHED` | `C'255,153,153'` | Band colour when touch count ≥ `TOUCH_WARN_COUNT` (red) |

## External files required

| File | Location | Purpose |
|---|---|---|
| `fvg_news.csv` | `%APPDATA%\MetaQuotes\Terminal\Common\Files\` | News calendar (auto-synced live) |
| `fvg_pause.flag` | Same folder | Web panel pause (optional) |

See [CHANGELOG.md](CHANGELOG.md) for full version history.

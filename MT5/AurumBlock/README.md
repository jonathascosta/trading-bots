# AurumBlock

**Platform:** MetaTrader 5  
**Version:** 1.37  
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
lot = FLOOR( Balance / (13 × 100 × (2^(InpMaxFolds+2) − InpMaxFolds − 3)), 0.01 )
```

Denominator equals the worst-case total floating exposure (in account-currency units per 0.01 lot) up to the point where an additional scale-in beyond `InpMaxFolds` would trigger — providing one full safety interval of buffer. Result is floored to the 0.01 grid; minimum is 0.01.

| Balance (USC) | InpMaxFolds=6 | InpMaxFolds=10 |
|---|---|---|
| 10 000 | 0.02 | 0.01 |
| 70 000 | 0.11 | 0.02 |
| 140 000 | 0.22 | 0.05 |

Set `InpFixedLots > 0` to override with a fixed lot without recompiling. Scale-in lots multiply the previous position's lot by `InpLotMultiplier` regardless of this setting.

## Dashboard (bottom-left)

Semi-transparent dark navy card (88% opacity, true ARGB bitmap, 370 px wide). The panel is **draggable** — click and drag it to any position on the chart; the position is saved to terminal global variables (`AUR_PAN_X` / `AUR_PAN_Y`) and restored on EA restart. To reset to the default bottom-left corner, remove and re-attach the EA (or delete those global variables via `Tools → Global Variables`).

Rows top to bottom:

- **Status row** — current state: `● ACTIVE` (green), `▶ NEWS <name> » Xm` (amber), `⏸ <Session> pause » Xm` (amber), `■ PAUSED` (red)
- **Next event row** — upcoming pause/news preview: amber when < 90 min to news pre-block or < 60 min to session pause; dim informational when event is within 8 h
- **Box row** — active FVG block range, pip size, and per-band touch counters (`↑Nt ↓Nt`; prefixed with `!` when a band is exhausted)
- **Today row** — cycles started today + closed breakdown: `BE N  >BE N` (BE = net P&L ≤ $0.10; >BE = net P&L > $0.10)
- **Week row** — same breakdown for the current week
- **Duration row** — min / avg / max per closed position
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

Each **visit** to the zone counts as one touch, regardless of how many consecutive bars price remains inside it. The EA tracks whether price was already in the zone on the previous bar (`g_botInZone` / `g_topInZone`) and only increments the counter on the entry transition (outside → inside).

## Safe Mode

When `InpSafeMode = true`, new cycle entries are restricted to two UTC+1 time windows:

| Window | Hours |
|---|---|
| Window 1 | 01:15 – 05:45 |
| Window 2 | 08:15 – 10:45 |

Outside these windows, pending limit orders are cancelled and no new initial entries are placed. Scale-ins on existing open positions continue normally. Session pauses are overridden by Safe Mode for scale-ins (news blocks still apply in all cases). The dashboard shows `◈ SAFE  scale-ins only` (indigo) when outside a window and `● ACTIVE  (safe window)` when inside one.

## Configuration

Most settings are `#define` constants — change them and recompile. The runtime inputs are:

| Input | Default | Description |
|---|---|---|
| `InpFixedLots` | 0.0 | Fixed initial lot (0 = auto by balance formula) |
| `InpMinOrderDist` | 130.0 | Pips between scale-in levels (was `#define`, now tunable at runtime / in optimizer) |
| `InpLotMultiplier` | 2.0 | Scale-in lot multiplier (2 = double, 3 = triple, 4 = quadruple) |
| `InpMaxFolds` | 10 | Number of scale-ins the auto-lot formula is sized to support |
| `InpSafeMode` | false | Restrict new cycle entries to two UTC+1 windows (01:15–05:45 and 08:15–10:45) |
| `InpUIScale` | 1 | Dashboard scale: `1` = Windows / non-Retina Mac; `2` = Mac Retina / HiDPI |
| `InpLogTrades` | true | Log every order and position close to SQLite |
| `InpLogBlocks` | true | Log every new FVG block activation to SQLite |
| `InpLogFilters` | true | Log news/session/trading-window filter transitions to SQLite |
| `InpLogSnapshots` | true | Log end-of-day and cycle-close P&L snapshots to SQLite |

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
| `FORCE_CLOSE_H/M` | 19:45 | Force-close / scale-in threshold (unified) |
| `SERVER_OFFSET` | 3 | Broker server UTC offset |
| `LOCAL_OFFSET` | 1 | Local UTC offset |
| `TOUCH_WARN_COUNT` | 3 | Touch threshold to flag a band as exhausted and block new entries |
| `C_OVERTOUCHED` | `C'255,153,153'` | Band colour when touch count ≥ `TOUCH_WARN_COUNT` (red) |

## Activity logging (SQLite)

When running live (`IsTesting()` = false), the EA writes to `MQL5\Files\AurumBlock.db` using the built-in MQL5 SQLite API — no DLLs required. Each logging category can be toggled independently via the `InpLog*` inputs.

**7 tables:**

| Table | Contents |
|---|---|
| `sessions` | EA start/stop with full config JSON |
| `blocks` | Every new FVG block activation and zone coordinates |
| `zone_touches` | Each distinct zone touch (bot/top) with exhaustion flag |
| `filter_events` | News / session-pause / trading-window / force-close transitions with duration |
| `trades` | Every order placed, scale-ins, and position closes with P&L breakdown |
| `cycles` | Completed trade cycles: direction, duration, scale-in count, peak lots, net P&L, max floating drawdown (`max_dd`) |
| `pnl_snapshots` | End-of-day and cycle-close P&L snapshots |

**Retention:** on the first tick of each new month, the active DB is archived to `AurumBlock_YYYY_MM.db`, rows older than 30 days are pruned, and `VACUUM` is run. Backtests do not write to the database.

## External files required

| File | Location | Purpose |
|---|---|---|
| `fvg_news.csv` | `%APPDATA%\MetaQuotes\Terminal\Common\Files\` | News calendar (auto-synced live) |
| `fvg_pause.flag` | Same folder | Web panel pause (optional) |

See [CHANGELOG.md](CHANGELOG.md) for full version history.

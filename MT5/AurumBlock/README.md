# AurumBlock

**Platform:** MetaTrader 5  
**Version:** 1.51  
**Last updated:** 2026-07-08  
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

Two nested zones around each event:

| Zone | Window | Effect |
|---|---|---|
| Soft | −180 min → +15 min | Blocks new entries only; scale-ins on open positions continue |
| Hard | −60 min → +15 min | Freezes everything including scale-ins |

Events are read from `fvg_news.csv` in `%APPDATA%\MetaQuotes\Terminal\Common\Files\`. While running live, the EA automatically syncs new USD events from the MT5 native economic calendar into the CSV daily (dedup, sorted, history preserved). Backtests read the same CSV, making news blocks reproducible without a live calendar API.

The calendar whitelist filters only events that materially move gold:

- **Labour market:** NFP, ADP, Unemployment Rate, Claims, JOLTS
- **Inflation:** CPI, PPI, PCE
- **Growth:** GDP, Durable Goods, Retail Sales
- **Activity:** ISM Manufacturing, ISM Services
- **Fed:** FOMC, Powell speeches, Fed member statements

Both high-impact (red) and moderate-impact (orange) events on the whitelist are blocked. The dashboard banner distinguishes "NEWS … scale-ins" (soft zone) from "NEWS … frozen" (hard zone).

## Lot sizing

`GetLots()` uses a tiered formula that scales safely with balance. Starting from n=6, it iterates upward and selects the first n where `lot < 2^(n−6)`:

```
lot(n) = FLOOR( Balance / (13 × 100 × (2^(n+2) − n − 3)), 0.01 )
tier advances when lot(n) ≥ 2^(n−6)  →  try n+1
```

Each tier adds one extra fold of safety margin to match the larger position. The loop is uncapped (runs to n=30 as a safety guard, unreachable below ~$10¹² balance).

| Lot range | n selected | Safety folds |
|---|---|---|
| 0.01 – 0.99 | 6 | 6 |
| 1.00 – 1.99 | 7 | 7 |
| 2.00 – 3.99 | 8 | 8 |
| 4.00 – 7.99 | 9 | 9 |

The starting tier `n` is controlled by `InpAutoLotFolds` (default 10). A higher value produces a smaller, more conservative initial lot; a lower value produces a larger, more aggressive lot. This only affects the initial lot size — it does not limit the actual number of scale-ins.

Set `InpFixedLots > 0` to override with a fixed lot without recompiling. Scale-in lots multiply the previous position's lot by `InpLotMultiplier` regardless of this setting.

## Dashboard (bottom-left)

Semi-transparent dark navy card (88% opacity, true ARGB bitmap, 370 px wide). The panel is **draggable** — click and drag it to any position on the chart; the position is saved to terminal global variables (`AUR_PAN_X` / `AUR_PAN_Y`) and restored on EA restart. To reset to the default bottom-left corner, remove and re-attach the EA (or delete those global variables via `Tools → Global Variables`).

Rows top to bottom:

- **Status row** — current state: `● ACTIVE` (green), `◈ SAFE  scale-ins only` (indigo), `▶ NEWS <name>` (amber), `⏸ <Session> pause` (amber), `■ PAUSED` (red), `■ HALTED max-loss` (bright red)
- **Next event / version row** — upcoming pause/news preview with countdown; EA version in dim text at the right
- **Box row** — active FVG block range, pip size, and per-band touch counters (`↑Nt ↓Nt`; prefixed with `!` when exhausted)
- **Lot row** — initial lot, budgeted folds, and max adverse gold move the sizing can absorb (e.g. `Lot 0.21 · 10 folds · ↔ $143.00`)
- **Statistics table** — three rows aligned in monospace (Consolas):

```
        ops  cyc  mxF   maxDD     P/L    avg
Today    27   15    5   -2781    +543    +36
Week     87   44    6   -5200   +2100    +48
All     312  180    8  -12400   +8900    +49
```

- **Warning banner** — `⚠ N FOLDS · X lots ⚠` flashing red/amber when active cycle exceeds `InpAlertScaleIns` folds
- **Halt banner** — `⚠ HALTED · MAX-LOSS STOP ⚠` flashing red/dark when EA is halted

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

When `InpSafeMode = true` (default), new cycle entries are restricted to a single UTC+1 window: **01:15 – 10:45**. The only interruption within that window is the London session pause (07:45–08:15), which blocks new entries for 30 minutes but leaves scale-ins running.

Outside the safe window, pending limit orders are cancelled and no new initial entries are placed. Scale-ins on existing open positions continue normally (session pauses are overridden by Safe Mode for scale-ins). News hard-zone blocks still freeze scale-ins in all cases.

The dashboard shows `◈ SAFE  scale-ins only` (indigo) when outside the window and `● ACTIVE  (safe window)` when inside it.

## Configuration

Most settings are `#define` constants — change them and recompile. The runtime inputs are:

| Input | Default | Description |
|---|---|---|
| `InpFixedLots` | 0.0 | Fixed initial lot (0 = auto by balance formula) |
| `InpMinOrderDist` | 130.0 | Pips between scale-in levels |
| `InpLotMultiplier` | 2.0 | Scale-in lot multiplier (2 = double, 3 = triple, 4 = quadruple) |
| `InpAutoLotFolds` | 10 | Budgeted folds for the auto-lot formula (higher = smaller/safer lot) |
| `InpSafeMode` | true | Restrict new cycle entries to the 01:15–10:45 UTC+1 window |
| `InpAlertScaleIns` | 4 | Push alert threshold: notify on every scale-in beyond this fold count (0 = off) |
| `InpMaxLossPct` | 12.0 | Daily loss kill switch as % of balance (0 = off); halts EA permanently via `AUR_HALT` GV |
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
| `NEWS_PRE_SOFT_SEC` | 10800 | Seconds before event to block new entries only (180 min) |
| `NEWS_PRE_HARD_SEC` | 3600 | Seconds before event to freeze everything incl. scale-ins (60 min) |
| `NEWS_POST_SEC` | 900 | Seconds after event to resume (15 min) |
| `TRADE_START_H/M` | 23:15 | Trading window start |
| `FORCE_CLOSE_H/M` | 19:45 | Force-close / scale-in threshold (unified) |
| `SERVER_OFFSET` | 3 | Broker server UTC offset |
| `LOCAL_OFFSET` | 1 | Local UTC offset |
| `TOUCH_WARN_COUNT` | 3 | Touch threshold to flag a band as exhausted and block new entries |
| `C_OVERTOUCHED` | `C'255,153,153'` | Band colour when touch count ≥ `TOUCH_WARN_COUNT` (red) |

## Kill switch (max daily loss)

When `InpMaxLossPct > 0`, the EA monitors `daily_profit + floating_PnL` on every tick. If the combined loss reaches or exceeds `InpMaxLossPct %` of the current balance, the EA:

1. Closes all open positions and cancels pending orders immediately
2. Enters a **permanent halt** — no new entries or scale-ins until manually re-armed
3. Persists the halt state in terminal global variable `AUR_HALT` (survives EA and MT5 restarts)
4. Sends a push notification to the MT5 mobile app and fires a desktop `Alert()`

**To re-arm:** delete the `AUR_HALT` global variable via `Tools → Global Variables` (F3) in MT5.

The dashboard shows `■ HALTED max-loss · F3 del AUR_HALT` in bright red (highest priority status) and a large flashing `⚠ HALTED · MAX-LOSS STOP ⚠` banner. The state machine continues running during the halt so that any forced closes are correctly logged to the database.

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

# AurumBlock EA — Changelog

## v1.39 — 2026-06-23

### Change — Auto-lot: removed InpMaxFolds; tiered threshold is now uncapped

`InpMaxFolds` removed as an input parameter. `GetLots()` now iterates n freely
from 6 upward — no ceiling needed because the formula is self-limiting: the
denominator grows as `2^n` while the threshold grows as `2^(n-6)`, so lots
converges below the threshold at some finite n for any realistic balance.

The loop runs to n=30 as a safety guard (unreachable below ~$10¹² balance).

---

## v1.38 — 2026-06-23

### Change — Auto-lot: tiered threshold allows lot size to grow with balance

**Before:** `GetLots()` used fixed `InpMaxFolds` as the single denominator exponent.
The lot was always capped below 1.0 — once balance was large enough that the
calculated lot hit 1.0, the EA silently capped it and would never trade larger.

**After:** `GetLots()` iterates `n` from 6 to `InpMaxFolds`, stopping at the first `n` where:
`lots < 2^(n−6)` — threshold doubles each step: 1, 2, 4, 8, 16 …

Effect: as balance grows, the lot tier advances instead of stalling at 1.0.
Each tier upgrade adds one extra fold of safety margin to match the larger position size.

| Balance tier | n selected | lots range | safety folds |
|---|---|---|---|
| base | 6 | 0 – 0.99 | 6 |
| ×1 | 7 | 1 – 1.99 | 7 |
| ×2 | 8 | 2 – 3.99 | 8 |
| ×4 | 9 | 4 – 7.99 | 9 |

`InpMaxFolds` remains a hard cap: if balance would require `n > InpMaxFolds`, the EA
keeps `n = InpMaxFolds` (lots may exceed the tier threshold in that case).

The corresponding Excel formula change: `lots < 1` → `lots < 2^(ns−6)`.

---

## v1.37 — 2026-06-22

### Fix — Quick cycles (limit fills + TP in same tick) now logged in DB

**Root cause:** When a sell/buy limit order fills AND hits TP between two `OnTick` calls
(within the same server tick), the EA state machine jumps `STATE_PENDING → STATE_IDLE`
without passing through `STATE_SELLS/BUYS`. `DBLogCycle` was only triggered on
`STATE_SELLS/BUYS → STATE_IDLE`, so these fast cycles were silently dropped from the DB.
They appeared in MT5 history and in the `trades` table, but never in the `cycles` table,
making the dashboard Net P&L significantly understated.

**Fix:**
- When a sell/buy *limit* order is placed in `STATE_IDLE`, immediately anchor
  `g_cycleStartDealCount = HistoryDealsTotal()` (before the fill) and set
  `g_pendingDirection = "sell"/"buy"`.
- A new `else if(g_prevState == STATE_PENDING && g_state == STATE_IDLE && g_pendingDirection != "")`
  branch calls `DBLogCycle(g_pendingDirection)` on the quick-cycle transition.
- `DBLogCycle` signature changed from `(EState fromState, datetime cycleStart)` to
  `(string direction)` — the `cycleStart` parameter was unused internally (INSERT uses
  `firstIn` from the deal scan).
- `g_pendingDirection` is cleared on every `STATE_IDLE` entry and when a normal cycle
  opens (to prevent stale values).

Market orders are unaffected (they go directly to `STATE_SELLS/BUYS`, handled by the
existing backward-walk anchor path).

---

## v1.36 — 2026-06-22

### Change — Auto-lot formula: extra safety interval beyond last scale-in

**Before:** `denom = 13 × 100 × (2^(N+1) − 2 − N)`
Sized to survive the floating when the Nth (last) scale-in is placed.

**After:** `denom = 13 × 100 × (2^(N+2) − N − 3)`
Sized to survive the floating up to the point where the (N+1)th scale-in WOULD trigger,
without actually opening that position. This adds one full interval of buffer (130 pips
× total open lots) beyond the last permitted scale-in.

Effect: lot size is approximately halved for the same `InpMaxFolds` value.
Example with N=6, balance $72 565: 0.46 → 0.22 initial lots.

---

## v1.35 — 2026-06-22

### Fix — Cycle not logged after MT5/chart restart mid-cycle

**Root cause:** On restart with an active cycle, `g_cycleStartDealCount` was set to
`HistoryDealsTotal()` at restart time — i.e., AFTER all existing entry deals. When the
cycle eventually closed, `DBLogCycle` scanned from that index, found no `DEAL_ENTRY_IN`
records, hit the `firstIn == 0` guard, and returned without writing the cycle row.

**Fix:** When the cycle-open transition fires, walk back through history (by magic number
and symbol) from the current tail to `g_cycleOpenTime`. The first entry deal found
becomes the new `g_cycleStartDealCount`, ensuring all entry deals — including those that
predate the current session — are included in the scan.

This fix is purely derived from server-side history, so it survives hard crashes and
full MT5 restarts with no GlobalVariables or extra DB tables required.

**Side-effect (improvement):** For fresh cycles, `open_time` now reflects the initial
fill rather than the first scale-in, and `peak_lots` now includes the initial entry lots.

---

## v1.34 — 2026-06-22

### Change — Safe Mode overrides session pause for scale-ins

When `InpSafeMode = true`, session pauses (Tokyo, London, NY, NYSE) no longer block
scale-ins on existing positions. The Safe Mode operating schedule becomes the single
governing time rule:

- **Inside safe window:** new entries allowed, scale-ins allowed — session pause ignored.
- **Outside safe window:** new entries blocked, scale-ins allowed — session pause ignored.
- **News active:** scale-ins blocked in all cases regardless of Safe Mode (risk control).

Implementation: scale-in guard changed from `!IsSessionPauseTime()` to
`(!IsSessionPauseTime() || InpSafeMode)` in both `STATE_SELLS` and `STATE_BUYS`.

---

## v1.33 — 2026-06-22

### Fix — Scale-in trades not logged in DB (`scale_sell` / `scale_buy`)

**Root cause:** In both `STATE_SELLS` and `STATE_BUYS`, after `g_trade.Sell()` / `g_trade.Buy()`
succeeds, `UpdateAllTPs()` was called before reading `g_trade.ResultOrder()` and
`g_trade.ResultPrice()`. `UpdateAllTPs()` calls `g_trade.PositionModify()` for every open
position, which overwrites the CTrade internal result buffer. By the time `DBLogTrade` was
called, `g_trade.ResultOrder()` reflected the last `PositionModify` result (typically 0 or a
position ticket unrelated to the new scale-in order), causing `DBLogTrade` to return early on
the `ticket == 0` guard — silently skipping the insert.

**Fix:** Capture `g_trade.ResultOrder()` and `g_trade.ResultPrice()` into local variables
immediately after `Sell()`/`Buy()` returns, before any other `g_trade` call.

**Note:** Scale-in rows in `trades` will have `closed_at = NULL` and `profit = NULL` because
`DBDetectClosedTrades()` matches by `DEAL_POSITION_ID`, and on netting accounts all scale-ins
share the same position ID as the initial entry — the close deal is attributed to the initial
trade row only. This is acceptable: aggregate P&L is already captured in `cycles.net_pnl`.

---

## v1.32 — 2026-06-21

### Change — Auto lot formula rewritten

New formula: `FLOOR(Balance / (13 × 100 × (2^(Folds+1) − 2 − Folds)), 0.01)`

- `Balance` = account balance (not equity).
- `Folds` = new input `InpMaxFolds` (int, default 10) — number of scale-ins to support.
- Denominator = worst-case total exposure in account-currency units per 0.01 lot across all folds.
- Result is floored to the 0.01 lot grid; minimum enforced at 0.01.
- Old formula (square-root of balance) removed.

| Balance (USC) | InpMaxFolds=10 → lots |
|---|---|
| 10 000 | 0.01 |
| 38 500 | 0.01 |
| 70 000 | 0.02 |
| 140 000 | 0.05 |

---

## v1.31 — 2026-06-21

### Feature — Safe Mode (`InpSafeMode`)

New boolean input (default `false`). When enabled, the EA restricts opening of new cycles
to two predefined UTC+1 time windows:

- **Window 1:** 01:15 – 05:45
- **Window 2:** 08:15 – 10:45

**Outside these windows:** pending limit orders are cancelled and no new initial entries are
placed. Scale-ins (martingale doublings on existing positions) continue normally — the
`canOpen` guard only controls new cycle entry; scale-in guards (`STATE_SELLS` / `STATE_BUYS`)
are unaffected.

**Implementation:**
- `#define` constants `SAFE_WIN1_*` / `SAFE_WIN2_*` for the window boundaries.
- `IsSafeTime()` — returns `true` always when `InpSafeMode=false`; otherwise checks current
  local time against the two windows.
- `canOpen` now includes `IsSafeTime()`.
- Pending-cancel condition expanded to include `InpSafeMode && !IsSafeTime()`.
- Dashboard: new status `◈ SAFE  scale-ins only` (indigo) when safe mode is on and outside
  a window; `● ACTIVE  (safe window)` when inside one.

---

## v1.30 — 2026-06-19

### Feature — Max floating drawdown per cycle (`max_dd`)

Tracks the worst (most negative) sum of floating P&L of all EA-magic positions, sampled
on every tick while a cycle is active. Stored in `cycles.max_dd` (negative value, e.g. -1.36 USC).

- New global `g_cyclePeakDD`: reset to 0.0 at cycle open and after cycle close.
- Per-tick loop in ManageTrade() sums `POSITION_PROFIT + POSITION_SWAP` for all EA positions;
  updates `g_cyclePeakDD` whenever the sum is more negative.
- `DBLogCycle()` writes `g_cyclePeakDD` into the new `max_dd` column.
- `DBInit()` adds `ALTER TABLE cycles ADD COLUMN max_dd REAL DEFAULT 0.0` for existing DBs.

---

## v1.29 — 2026-06-19

### Fix — DBLogCycle: index-based deal scan replaces timestamp-based scan

v1.28 changed `HistorySelect(cycleStart - 1, ...)` to `HistorySelect(cycleStart, ...)` but
the bug persisted: when a cycle closes and the next opens in the same second, the exit
deal of the previous cycle has `DEAL_TIME == cycleStart`, so it was still captured by the
inclusive range.

Root fix: at the IDLE→SELLS/BUYS transition, snapshot `HistoryDealsTotal()` into
`g_cycleStartDealCount`. `DBLogCycle` now uses `HistorySelect(0, now+1)` and loops from
`g_cycleStartDealCount`, skipping all deals that predate this cycle regardless of timestamp.

---

## v1.28 — 2026-06-19

### Fix — DBLogCycle double-counts previous cycle profit

`HistorySelect` was called with `cycleStart - 1` to avoid missing the entry deal.
When a cycle closes and the next one opens in the same second, this caused
`HistorySelect` to start 1 second before the new cycle, capturing the previous
cycle's exit deal and inflating `net_pnl` by the previous cycle's profit.

Fix: `HistorySelect(cycleStart, ...)` — safe because `g_cycleOpenTime` is set
from `POSITION_TIME`, which equals the entry deal's `DEAL_TIME`, so no deal is
missed by the inclusive range.

---

## v1.27 — 2026-06-12

### Visual — remove border outline from FVG block

Removed the dedicated border rectangle (`AUR_MID_BORD`) that was drawn on top of
the filled block. The block now renders as solid filled zones with no outline.

Removed: `N_MID_B` object name, `BORDER_WIDTH` define, `cBorder` local variable,
and the `BoxSet(N_MID_B, ...)` call in `UpdateVisuals()`.

---

## v1.26 — 2026-06-11

### Dashboard — remove arrow glyph from cycle count rows

Removed `↑` prefix from "Today" and "Week" rows (no functional meaning).

---

## v1.25 — 2026-06-11

### Dashboard — separate today / week stats with per-period BE breakdown

**Cycles rows restructured:**
- Row "Today": total cycles started today + closed breakdown — `BE N  >BE N`
- Row "Week": same for the current week

The "Today" total counts initial entries (including any cycle still open).
`BE` = closed cycles where net P&L ≤ $0.10 (breakeven/loss).
`>BE` = closed cycles where net P&L > $0.10 (profitable).

**Removed:** separate "Breakeven" and "Above BE" rows (merged into the two new rows).
**Added:** "Duration" row promoted to the freed position.

---

## v1.24 — 2026-06-11

### Fix — TP tracking the visual midline correctly + same-block guard

**Bug:** the midline area drawing moved on every tick (because `UpdateVisuals()` includes
the live bar's high/low range) but the TP stayed put until bar close. Fixed by applying
the same live-bar adjustment to `abH`/`abL` in `ManageTrade()`.

**New rule — same-block guard:** `g_tradeBlockTime` records the `startTime` of the block
that opened the current cycle. TP is only updated when the active block is the same as
the one that created the position. If the block changes while positions are still open,
the TP stays frozen at its last value.

**Threshold change:** `UpdateAllTPs` and `UpdatePendingOrder` now use `> 0.01` (was
`> 0.00001`) before sending a `PositionModify` — prevents redundant broker calls for
sub-pip drift on XAUUSD.

---

## v1.23 — 2026-06-11

### Feature — SQLite activity logger

Adds persistent logging to `MQL5\Files\AurumBlock.db` (SQLite, built-in MQL5 API, no DLLs).
Live trading only (`IsTesting()` guard prevents writes during backtesting).

**7 tables:** `sessions`, `blocks`, `zone_touches`, `filter_events`, `trades`, `cycles`, `pnl_snapshots`

**What is logged:**
- EA start/stop with full config JSON (`sessions`)
- Every new FVG block activation and its zone coordinates (`blocks`)
- Each distinct zone touch (bot/top) with exhaustion flag (`zone_touches`)
- News/session-pause/trading-window/force-close/web-pause transitions with duration (`filter_events`)
- Every order placed (limit and market), scale-ins, and position closes with P&L breakdown (`trades`)
- Completed trade cycles: direction, duration, scale-in count, peak lots, net P&L (`cycles`)
- End-of-day and cycle-close P&L snapshots (`pnl_snapshots`)

**Manual closes** are detected via `DEAL_REASON` and logged as `close_reason='manual'`.

**Retention:** On the first tick of each new month, the active DB is archived to
`AurumBlock_YYYY_MM.db` via `ATTACH DATABASE`, then rows older than 30 days are pruned
from the active file and `VACUUM` is run.

**4 new inputs** (group "DB Logging"): `InpLogTrades`, `InpLogBlocks`, `InpLogFilters`,
`InpLogSnapshots` — each can be toggled independently.

---

## v1.22 — 2026-06-11

### Cleanup — remove redundant `FORCE_CLOSE_H/M` defines

`FORCE_CLOSE_H` and `FORCE_CLOSE_M` were made equal to `TRADE_STOP_H/M` in
v1.19. `IsForceCloseTime()` now references `TRADE_STOP_H/M` directly.
The two redundant defines are removed.

No behaviour change.

---

## v1.21 — 2026-06-11

### Change — code and dashboard fully in English

All remaining Portuguese text translated to English:
- Dashboard labels: "Ciclos" → "Cycles", "hoje" → "today", "semana" → "week",
  "Duração" → "Duration", "Acima BE" → "Above BE", "ciclos" → "cycles",
  "em X" → "in X", "para em X" → "stops in X"
- Code comments: defines, function block headers, inline comments
- Changelog entries v1.07 – v1.20 translated

No logic changes.

---

## v1.20 — 2026-06-11

### Fix — touch count per visit, not per bar

**Bug:** `g_botTouchCount++` incremented on **every M1 bar** where
`barLow <= bb`. If price entered the zone and stayed there for 3 consecutive
bars, the counter reached 3 from a single visit — the zone was invalidated
before price had independently returned 3 times.

**Root cause:** no memory of whether price was already inside the zone on
the previous bar.

**Fix:** two new globals `g_botInZone` / `g_topInZone`.
The counter only increments when price **enters** the zone (false→true
transition). While price remains in the zone the flag stays `true` and the
`++` is blocked. On exit (`barLow > bb`) the flag resets to `false`,
allowing the next visit to be counted.

```
Before: 3 consecutive bars in zone = 3 touches (bug)
After:  3 consecutive bars in zone = 1 touch  (correct)
```

Flag reset also added in: new block detected, large band extension (reference
reset), `OnInit()`, and when `g_activeIdx < 0`.

**No impact on trading logic** — touch counting only.

---

## v1.19 — 2026-06-11

### Change — single end-of-day threshold (19:45)

`FORCE_CLOSE_H` lowered from 20 to 19, matching `TRADE_STOP_H`.

**Before:** two separate thresholds:
- 19:45 → stops new cycles, cancels pending, **blocks** scale-ins
- 20:45 → close if positive; if negative, activates scale-ins

**Now:** single threshold at 19:45:
- 19:45 → close if positive, cancel pending, no new cycles
- If negative with open positions → scale-ins allowed immediately

**Advantage:** eliminates the 1-hour dead zone where scale-ins were blocked.
Entering a scale-in earlier (less adverse price) is mathematically better
than waiting 60 min.

Manual close if position is still negative at 22:00+.

**No impact on trading logic** — time defines only.

---

## v1.18 — 2026-06-10

### Change — configurable scale-in lot multiplier (`InpLotMultiplier`)

The lot multiplier was hardcoded as `2.0` (double) in two places in
`ManageTrade()`. It is now an external input:

```
input double InpLotMultiplier = 2.0;   // 2=double · 3=triple · 4=quadruple
```

Suggested combinations (based on break-even analysis):

| Multiplier | Interval | BE @ L3 (e.g. sell 4100) | BE distance (pips) |
|---|---|---|---|
| 2× | 130 pips | 4118.6 | 74 |
| 3× | ~90 pips | ~4120 | ~55 |
| 4× | ~70 pips | ~4122 | ~35 |

Smaller intervals compensate for the higher exposure of an aggressive multiplier.
Optimise via Strategy Tester with `InpMinOrderDist` and `InpLotMultiplier` together.

**No other impact** — only `newLots = lastLots × InpLotMultiplier`.

---

## v1.17 — 2026-06-10

### Fix — drag via pure CHARTEVENT_MOUSE_MOVE

`CHARTEVENT_OBJECT_DRAG` never fires for `OBJ_BITMAP_LABEL` (it is a
pixel-positioned overlay, not a price/time chart object). Replaced by drag
detection entirely based on `CHARTEVENT_MOUSE_MOVE`:

- New global `g_prevLBtn` — stores the left button state from the previous
  event to detect the `false → true` transition (button just pressed).
  Prevents accidentally starting a drag when the user had the button pressed
  elsewhere and moves the cursor over the panel.
- Drag starts when: button transitioned from released to pressed AND cursor
  is within the panel bounds.
- While dragging: panel updates in real time, clamped inside the chart.
- On release: position saved with `GlobalVariableSet`.

**No impact on trading logic** — visual only.

---

## v1.16 — 2026-06-10

### Fix — panel drag now works

`CHARTEVENT_OBJECT_DRAG` never fires for `OBJ_BITMAP_LABEL` (it is a
pixel-positioned overlay, not a price/time chart object).

**New implementation:**
1. `ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE, true)` in `OnInit` enables
   mouse events in the EA
2. `CHARTEVENT_OBJECT_CLICK` on the bitmap detects the drag start and stores
   the offset (cursor − panel position) to prevent a jump when grabbing
3. `CHARTEVENT_MOUSE_MOVE` (with left button active) updates the position in
   real time, clamped within chart bounds
4. On button release, position is persisted with `GlobalVariableSet`

With `OBJPROP_SELECTABLE = true` a click on the panel goes to the object, not
the chart — the chart does NOT scroll while the panel is being dragged.

**No impact on trading logic** — visual only.

---

## v1.15 — 2026-06-10

### Visual — draggable dashboard

The panel can now be dragged to any position on the chart.

**How to use:** click on the panel and drag to the desired position. The
position is saved automatically in terminal global variables (`AUR_PAN_X` /
`AUR_PAN_Y`) and restored when the EA restarts. To reset to the bottom-left
corner: remove the EA and reattach it (or delete the global variables in
`Tools → Global Variables`).

**Implementation:**
- New globals `g_panX`, `g_panY`, `g_panDragged`
- New function `EnsurePanelPos()` — calculates the default position (pinned
  to the bottom) when `!g_panDragged`; no-op after the user drags
- `DashLabel()` converted from `CORNER_LEFT_LOWER` (absolute chart-bottom
  coordinates) to `CORNER_LEFT_UPPER + ANCHOR_LEFT_LOWER` with coordinates
  relative to the panel (`g_panX + 20`, `g_panY + row_offset`)
- Panel bitmap: `OBJPROP_SELECTABLE = true` to enable drag
- New `OnChartEvent()` — captures `CHARTEVENT_OBJECT_DRAG` on the bitmap,
  updates `g_panX/g_panY`, persists with `GlobalVariableSet`, redraws labels
- `OnInit()` restores position with `GlobalVariableGet` if available

**No impact on trading logic** — visual only.

---

## v1.14 — 2026-06-09

### Fix — version label offset + wider panel

**Version label:** `ANCHOR_RIGHT_LOWER` with `CORNER_LEFT_LOWER` causes
offset in MQL5 — replaced by `ANCHOR_LEFT_LOWER` (same as all other labels),
positioned 50 px from the panel's right edge.
Colour changed from `C'70,85,110'` (dark, no contrast) to `C'210,220,235'`
(very light grey, readable on the navy background).
Final position adjusted manually: `vx = (20 + DASH_PAN_W - 50)`, `vy = (DASH_PAN_BOT + DASH_PAN_H - 18)`.

**Wider panel:** `DASH_PAN_W` 325 → 370 px to give more room to content.

---

## v1.13 — 2026-06-09

### Visual — version shown in dashboard

Added label `v1.13` in the **top-right corner** of the panel, in 8 pt font
and dim colour (`C'70,85,110'`). Subtle but always visible.

To stay consistent across versions, always update both defines together:
```mql5
#property version   "X.XX"
#define EA_DASH_VER "vX.XX"
```

---

## v1.12 — 2026-06-09

### Fix — dashboard: "non-string passed" and phantom "Label"

**"non-string passed"** on the Box line: `StringFormat` in MQL5 behaves
unstably when mixing `%s` and `%d` in the same format string. Replaced by
string concatenation + `IntegerToString()`.

**Phantom "Label"** on the next-event line: when `nextText = ""`, the
`OBJ_LABEL` shows the MT5 default text ("Label") instead of remaining blank.
Fixed by passing `" "` (space) when there is no event to display.

---

## v1.11 — 2026-06-09

### Logic — block new entries on exhausted band + counters in dashboard

**Entry blocking (STATE_IDLE):**
When a band reaches `TOUCH_WARN_COUNT` (3) or more touches, the EA stops
opening new initial entries on that side. The opposite side (if still valid)
continues to operate normally. Scale-ins on already-open positions are
not affected.

```
topValid = !g_topUnstable || g_topTouchCount < TOUCH_WARN_COUNT
botValid = !g_botUnstable || g_botTouchCount < TOUCH_WARN_COUNT
```

**Touch counters visible in dashboard (Box line):**
The block info line now shows the number of touches per band:

```
Box  3321.08 – 3315.56  [ 55.2 p ]  ↑1t ↓2t
Box  3321.08 – 3315.56  [ 55.2 p ]  ↑1t !↓3t   ← "!" when exhausted
```

**Counter behaviour with block growth:**
- Small growth (band moves < zs): counter persists — incremental history
- Large growth (new reference triggered): counter resets to 0

---

## v1.10 — 2026-06-09

### Visual — third colour on block margins (touch counter)

Before: margins were blue (untouched) or amber (touched ≥ 1×) — only two states.

Now there are three states per margin, with automatic reset if the band
expands to a new extreme (the block "shifted" its reference):

| Touches on margin | Band colour | Meaning |
|---|---|---|
| 0 – 1 | Blue `C'194,209,242'` | Normal — first entry |
| 2 – N-1 | Amber `C'240,214,153'` | Warning — band already tested |
| ≥ N (default 3) | Light red `C'255,153,153'` | Alert — band heavily tested |

**Configurable threshold:** `#define TOUCH_WARN_COUNT 3` — change to adjust
how many touches trigger the red colour.

**New globals:** `g_botTouchCount` · `g_topTouchCount` (int, reset on new
block or band expansion).

**No impact on trading logic** — visual only.

---

## v1.09 — 2026-06-09

### Fix — `SyncCalendarToFile()` dedup and whitelist

**Problem:** the MT5 calendar sometimes returns two entries for the same event
(slightly different names or incorrect time offset), resulting in duplicates
in the CSV that caused the bot to block twice for the same event.

**Improved dedup:** instead of comparing only the exact datetime, now compares
by **date + normalised name (case-insensitive)**:
- Same event on the same day → duplicate ignored
- Same event, later time → time corrected to the earlier one (fixes entries
  3 h ahead caused by the `SERVER_OFFSET` bug in previous versions)

**Expanded whitelist:** added `"existing home sales"` and `"new home sales"`
to be included automatically in the sync.

**CSV regenerated:** the `fvg_news.csv` file was deleted to force a clean
regeneration on the next EA start.

---

## v1.08 — 2026-06-09

### Fix — Dashboard HiDPI/Mac scaling (`InpUIScale`)

On Mac with a Retina screen (or any HiDPI display), `OBJ_BITMAP_LABEL` renders
the bitmap in **physical pixels** (1:1 mapping), while label coordinates
(`CORNER_LEFT_LOWER`, `YDISTANCE`) use **logical pixels** (already scaled by
the OS). Result: the background appeared at half the visual size and the text
"leaked" outside it.

**Solution:** new input parameter `InpUIScale` (default = 1).

| Value | When to use |
|---|---|
| `1` | Windows / Mac non-Retina screen (previous behaviour) |
| `2` | Mac Retina screen / HiDPI 1920 × 1080 |

With `InpUIScale = 2`:
- Bitmap created at `DASH_PAN_W × 2` by `DASH_PAN_H × 2` physical pixels
  → on Retina occupies exactly `DASH_PAN_W × DASH_PAN_H` logical pixels ✓
- Label coordinates (`XDISTANCE`, `YDISTANCE`) multiplied by 2
  → remain aligned inside the bitmap ✓
- Panel positioning (`panTop`) uses `DASH_PAN_H × InpUIScale`
  → background correctly pinned to the chart's bottom margin ✓

**No impact on trading logic** — visual only.

---

## v1.07 — 2026-06-09

### Dashboard — next-event preview line

New line in the dashboard (between the status and box info rows) that warns
in advance when the bot is about to stop, before it actually happens.

**Three display modes (decreasing priority):**

| Situation | Text | Colour |
|---|---|---|
| Session pause starts in < 60 min | `▸ ⏸ NY Forex pause  in 23m` | Amber |
| News pre-block starts in < 90 min | `▸ NEWS NFP 15:30  stops in 45m` | Amber |
| News within 8 hours (informational) | `◦ NFP 15:30  in 3h05m` | Dim |
| No upcoming events | *(empty line)* | — |

**New functions:** `GetNextSessionPauseStart()` · `GetNextNewsInfo()`

**Layout adjustments:** `DASH_PAN_H` 155 → 179 px · `N_DASH0` y=145 → y=169 · `N_DASHN` new at y=145

---

## v1.06 — 2026-06-07

### Change — `InpMinOrderDist` external input

`MIN_ORDER_DIST` (previously a compile-time `#define` of 130.0 pips) is now an
external input parameter, allowing changes directly in the Strategy Tester
without recompiling.

- Default: **130.0 pips** (behaviour unchanged)
- Appears in the EA parameter dialog as **"Min distance to double position (pips)"**
- Used in backtests via the Optimisation tab to find the best martingale distance

---

## v1.05 — 2026-06-07

### Change — `GetLots()` formula

Replaced the linear balance formula with a square-root curve that grows more
slowly and stays at 0.01 lot for longer, protecting smaller accounts:

```
lots = 0.01 × MAX(1;  1 + FLOOR( (√(2×Balance − 700) − 30) / 20 ;  1))
```

| Balance range | Lots |
|---|---|
| < $1 600 | 0.01 |
| $1 600 – $2 799 | 0.02 |
| $2 800 – $4 399 | 0.03 |
| $4 400 – $6 399 | 0.04 |

Previous formula (`ROUND((Balance−400)/800)/100 + 0.01`) scaled more
aggressively (0.02 from $800, 0.03 from $1 600).

`InpFixedLots > 0` continues to override the formula unconditionally.

---

## v1.04 — 2026-06-07

### Dashboard — unified panel with countdown timer

**Consolidated**: the separate top-left status label (`N_INFO`) is removed. All
information now lives in a single bottom-left panel — no scattered labels.

**Status row** (top of panel): shows the bot's current state with a colour-coded dot:
- `◉ ACTIVE` — green
- `▶ NEWS  <EventName>  » 12m30s` — amber, with event name and countdown to resume
- `⏸ <Session> pause  » 8m15s` — amber, with session name and countdown to resume
- `■ PAUSED (web panel)` — red

**Box info row**: directly below the status row, shows the active FVG block's
high/low/size (`Box 4331.08 – 4325.56 [ 55.2 pips ]`).

**Timer logic**:
- `GetNewsBlockInfo()` — returns seconds until `event_time + NEWS_POST_SEC` and event name
- `GetSessionPauseInfo()` — returns seconds until `sessionOpen + PAUSE_WINDOW_MIN` and session name
- `FormatTimer()` — `< 1 h` → `"12m30s"`; `≥ 1 h` → `"1h05m"`

**Visual**:
- Panel size: 325 × 155 px (was 295 × 106 px)
- Background: `ColorToARGB(C'10,13,24', 220)` — true semi-transparent dark glass
- Border: `C'55,80,160'` cobalt
- Row spacing: 24 px, YDISTANCE 145 / 121 / 93 / 69 / 45 / 21

---

## v1.03 — 2026-06-04

### Change
- **`InpFixedLots` external input** — replaces the compile-time `#define FIXED_LOTS`.
  Setting it to `0.0` (default) keeps the automatic balance-scaled formula.
  Setting it to any positive value (e.g. `0.02`) fixes the initial lot without recompiling.
  Scale-in lots continue to double the last position's lot regardless of this setting.

---

Commercial build of the FVG Block strategy, specialised for XAUUSD M1.
Based on FvgBlock v3.87. No external inputs — all settings are `#define` constants.

---

## v1.02 — 2026-06-04

### Features
- **`FIXED_LOTS` constant** — optional fixed initial lot size.
  Set `FIXED_LOTS > 0.0` to override the automatic formula; `0.0` uses `GetLots()`.

### Visual
- **New colour scheme** — frosted-glass cobalt blue replaces the vivid orange/magenta:
  - `C_MIDBODY`  `C'224,232,247'` — body fill (15 % cobalt on white)
  - `C_EXTREME`  `C'194,209,242'` — top/bottom zone bands (30 %)
  - `C_MIDBAND`  `C'163,185,237'` — centre accent band (45 %)
  - `C_BORDER`   `C'50,100,210'`  — solid cobalt outline and labels
  - `C_UNSTABLE` `C'240,214,153'` — amber warning when zone is unstable
- Centre band (`N_MBAND`) now uses the distinct `C_MIDBAND` instead of the same
  colour as the extreme zones — creates a visible depth gradient.

### Dashboard redesign
- **Dark navy card** (`C'22,27,40'`) with cobalt border — readable on any chart
  background (white or dark); previous alpha-blended background was illegible on
  light charts.
- **Data fix — cycle counter**: `Cycles` now counts only *initial* cycle entries
  (comments `AUR_SL`, `AUR_SM`, `AUR_BL`, `AUR_BM`). Scale-in entries
  (`AUR_SS`, `AUR_BS`) are excluded. Previously every individual entry was counted,
  inflating the number by the average martingale depth.
- **Data fix — cycle grouping**: EXIT deals are now grouped by *direction* within a
  30-second window (previously 5 s, no direction check). Prevents mixing unrelated
  BUY and SELL closes and handles martingale cycles where multiple positions close
  within seconds of each other.
- **Smart duration format**: values under 60 min show as `Xm`; values above show
  as `Xh Ym` (e.g. `1h56m`).
- Colour hierarchy: gold title → steel-blue stats → dimmed breakeven → green above-BE.

---

## v1.01 — 2026-06-03

### Bug fix — news calendar timezone
- **`SyncCalendarToFile()`**: restored `- SERVER_OFFSET * 3600` subtraction.
  `MqlCalendarValue.time` was confirmed (via live debug log) to be in broker server
  time (UTC+3), not UTC. Removing the subtraction caused new events to be written
  3 hours ahead of their actual UTC time (e.g. ADP at `15:15` instead of `12:15`).
- **Debug print removed** from `SyncCalendarToFile()` (TZ-CHECK confirmed correct).

### News calendar — whitelist expansion
- Added keywords: `"gross domestic product"`, `"durable goods"`,
  `"average hourly earnings"`, `"unemployment claims"`, `"jobless claims"`,
  `"jolts"`, `"job openings"`, `"fed member"`, `"fomc member"`.
- `"gdp"` substring was not matching `"Gross Domestic Product Annualized"` —
  full phrase added.
- Extended importance filter to include `CALENDAR_IMPORTANCE_MODERATE` (orange
  events) in addition to `CALENDAR_IMPORTANCE_HIGH` (red events).

### News calendar — event name storage
- `LoadNewsFile()` now populates a parallel `g_newsNames[]` array alongside
  `g_newsEvents[]`, enabling named diagnostics.
- `PrintUpcomingNews(int maxEvents)` added: on every news reload, prints the next
  N upcoming events in local UTC+1 time to the Experts log. Used to verify UTC
  conversion against Forex Factory without running a backtest.

### fvg_news.csv
- Rebuilt with correct UTC times cross-referenced against Forex Factory.
- Orange-impact events added for all months: JOLTS, ADP, Unemployment Claims,
  ISM Services PMI, Retail Sales, FOMC Press Conference, Powell Speeches.
- Jun 25 corrected from `PCE` (wrong) to `GDP Annualized + Durable Goods`.
- Powell Speech Jun 1 corrected to `00:30 UTC` (was `03:30`, 3 h off due to
  server-time bug in earlier sync).

---

## v1.00 — 2026-06-03

Initial release. Ported from FvgBlock v3.87. Key additions over the source:

### Architecture
- **No external inputs** — all tunable values are `#define` / compile-time constants.
  Users recompile to change settings; no accidental parameter changes at runtime.
- **Magic number** `20250528` — compatible with the FvgBlock web control panel.

### Session pause windows
New function `IsSessionPauseTime()` blocks new entries and cancels pending limits
during the ±`PAUSE_WINDOW_MIN` (15 min) window around each major session open.
Existing positions remain open and TP break-even continues to be calculated.

| Session   | Opens (UTC+1 summer) | Block window       |
|-----------|---------------------|--------------------|
| Sydney    | 23:00               | trading starts 23:15 (no pause) |
| Tokyo     | 01:00               | 00:45 – 01:15      |
| London    | 08:00               | 07:45 – 08:15      |
| NY Forex  | 13:00               | 12:45 – 13:15      |
| NYSE      | 14:30               | 14:15 – 14:45      |

### Asymmetric news filter
- Block window: **135 min before** the event → **15 min after** (previously ±15 min).
- `NEWS_PRE_SEC = 8100` (135 × 60), `NEWS_POST_SEC = 900` (15 × 60).

### External news calendar (single source of truth)
- `fvg_news.csv` in `%APPDATA%\MetaQuotes\Terminal\Common\Files\` is the only
  source read by both live trading and backtesting.
- **Live**: `SyncCalendarToFile()` merges new USD high-impact events from the MT5
  native economic calendar into the CSV daily (dedup, sort, history preserved).
- **Backtest**: Strategy Tester has no calendar API → reads the same CSV directly,
  so historical blocks are reproducible.
- Reload on day change — no EA restart required after news updates.

### Automatic lot sizing
`GetLots()` scales the initial lot with account balance:
```
lot = ROUND((Balance − 400) / 800) / 100 + 0.01
```
Examples: $400 → 0.01 | $1 200 → 0.02 | $2 000 → 0.03.
Scale-in lots continue to double the last position's lot regardless.

### Dashboard overlay
`OBJ_RECTANGLE_LABEL` panel, bottom-left corner, showing:
- Cycles today / week
- Duration min / avg / max (per closed position)
- Breakeven cycles (net ≤ $0.10 after cost)
- Above BE cycles (net > $0.10)

### Status label enhancements
Top-left label shows active state prefix:
- `⏸ PAUSED` (red) — web panel pause flag active
- `⏸ SESSION PAUSE` (yellow) — within session open window
- `📰 NEWS BLOCK` (yellow) — within news filter window

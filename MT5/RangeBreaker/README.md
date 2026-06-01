# RangeBreaker

**Platform:** MetaTrader 5  
**Files:**
- `RangeBreaker.mq5` — v1.33, last updated **2026-01-11** (current)
- `SessionHighLowEA.mq5` — v1.0, last updated **2026-02-10** (earlier version, kept for reference)

## What it does

Session range breakout EA with support for up to 5 independently configured trading sessions. For each session it measures the High/Low of the first N candles, then places BUY STOP and SELL STOP orders at ±1× range beyond the session boundaries. If the entry is filled, the opposing pending order is cancelled automatically.

## Sessions (default configuration)

| # | Name | Start | End | Colour |
|---|---|---|---|---|
| 1 | Sydney | 01:00 | 09:00 | Blue |
| 2 | Tokyo | 03:00 | 12:00 | Pink |
| 3 | London | 10:00 | 19:00 | Aqua |
| 4 | New York | 15:00 | 00:00 | Gold |
| 5 | NYSE | 16:30 | 23:00 | Orchid |

All sessions are independently configurable: name, time window, timeframe, candle count, and colour.

## Level calculation

```
  BUY STOP entry  = session_high + range        TP = entry + 2 × range
  ─────────────── session_high (H) ─────────────
  ─────────────── session_low  (L) ─────────────
  SELL STOP entry = session_low  − range        TP = entry − 2 × range

  SL for BUY  = session_low  − 0.5 × range
  SL for SELL = session_high + 0.5 × range
```

## Entry modes

**Pending orders (default):** BUY STOP and SELL STOP are placed as soon as the analysis period ends. The EA cancels the opposing order when one fills.

**Confirmation mode (`WaitForConfirmation = true`):** Instead of placing pending orders, the EA draws dotted entry lines on the chart and waits. It fires a **market order** only when the previous confirmation candle (configurable timeframe) closes beyond the entry level.

## Session lifecycle

```
New day detected
  └─ Reset all session data and remove chart objects

For each enabled session (checked every 60 seconds):
  │
  ├─ Session time not yet reached → skip
  │
  ├─ Session started → record aligned start time
  │     Wait for analysis period to complete
  │     (candle_count × timeframe duration)
  │
  ├─ Analysis period complete → measure H/L, calculate levels
  │     Range within MinRange–MaxRange?
  │         Yes → place pending orders (or draw entry lines)
  │         No  → skip session
  │
  └─ Session ended → draw final H/L lines on chart
```

## New session invalidation

When `CancelPendingOrdersIfNewSessionStarts = true`, any pending orders from previous sessions are cancelled when a newer session's analysis completes. This prevents old setups from filling during a different market context.

## Risk & lot sizing

Lot is calculated using `OrderCalcProfit` to determine the exact loss per lot at the SL distance, then scaled to risk `RiskPercent` of account balance. Margin is verified before placing each order.

## GUI Dashboard

An on-chart dashboard shows live statistics per session:

```
Range Breaker EA Dashboard                        Runtime: Xh Ym
──────────────────────────────────────────────────────────────────
SESSION          TRADES    WINS    LOSSES    P/L ($)    AVG RNG
──────────────────────────────────────────────────────────────────
Sydney               4       3         1       +45.20    0.00820
Tokyo                2       1         1        -5.10    0.00640
...
──────────────────────────────────────────────────────────────────
TOTAL               12       8         4       +85.30    0.00730
```

## Key parameters

| Group | Parameter | Default | Description |
|---|---|---|---|
| Session N | `SessionN_Enable` | true | Enable/disable session |
| Session N | `SessionN_StartTime` | varies | Session start HH:MM |
| Session N | `SessionN_EndTime` | varies | Session end HH:MM |
| Session N | `SessionN_Timeframe` | M5 | Candle timeframe for measurement |
| Session N | `SessionN_CandleCount` | 4 | Candles to define the range |
| Trading | `RiskPercent` | 0.5 | Risk % per trade |
| Trading | `MinRange` / `MaxRange` | 0 / 1000 | Range filter |
| Trading | `WaitForConfirmation` | false | Use confirmation candle entry |
| Trading | `ConfirmationCandle` | M1 | Confirmation timeframe |
| Trading | `CancelPendingOrdersIfNewSessionStarts` | true | Cancel old pending on new session |
| Days | `TradeOnMonday` … `TradeOnFriday` | true | Day-of-week filter |

## File history

`SessionHighLowEA.mq5` is an older build (v1.0) of the same EA code. It is kept for diffing and rollback but is not the active version. Both files are in this folder to make it clear they are the same project at different maturity levels.
